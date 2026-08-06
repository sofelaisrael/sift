import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// Single shell Scaffold hosting the floating bottom nav and the three
/// Scaffold-less tabs (Library / Ask / More) in an IndexedStack.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final FocusNode _askFocusNode = FocusNode();

  void _switchToAsk() {
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _askFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _askFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onAsk: _switchToAsk),
          ChatScreen(askFocusNode: _askFocusNode),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildNav(context),
    );
  }

  Widget _buildNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = context.select<ScreenshotProvider, int>(
      (p) => p.screenshots.length,
    );

    return Container(
      color: isDark ? AppTheme.bgDark : AppTheme.bgLight,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SafeArea(
        top: false,
        child: Container(
          height: AppTheme.navH,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
            borderRadius: BorderRadius.circular(AppTheme.r2xl),
            border: Border.all(
              color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
            ),
            boxShadow: AppTheme.raisedShadow(isDark),
          ),
          child: Row(
            children: [
              _NavTab(
                icon: Icons.photo_library_rounded,
                label: 'Library',
                active: _index == 0,
                count: count > 0 ? count : null,
                onTap: () => setState(() => _index = 0),
              ),
              _NavTab(
                icon: Icons.chat_bubble_rounded,
                label: 'Ask',
                active: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
              _NavTab(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                active: _index == 2,
                onTap: () => setState(() => _index = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const ember = AppTheme.emberMain;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;
    final ash = isDark ? AppTheme.ashDark : AppTheme.ashLight;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.r2xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: Motion.standard,
              child: Icon(
                icon,
                key: ValueKey('$label-$active'),
                size: 22,
                color: active ? ember : ash,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: Motion.standard,
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? ink : ash,
                      letterSpacing: 0.2,
                    ),
                    child: Text(label),
                  ),
                ),
                if (active && count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ember,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
