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
import '../services/local_model_service.dart';
import '../services/web_lookup.dart';
import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../widgets/brutal_activate.dart';
import '../widgets/brutal_field.dart';
import '../theme/motion_tokens.dart';
import '../widgets/brutal_button.dart';
import '../widgets/brutal_chip.dart';
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
    required List<String> objects,
    required String? youTubeApiKey,
  })? lookupOverride;

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

  /// Which path answered, per assistant message id, for the life of this screen.
  ///
  /// In memory only, and deliberately so. Chat history is restored from the
  /// `chat` box as [ChatMessage]s with no provenance field, and a message
  /// restored from disk gets no line rather than a guessed one -- the honest
  /// state for an answer whose origin this process did not witness. Adding a
  /// Hive field for it would mean a model migration for a caption.
  final Map<String, ({ChatAnswerSource source, String? loadFailure})>
      _answerOrigins = {};
  bool _sending = false;
  List<String> _recentQueries = [];
  ScreenshotProvider? _screenshotProvider;
  int _deletionRevision = 0;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<ScreenshotProvider>();
    if (!identical(_screenshotProvider, provider)) {
      _screenshotProvider?.removeListener(_onProviderChanged);
      _screenshotProvider = provider;
      provider.addListener(_onProviderChanged);
    }
    _syncDeletionRevision(provider);
  }

  void _onProviderChanged() {
    final provider = _screenshotProvider;
    if (provider == null || !mounted) return;
    final revision = provider.deletionRevision;
    if (revision == _deletionRevision) return;
    _deletionRevision = revision;
    setState(_clearInMemoryTranscript);
  }

  void _syncDeletionRevision(ScreenshotProvider provider) {
    if (provider.deletionRevision == _deletionRevision) return;
    _deletionRevision = provider.deletionRevision;
    _clearInMemoryTranscript();
  }

  void _clearInMemoryTranscript() {
    _messages = [];
    _sources.clear();
    _streamingIds.clear();
    _answerOrigins.clear();
    _recentQueries = [];
    _sending = false;
  }

  @override
  void dispose() {
    _screenshotProvider?.removeListener(_onProviderChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMessages() async {
    final provider = context.read<ScreenshotProvider>();
    final revision = provider.deletionRevision;
    final box = Hive.box('chat');
    final history = box.get('history');
    if (history != null &&
        mounted &&
        !provider.isDeleting &&
        provider.deletionRevision == revision &&
        _deletionRevision == revision) {
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
    final provider = _screenshotProvider ?? context.read<ScreenshotProvider>();
    final revision = provider.deletionRevision;
    if (provider.isDeleting || revision != _deletionRevision) return;
    final box = Hive.box('chat');
    await box.put('history', _messages.map((m) => m.toJson()).toList());
    if (provider.isDeleting || provider.deletionRevision != revision) {
      await box.delete('history');
    }
  }

  Future<void> _loadRecentQueries() async {
    final provider = context.read<ScreenshotProvider>();
    final revision = provider.deletionRevision;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history') ?? const [];
    if (mounted &&
        !provider.isDeleting &&
        provider.deletionRevision == revision &&
        _deletionRevision == revision) {
      setState(() => _recentQueries = history);
    }
  }

  Future<void> _recordQuery(String text) async {
    final provider = _screenshotProvider ?? context.read<ScreenshotProvider>();
    final revision = provider.deletionRevision;
    if (provider.isDeleting || revision != _deletionRevision) return;
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
    if (provider.isDeleting || provider.deletionRevision != revision) {
      await prefs.remove('chat_history');
      return;
    }
    if (mounted && _deletionRevision == revision) {
      setState(() => _recentQueries = history);
    }
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _controller.text).trim();
    await _runQuery(text, addUser: true);
  }

  bool _queryIsCurrent(ScreenshotProvider provider, int revision) {
    return !provider.isDeleting &&
        provider.deletionRevision == revision &&
        _deletionRevision == revision;
  }

  Future<void> _runQuery(String text, {required bool addUser}) async {
    if (text.isEmpty || _sending) return;
    final provider = _screenshotProvider ?? context.read<ScreenshotProvider>();
    final queryRevision = provider.deletionRevision;
    if (!_queryIsCurrent(provider, queryRevision)) return;
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
      if (!_queryIsCurrent(provider, queryRevision)) {
        if (mounted) setState(() => _sending = false);
        return;
      }
    } else {
      setState(() => _sending = true);
    }
    if (!mounted || !_queryIsCurrent(provider, queryRevision)) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    _scrollToBottom();

    try {
      final results = provider.search(text);

      // Nullable read: a screen without the model still chats, it just keeps
      // the plain local reply in local-only mode.
      final localModel = context.read<LocalModelService?>()?.model;

      final engine = ChatEngine(
        lam: context.read<LAMService>(),
        consentCheck: () => showPrivacyConsentIfNeeded(context),
        lookup: widget.lookupOverride ?? WebLookupService().lookup,
        localModel: localModel,
      );
      final replyResult = await engine.reply(
        text: text,
        results: results,
        localOnly: provider.localOnly,
      );
      if (!_queryIsCurrent(provider, queryRevision)) return;
      final reply = replyResult.content;
      final relatedLinks = replyResult.relatedLinks;

      if (replyResult.blocked) {
        if (!mounted || !_queryIsCurrent(provider, queryRevision)) return;
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
          _answerOrigins[blockedMsg.id] = (
            source: replyResult.source,
            loadFailure: replyResult.loadFailure,
          );
        });
        await _saveMessages();
        return;
      }

      await _ensureMinTyping(startedAt);
      if (!mounted || !_queryIsCurrent(provider, queryRevision)) return;

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
        _answerOrigins[asstMsg.id] = (
          source: replyResult.source,
          loadFailure: replyResult.loadFailure,
        );
      });
      await _saveMessages();
    } catch (e) {
      debugPrint('Chat error: ${e.toString()}');
      await _ensureMinTyping(startedAt);
      if (!mounted || !_queryIsCurrent(provider, queryRevision)) return;
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
        _answerOrigins.remove(removed.id);
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
          BrutalButton.text(
            onPressed: () => Navigator.pop(context, false),
            label: const Text('Cancel'),
          ),
          BrutalButton(
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
        _answerOrigins.clear();
        _recentQueries = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localOnly = context.watch<ScreenshotProvider>().localOnly;
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
                  : _buildConversation(context, localOnly: localOnly),
            ),
          ),
          if (_messages.isNotEmpty) _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final s = AppTheme.of(context);
    final provider = context.watch<ScreenshotProvider>();
    final isLocal = provider.localOnly;

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
          // Subtle privacy mode indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLocal ? s.surfaceWarm1 : s.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLocal ? Icons.phone_rounded : Icons.cloud_rounded,
                  size: 12,
                  color: isLocal ? s.graphite : s.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  isLocal ? 'Local' : 'Cloud',
                  style: SiftType.microLabel.copyWith(
                    color: isLocal ? s.graphite : s.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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
            'Screenshot images and OCR text stay on this device. Google Play services may download the small image-labeling model on first use. The optional on-device chat model is not bundled: SIFT downloads it once from Hugging Face when you set it up, then runs it on this device with LiteRT-LM. Cloud chat sends screenshot-derived text and context to your chosen provider, and optional source lookup can query the web. Local-only mode prevents cloud chat and source lookup.',
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

  Widget _buildConversation(
    BuildContext context, {
    required bool localOnly,
  }) {
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
        return _buildTurn(_messages[index], localOnly: localOnly);
      },
    );
  }

  Widget _buildTurn(
    ChatMessage message, {
    required bool localOnly,
  }) {
    final sources = _sources[message.id];
    final relatedLinks = message.relatedLinksForDisplay(localOnly: localOnly);
    final originLine = _answerOriginLine(_answerOrigins[message.id]);

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
          if (originLine != null) ...[
            const SizedBox(height: 10),
            _AnswerOriginLine(text: originLine),
          ],
          if (relatedLinks.isNotEmpty) ...[
            const SizedBox(height: 16),
            RelatedLinksStrip(links: relatedLinks),
          ],
        ],
      ),
    );
  }

  /// The one quiet line under an answer, saying which of the two produced it.
  ///
  /// Plain words on purpose, and no praise. The report this answers was "same
  /// results as if I hadn't downloaded the model", which was true: both paths
  /// rendered the same evidence strip and the same text shape. So the line names
  /// the difference in the terms the user acted on -- the model, or their own
  /// screenshot text -- and on the fallback path there was no model to be
  /// clever about, so nothing here implies otherwise.
  ///
  /// Null for a cloud answer. There the user picked the provider and was asked
  /// for consent before anything was sent, so the provenance is not in doubt and
  /// a second telling of it would just be noise. Null also when this process did
  /// not witness the reply: a message restored from the chat history carries no
  /// origin, and guessing one would be the same defect in a new place.
  static String? _answerOriginLine(
    ({ChatAnswerSource source, String? loadFailure})? origin,
  ) {
    if (origin == null) return null;
    final failure = origin.loadFailure?.trim();
    final line = switch (origin.source) {
      ChatAnswerSource.cloudAnswer || ChatAnswerSource.cloudUnavailable => null,
      ChatAnswerSource.onDeviceModel => 'Answered by the on-device model.',
      ChatAnswerSource.noResults =>
        'Nothing matched, so the model was never asked.',
      ChatAnswerSource.noModel =>
        'No on-device model is set up. This is a keyword list of your '
            'screenshots.',
      ChatAnswerSource.modelNotReady =>
        'The on-device model was not ready. This is a keyword list of your '
            'screenshots.',
      ChatAnswerSource.modelLoadFailed =>
        'The on-device model could not be loaded on this device. This is a '
            'keyword list of your screenshots.',
      ChatAnswerSource.modelFailed =>
        'The on-device model stopped answering. This is a keyword list of your '
            'screenshots.',
      ChatAnswerSource.modelEmpty =>
        'The on-device model had nothing to add. This is a keyword list of your '
            'screenshots.',
    };
    if (line == null) return null;
    // The model's own explanation, in its own vetted words. Appended rather
    // than replacing the line above: the user needs both what answered and why
    // the model did not, and the reason is the part they can act on.
    if (failure == null || failure.isEmpty) return line;
    return '$line $failure';
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

/// Paper field (r4, 2pt stone border -> 2pt focus ring) + 40pt send circle
/// (accentDeep when there is text, surfaceWarm2 when empty). The focus
/// listener stays on the field's node because it is also what refreshes
/// `hasText` when the user types without submitting.
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
          child: BrutalField(
            height: 52,
            // The ring tracks the field's own node, exactly as it did when this
            // row read `_focus.hasFocus` itself.
            focusNode: _focus,
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
        SiftSendCircle(
          enabled: hasText && !widget.sending,
          onPressed: widget.onSend,
        ),
      ],
    );
  }
}

