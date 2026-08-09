import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';
import '../models/chat_message.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../services/lam_service.dart';
import '../theme/app_theme.dart';
import '../widgets/privacy_gate.dart';
import 'detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final FocusNode? askFocusNode;

  const ChatScreen({super.key, this.askFocusNode});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _uuid = Uuid();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  final Map<String, List<Screenshot>> _sources = {};
  bool _sending = false;
  List<String> _recentQueries = [];

  static const List<String> _examplePrompts = [
    'Show me my flights',
    'What recipes did I save?',
    'Find the Wi-Fi password',
    'Any deadlines coming up?',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadRecentQueries();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final box = Hive.box('chat');
    final history = box.get('history');
    if (history != null && mounted) {
      setState(() {
        _messages = (history as List)
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList();
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
      setState(() {
        _recentQueries = history;
      });
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
      setState(() {
        _recentQueries = history;
      });
    }
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();

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
    _scrollToBottom();

    try {
      await _saveMessages();
      await _recordQuery(text);
      if (!mounted) return;

      final provider = context.read<ScreenshotProvider>();
      final results = provider.search(text);

      String reply;
      if (provider.localOnly) {
        reply = _buildLocalReply(results);
      } else {
        final ok = await showPrivacyConsentIfNeeded(context);
        if (!ok || !mounted) {
          if (!mounted) return;
          final blockedMsg = ChatMessage(
            id: _uuid.v4(),
            role: 'assistant',
            content: 'Privacy consent is required before Sift sends anything to an AI provider. You can grant it the next time you analyze a screenshot, or enable Local-only mode in Settings.',
            timestamp: DateTime.now(),
          );
          setState(() {
            _messages.add(blockedMsg);
            _sources[blockedMsg.id] = results;
          });
          await _saveMessages();
          return;
        }

        final lam = context.read<LAMService>();
        final prefs = await SharedPreferences.getInstance();
        final providerName =
            prefs.getString('provider') ?? AppConfig.defaultProvider;
        final savedKey = prefs.getString('key_$providerName') ?? '';
        final apiKey =
            savedKey.isNotEmpty ? savedKey : AppConfig.apiKeyFor(providerName);
        reply = await lam.chat(
          text,
          context: _buildContextText(results),
          apiKey: apiKey,
          provider: providerName,
        );
      }

      final asstMsg = ChatMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(asstMsg);
        _sources[asstMsg.id] = results;
      });
      await _saveMessages();
    } catch (e) {
      // Never surface raw exceptions to the user: provider errors can embed
      // the API key (e.g. in the request URI) and would be persisted in chat.
      debugPrint('Chat error: $e');
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: 'Sorry, I hit an error. Check your API key in More > Settings and try again.',
        timestamp: DateTime.now(),
      );
      setState(() => _messages.add(errMsg));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  String _buildContextText(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'No saved screenshots matched the query. Answer honestly that nothing matches.';
    }

    final sb = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final s = results[i];
      sb.writeln('[$i]');
      sb.writeln('  Summary: ${s.summary ?? 'No summary'}');
      if (s.description != null && s.description!.isNotEmpty) {
        sb.writeln('  Description: ${s.description}');
      }
      if (s.ocrText != null && s.ocrText!.isNotEmpty) {
        sb.writeln('  Text: ${s.ocrText}');
      }
      if (s.recognitions.isNotEmpty) {
        sb.writeln('  Recognitions: ${s.recognitions.join(', ')}');
      }
      if (s.lamType != null) {
        sb.writeln('  Type: ${s.lamType}');
      }
      sb.writeln('  Taken: ${s.timestamp.toIso8601String()}');
      sb.writeln();
    }
    return sb.toString();
  }

  String _buildLocalReply(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'Nothing found in your saved screenshots. '
          'Local-only mode searches on-device text only — no AI.';
    }
    final capped = results.take(5).toList();
    final sb = StringBuffer('Found ${results.length} matching screenshots:');
    for (final s in capped) {
      sb.write('\n• ${s.summary ?? 'No summary'}');
      if (s.recognitions.isNotEmpty) {
        sb.write(' (${s.recognitions.join(', ')})');
      }
    }
    return sb.toString();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Motion.standard,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.r2xl),
        ),
        title: const Text('Clear Chat?'),
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
        _recentQueries = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (_messages.isNotEmpty) _buildHeader(context),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _messages.isEmpty
                ? _buildHero(context)
                : _buildConversation(context, isDark),
          ),
        ),
        if (_messages.isNotEmpty) _buildComposer(context, isDark),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ask',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
          ),
          IconButton(
            onPressed: _clearChat,
            icon: Icon(
              Icons.delete_sweep_outlined,
              color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      key: const ValueKey('hero'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Ask your memory anything',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Plain words. Answers grounded in the screenshots you saved.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(AppTheme.rXl),
                    border: Border.all(
                      color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.askFocusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: 'Ask your memory…',
                      hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                          ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _EmberSendButton(enabled: !_sending, onPressed: _send),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _examplePrompts
                .map(
                  (p) => _PromptChip(label: p, onTap: () => _send(p)),
                )
                .toList(),
          ),
          if (_recentQueries.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'RECENT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                    letterSpacing: 0.8,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _recentQueries
                  .map(
                    (q) => _PromptChip(label: q, onTap: () => _send(q)),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'Screenshots stay on this device. AI analysis sends images to the provider you choose — or turn on Local-only mode.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(BuildContext context, bool isDark) {
    return ListView.builder(
      key: const ValueKey('conversation'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const _TypingIndicator();
        }
        return _buildBubble(_messages[index], isDark);
      },
    );
  }

  Widget _buildComposer(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(
                    color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: widget.askFocusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Ask your memory…',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                        ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _EmberSendButton(enabled: !_sending, onPressed: _send),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage message, bool isDark) {
    final isUser = message.isUser;
    final sources = _sources[message.id];
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.fromLTRB(
          14,
          isUser ? 10 : 12,
          14,
          isUser ? 8 : 10,
        ),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.emberMain
              : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppTheme.rXl),
            topRight: const Radius.circular(AppTheme.rXl),
            bottomLeft: Radius.circular(isUser ? AppTheme.rXl : 4),
            bottomRight: Radius.circular(isUser ? 4 : AppTheme.rXl),
          ),
          border: isUser
              ? null
              : Border.all(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isUser ? AppTheme.emberInk : null,
                  ),
            ),
            if (sources != null && sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SourceStrip(sources: sources),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isUser
                    ? AppTheme.emberInk.withValues(alpha: 0.7)
                    : (isDark ? AppTheme.ashDark : AppTheme.ashLight),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.chipH / 2),
        child: Container(
          height: AppTheme.chipH,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.chipH / 2),
            border: Border.all(
              color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ),
      ),
    );
  }
}

