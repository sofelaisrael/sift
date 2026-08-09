import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/sift_mark.dart';
import 'app_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_complete') ?? false);
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    await OnboardingScreen.markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.ashDark
                              : AppTheme.ashLight,
                        ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: 3,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  return _buildPage(context, index);
                },
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final active = _currentPage == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.emberMain
                        : Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.hairDark
                            : AppTheme.hairLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _currentPage == 2
                      ? _completeOnboarding
                      : () {
                          _pageController.nextPage(
                            duration: Motion.emphasis,
                            curve: Curves.easeOutCubic,
                          );
                        },
                  child: Text(
                    _currentPage == 2 ? 'Start Sifting' : 'Next',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    switch (index) {
      case 0:
        return _buildPromise(context);
      case 1:
        return _buildMockExchange(context);
      default:
        return _buildTrust(context);
    }
  }

  Widget _buildPromise(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80,
            height: 80,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const SiftMark(size: 44),
          ),
          const SizedBox(height: 40),
          Text(
            'Remember everything you screenshot.',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Sift understands what you save and brings it back the moment you ask.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
          const SizedBox(height: 48),
          Text(
            'Your screenshots live on this device. AI analysis sends images to the provider you pick — Local-only mode keeps everything on-device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockExchange(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask in plain words.',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'See how Sift pulls up exactly what you need.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppTheme.emberMain,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.rXl),
                  topRight: Radius.circular(AppTheme.rXl),
                  bottomLeft: Radius.circular(AppTheme.rXl),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                'What was that flight price I screenshotted?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.emberInk,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.rXl),
                  topRight: Radius.circular(AppTheme.rXl),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(AppTheme.rXl),
                ),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                r'You saved a Google Flights result on Jan 12 — round trip to Lisbon, $540.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                _mockThumb(context, Icons.flight_rounded),
                const SizedBox(width: 6),
                _mockThumb(context, Icons.attach_money_rounded),
                const SizedBox(width: 8),
                Text(
                  'Read from 2 screenshots',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Every answer is grounded in a screenshot you saved.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                ),
          ),
        ],
      ),
    );
  }

  Widget _mockThumb(BuildContext context, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(icon, size: 18, color: AppTheme.emberMain),
    );
  }

  Widget _buildTrust(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'On your device.',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Screenshots live on this device. AI analysis sends images to the provider you pick — Local-only mode keeps everything on-device.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
          const SizedBox(height: 32),
          _trustRow(context, Icons.lock_outline_rounded, 'Your data, your call'),
          _trustRow(context, Icons.storage_rounded, 'Stored locally'),
          _trustRow(context, Icons.verified_user_outlined, 'You stay in control'),
        ],
      ),
    );
  }

  Widget _trustRow(BuildContext context, IconData icon, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final ink = isDark ? AppTheme.inkDark : AppTheme.inkLight;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
          ),
        ],
      ),
    );
  }
}