/// The composer's send button.
///
/// Public because it is a control, not a screen detail: DESIGN-BRUTALIST.md §7.6
/// records it as the one interactive element left outside the brutal control
/// system, and the only way to keep it inside is to test it on its own rather
/// than by mounting the whole screen around it.
///
/// §2.5 excludes circular icon buttons from the hard-edge treatment — a cast
/// shadow fights a circle's curvature — and that exclusion is honoured: the
/// press-scale, the fill and the shape are all exactly as they were. What it
/// over-reached on was FOCUS, which is not a shape question. So the ring is a
/// 2pt `BoxDecoration` border on the same circle, which follows the curve
/// instead of boxing it in, and it uses the page-step/slab rule the rest of the
/// system uses (§6.10): `accentDeep` is a slab, so the ring is the slab pair,
/// while the disabled `surfaceWarm2` fill is a page step and takes the plain one.
class SiftSendCircle extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const SiftSendCircle({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<SiftSendCircle> createState() => _SiftSendCircleState();
}

class _SiftSendCircleState extends State<SiftSendCircle> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (widget.enabled && MotionTokens.enabled) {
      setState(() => _pressed = value);
    }
  }

  void _setFocused(bool value) {
    if (value == _focused) return;
    setState(() => _focused = value);
  }

  /// One body for the tap and for Enter, so the keyboard can never reach a
  /// different outcome than the pointer. [brutalActivate] is handed null while
  /// disabled, which swallows the intent rather than letting it fire a send the
  /// pointer is not allowed to make.
  void _send() {
    if (!widget.enabled) return;
    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Send message',
      child: brutalActivate(
        onActivate: widget.enabled ? _send : null,
        child: Focus(
          onFocusChange: _setFocused,
          child: GestureDetector(
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: widget.enabled ? _send : null,
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
                  // A border on a circular shape paints as a circular ring
                  // inside the shape, which is what keeps the indicator on the
                  // circle instead of squaring it off (§6.10: the border is
                  // drawn ON TOP OF the fill, so it is scored against the fill).
                  border: _focused
                      ? Border.all(
                          color: widget.enabled
                              ? SiftBrutal.focusOnFill(isDark: isDark)
                              : SiftBrutal.focus(isDark),
                          width: SiftBrutal.borderW,
                        )
                      : null,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: widget.enabled ? s.onAccent : s.stone,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The provenance line under an answer: one sentence, meta-sized, in the
/// quietest ink on the page.
///
/// Not an error banner and not a badge. Every branch of `_localReply` that is
/// not the model reaching an answer is not an error either -- "you have not
/// downloaded it" is a state, not a mistake -- and dressing the honest ones up
/// as failures would train the reader to ignore the line that matters, the one
/// saying the model did answer. Meta label rather than body copy because this
/// qualifies the answer; it is not part of it.
class _AnswerOriginLine extends StatelessWidget {
  final String text;

  const _AnswerOriginLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    return Text(
      text,
      style: SiftType.metaLabel.copyWith(color: s.stone, height: 1.4),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SiftBrutalChip(
      label: label,
      rest: SiftChipRest.warm,
      onTap: () {
        if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}
