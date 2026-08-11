import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../services/chat_engine.dart';
import '../services/lam_service.dart';
import '../services/web_lookup.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/chat_atoms.dart';
import '../widgets/privacy_gate.dart';
import 'detail_screen.dart';

/// The Ask tab. Two phases: a quiet hero (serif headline + composer +
/// example chips) and the conversation (user pill -> evidence strip ->
/// serif essay block), with a docked composer above the nav.
class ChatScreen extends StatefulWidget {
  final FocusNode? askFocusNode;

  /// Test seam: replace the real web lookup (WebLookupService).
  final Future<List<WebResult>> Function({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required String? youTubeApiKey,
  })?
  lookupOverride;

  const ChatScreen({super.key, this.askFocusNode, this.lookupOverride});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _uuid = Uuid();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  final Map<String, List<Screenshot>> _sources = {};
  final Set<String> _streamingIds = {};
  bool _sending = false;
  List<String> _recentQueries = [];

  static const List<String> _examplePrompts = [
    'What recipes did I save?',
    'What was that flight to Lisbon?',
    'Find the Wi-Fi password',
    'Any deadlines coming up?',
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadMessages();
    _loadRecentQueries();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMessages() async {
    final box = Hive.box('chat');
    final history = box.get('history');
    if (history != null && mounted) {
      final provider = context.read<ScreenshotProvider>();
      final byId = {for (final s in provider.screenshots) s.id: s};
      final messages = (history as List)
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      setState(() {
        _messages = messages;
        _sources.clear();
        for (final m in messages) {
          if (!m.isUser && m.sourceIds.isNotEmpty) {
            _sources[m.id] = [
              for (final id in m.sourceIds)
                if (byId[id] != null) byId[id]!,
            ];
          }
        }
      });
    }
  }

  Future<void> _saveMessages() async {
    final box = Hive.box('chat');
    await box.put('history', _messages.map((m) => m.toJson()).toList());
  }

  Future<void> _loadRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history') ?? const [];
    if (mounted) {
      setState(() => _recentQueries = history);
    }
  }

  Future<void> _recordQuery(String text) async {
    final capped = text.length > 120 ? text.substring(0, 120) : text;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history') ?? <String>[];
    history
      ..remove(capped)
      ..insert(0, capped);
    if (history.length > 20) {
      history.removeRange(20, history.length);
    }
    await prefs.setStringList('chat_history', history);
    if (mounted) {
      setState(() => _recentQueries = history);
    }
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _controller.text).trim();
    await _runQuery(text, addUser: true);
  }

  Future<void> _runQuery(String text, {required bool addUser}) async {
    if (text.isEmpty || _sending) return;
    _controller.clear();

    final startedAt = DateTime.now();

    if (addUser) {
      final userMsg = ChatMessage(
        id: _uuid.v4(),
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(userMsg);
        _sending = true;
      });
      await _saveMessages();
      await _recordQuery(text);
    } else {
      setState(() => _sending = true);
    }
    if (!mounted) return;
    _scrollToBottom();

    try {
      final provider = context.read<ScreenshotProvider>();
      final results = provider.search(text);

      final engine = ChatEngine(
        lam: context.read<LAMService>(),
        consentCheck: () => showPrivacyConsentIfNeeded(context),
        lookup: widget.lookupOverride ?? WebLookupService().lookup,
      );
      final replyResult = await engine.reply(
        text: text,
        results: results,
        localOnly: provider.localOnly,
      );
      final reply = replyResult.content;
      final relatedLinks = replyResult.relatedLinks;

      if (replyResult.blocked) {
        if (!mounted) return;
        final blockedMsg = ChatMessage(
          id: _uuid.v4(),
          role: 'assistant',
          content: reply,
          timestamp: DateTime.now(),
          sourceIds: results.map((s) => s.id).toList(),
        );
        _streamingIds.add(blockedMsg.id);
        setState(() {
          _messages.add(blockedMsg);
          _sources[blockedMsg.id] = results;
        });
        await _saveMessages();
        return;
      }

      await _ensureMinTyping(startedAt);
      if (!mounted) return;

      final asstMsg = ChatMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
        sourceIds: results.map((s) => s.id).toList(),
        relatedLinks: relatedLinks,
      );
      _streamingIds.add(asstMsg.id);
      setState(() {
        _messages.add(asstMsg);
        _sources[asstMsg.id] = results;
      });
      await _saveMessages();
    } catch (e) {
      debugPrint('Chat error: ${e.toString()}');
      await _ensureMinTyping(startedAt);
      if (!mounted) return;
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content:
            'Something went wrong while reaching your provider. Please try again in a moment.',
        timestamp: DateTime.now(),
      );
      _streamingIds.add(errMsg.id);
      setState(() => _messages.add(errMsg));
      await _saveMessages();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _ensureMinTyping(DateTime startedAt) async {
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = const Duration(milliseconds: 600) - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _regenerate() async {
    if (_sending) return;
    String? query;
    for (final m in _messages.reversed) {
      if (m.isUser) {
        query = m.content;
        break;
      }
    }
    if (query == null) return;

    setState(() {
      while (_messages.isNotEmpty && !_messages.last.isUser) {
        final removed = _messages.removeLast();
        _sources.remove(removed.id);
        _streamingIds.remove(removed.id);
      }
    });
    await _saveMessages();
    await _runQuery(query, addUser: false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MotionTokens.standard,
        curve: MotionTokens.easeOutCubic,
      );
    });
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('This deletes the conversation history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final box = Hive.box('chat');
    await box.delete('history');
    await (await SharedPreferences.getInstance()).remove('chat_history');
    if (mounted) {
      setState(() {
        _messages = [];
        _sources.clear();
        _streamingIds.clear();
        _recentQueries = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (_messages.isNotEmpty) _buildHeader(context),
          Expanded(
            child: AnimatedSwitcher(
              duration: MotionTokens.emphasis,
              switchInCurve: MotionTokens.easeOutCubic,
              switchOutCurve: MotionTokens.easeInCubic,
              child: _messages.isEmpty
                  ? _buildHero(context)
                  : _buildConversation(context),
            ),
          ),
          if (_messages.isNotEmpty) _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ask',
              style: SiftType.serifTitle.copyWith(color: s.ink),
            ),
          ),
          IconButton(
            tooltip: 'Clear chat',
            onPressed: _clearChat,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: s.stone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final s = AppTheme.of(context);

    return SingleChildScrollView(
      key: const ValueKey('hero'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What would you like to remember?',
            style: SiftType.serifDisplay.copyWith(color: s.ink),
          ),
          const SizedBox(height: 10),
          Text(
            'Ask in plain words. Sift answers from the screenshots you saved.',
            style: SiftType.bodySans.copyWith(
              color: s.graphite,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _ComposerRow(
            controller: _controller,
            focusNode: widget.askFocusNode,
            sending: _sending,
            onSend: _send,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _examplePrompts
                .map((p) => _PromptChip(label: p, onTap: () => _send(p)))
                .toList(),
          ),
          if (_recentQueries.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Recent',
              style: SiftType.metaLabel.copyWith(
                color: s.stone,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentQueries
                  .map((q) => _PromptChip(label: q, onTap: () => _send(q)))
                  .toList(),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'Your screenshots stay on this device. AI analysis sends images to the provider you choose — or turn on Local-only mode in More.',
            style: SiftType.bodySansMd.copyWith(
              fontSize: 13,
              height: 1.45,
              color: s.stone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('conversation'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 32),
            child: TypingRow(),
          );
        }
        return _buildTurn(_messages[index]);
      },
    );
  }

  Widget _buildTurn(ChatMessage message) {
    final sources = _sources[message.id];

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: UserPill(text: message.content),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sources != null && sources.isNotEmpty) ...[
            EvidenceStrip(
              sources: sources,
              partial: sources.any(
                (s) => s.confidence != null && s.confidence! < 0.5,
              ),
              onOpen: (s) => _openDetail(s),
            ),
            const SizedBox(height: 16),
          ],
          EssayBlock(
            text: message.content,
            timestamp: message.timestamp,
            stream: _streamingIds.contains(message.id),
            onRegenerate:
                message.id == _messages.lastOrNull?.id ? _regenerate : null,
          ),
          if (message.relatedLinks.isNotEmpty) ...[
            const SizedBox(height: 16),
            RelatedLinksStrip(links: message.relatedLinks),
          ],
        ],
      ),
    );
  }

  void _openDetail(Screenshot screenshot) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(screenshot: screenshot),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.of(context).canvas,
      ),
      child: SafeArea(
        top: false,
        child: _ComposerRow(
          controller: _controller,
          focusNode: widget.askFocusNode,
          sending: _sending,
          onSend: _send,
        ),
      ),
    );
  }
}