class _EmberSendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _EmberSendButton({required this.enabled, required this.onPressed});

  @override
  State<_EmberSendButton> createState() => _EmberSendButtonState();
}

class _EmberSendButtonState extends State<_EmberSendButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.enabled && Motion.enabled) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: Motion.press,
        curve: Curves.easeOutCubic,
        child: Material(
          color: widget.enabled
              ? AppTheme.emberMain
              : (Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.hairDark
                  : AppTheme.hairLight),
          shape: const CircleBorder(),
          child: SizedBox(
            width: AppTheme.sendBtn,
            height: AppTheme.sendBtn,
            child: Icon(
              Icons.send_rounded,
              size: 20,
              color: widget.enabled
                  ? AppTheme.emberInk
                  : (Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.ashDark
                      : AppTheme.ashLight),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceStrip extends StatefulWidget {
  final List<Screenshot> sources;

  const _SourceStrip({required this.sources});

  @override
  State<_SourceStrip> createState() => _SourceStripState();
}

class _SourceStripState extends State<_SourceStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = widget.sources.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < visible.length; i++)
              Padding(
                padding: EdgeInsets.only(right: i == visible.length - 1 ? 0 : 6),
                child: _buildThumb(visible[i], i, isDark),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
            children: [
              const TextSpan(text: 'Read from '),
              TextSpan(
                text: '${widget.sources.length}',
                style: const TextStyle(
                  color: AppTheme.emberMain,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: widget.sources.length == 1
                    ? ' screenshot'
                    : ' screenshots',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumb(Screenshot screenshot, int index, bool isDark) {
    final interval = Interval(
      index * 0.14,
      0.3 + index * 0.14,
      curve: Curves.easeOutCubic,
    );
    final curved = CurvedAnimation(parent: _controller, curve: interval);

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.scale(
            scale: 1.05 - 0.05 * curved.value,
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailScreen(screenshot: screenshot),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          child: Image.file(
            File(screenshot.filePath),
            width: AppTheme.thumb,
            height: AppTheme.thumb,
            fit: BoxFit.cover,
            cacheWidth: 96,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: AppTheme.thumb,
                height: AppTheme.thumb,
                color: isDark
                    ? AppTheme.surfaceContainerDark
                    : AppTheme.surfaceContainerLight,
                child: Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (Motion.enabled) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rXl),
            topRight: Radius.circular(AppTheme.rXl),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(AppTheme.rXl),
          ),
          border: Border.all(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              _buildDot(i, isDark),
            const SizedBox(width: 10),
            Text(
              'Searching your screenshots…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index, bool isDark) {
    final interval = Interval(
      index * 0.2,
      0.6 + index * 0.2,
      curve: Curves.easeInOutSine,
    );
    final opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: interval),
    );

    return AnimatedBuilder(
      animation: opacity,
      builder: (context, child) {
        return Opacity(
          opacity: Motion.reduced ? 0.8 : opacity.value,
          child: child,
        );
      },
      child: Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
