import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ingest_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// Single shell Scaffold hosting the flat paper bottom nav and the three
/// Scaffold-less tabs (Library / Ask / More) in an IndexedStack.
///
/// [initialTab] and [scrollToChecklist] support the onboarding "Set up Sift"
/// deep link: it lands on More with the "Get Sift ready" checklist scrolled
/// into view.
class AppShell extends StatefulWidget {
  final int initialTab;
  final bool scrollToChecklist;

  const AppShell(
      {super.key, this.initialTab = 0, this.scrollToChecklist = false});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _index;
  final GlobalKey _checklistKey = GlobalKey();
  final FocusNode _askFocusNode = FocusNode();
  bool _checklistRevealed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialTab.clamp(0, 2);
    if (widget.scrollToChecklist) {
      _checklistRevealed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealChecklist());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _askFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A long bulk pass shouldn't keep running while the app is backgrounded.
    if (state == AppLifecycleState.paused) {
      final ingest = context.read<IngestService>();
      if (ingest.isIngesting && !ingest.paused) ingest.pause();
    }
  }

  void _switchToAsk() {
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _askFocusNode.requestFocus();
    });
  }

  void _revealChecklist() {
    final ctx = _checklistKey.currentContext;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(
      ctx,
      duration: MotionTokens.emphasis,
      curve: MotionTokens.easeOutCubic,
      alignment: 0.02,
    );
  }

  void _switchTo(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    if (index == 2 && widget.scrollToChecklist && !_checklistRevealed) {
      _checklistRevealed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealChecklist());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onAsk: _switchToAsk),
          ChatScreen(askFocusNode: _askFocusNode),
          SettingsScreen(checklistKey: _checklistKey),
        ],
      ),
      bottomNavigationBar: _buildNav(context),
    );
  }

  Widget _buildNav(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: s.canvas,
        border: Border(
          top: BorderSide(
            color: s.divider,
            width: AppTheme.hairline(isDark),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: SiftSpacing.navH,
          child: Row(
            children: [
              _NavTab(
                icon: Icons.photo_rounded,
                label: 'Library',
                active: _index == 0,
                onTap: () => _switchTo(0),
              ),
              _NavTab(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Ask',
                active: _index == 1,
                onTap: () => _switchTo(1),
              ),
              _NavTab(
                icon: Icons.tune_rounded,
                label: 'More',
                active: _index == 2,
                onTap: () => _switchTo(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat paper tab: active = accent icon + ink label, inactive = stone.
/// Color-only 200ms lerp, no capsule, no indicator, no badge, no shadow.
class _NavTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  late Color _iconBegin;
  late Color _labelBegin;

  @override
  void initState() {
    super.initState();
    final s = AppTheme.of(context);
    _iconBegin = widget.active ? s.accent : s.stone;
    _labelBegin = widget.active ? s.ink : s.stone;
  }

  @override
  void didUpdateWidget(covariant _NavTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      final s = AppTheme.of(context);
      _iconBegin = oldWidget.active ? s.accent : s.stone;
      _labelBegin = oldWidget.active ? s.ink : s.stone;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final iconEnd = widget.active ? s.accent : s.stone;
    final labelEnd = widget.active ? s.ink : s.stone;

    return Expanded(
      child: InkWell(
        onTap: () {
          if (MotionTokens.canHaptic) HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: Semantics(
          selected: widget.active,
          button: true,
          label: widget.label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(begin: _iconBegin, end: iconEnd),
                duration: MotionTokens.standard,
                curve: MotionTokens.easeOutCubic,
                builder: (context, color, child) {
                  return Icon(widget.icon, size: 24, color: color);
                },
              ),
              const SizedBox(height: 3),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(begin: _labelBegin, end: labelEnd),
                duration: MotionTokens.standard,
                curve: MotionTokens.easeOutCubic,
                builder: (context, color, child) {
                  return Text(
                    widget.label,
                    style: SiftType.tabLabel.copyWith(color: color),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