/// Paper field (r16, 1pt hairline -> 1.5pt accent on focus) + 40pt send
/// circle (accentDeep when there is text, surfaceWarm2 when empty).
class _ComposerRow extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool sending;
  final VoidCallback onSend;

  const _ComposerRow({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  State<_ComposerRow> createState() => _ComposerRowState();
}

class _ComposerRowState extends State<_ComposerRow> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: MotionTokens.standard,
            curve: MotionTokens.easeOutCubic,
            height: 52,
            decoration: BoxDecoration(
              color: s.paper,
              borderRadius: BorderRadius.circular(SiftRadii.rField),
              border: Border.all(
                color: _focus.hasFocus ? s.accent : s.divider,
                width: _focus.hasFocus ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSend(),
              style: SiftType.bodySans.copyWith(color: s.ink),
              decoration: InputDecoration(
                hintText: 'Ask about anything you\'ve saved…',
                hintStyle: SiftType.bodySans.copyWith(
                  color: s.stone,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendCircle(
          enabled: hasText && !widget.sending,
          onPressed: widget.onSend,
        ),
      ],
    );
  }
}

class _SendCircle extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SendCircle({required this.enabled, required this.onPressed});

  @override
  State<_SendCircle> createState() => _SendCircleState();
}

class _SendCircleState extends State<_SendCircle> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.enabled && MotionTokens.enabled) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled
          ? () {
              if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
              widget.onPressed();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: MotionTokens.press,
        curve: MotionTokens.easeOutCubic,
        child: AnimatedContainer(
          duration: MotionTokens.pressRelease,
          curve: MotionTokens.easeOutCubic,
          width: SiftSpacing.sendBtn,
          height: SiftSpacing.sendBtn,
          decoration: BoxDecoration(
            color: widget.enabled ? s.accentDeep : s.surfaceWarm2,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 20,
            color: widget.enabled ? s.onAccent : s.stone,
          ),
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: SiftSpacing.chipH,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.surfaceWarm1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: SiftType.chipLabel.copyWith(color: s.ink),
          ),
        ),
      ),
    );
  }
}
