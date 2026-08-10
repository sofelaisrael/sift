import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/screenshot.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/chat_atoms.dart';
import '../widgets/sift_mark.dart';
import 'app_shell.dart';

/// Three quiet beats: Promise, Exchange (built from the real conversation
/// atoms inside a phone frame) and Privacy. The final CTA deep-links to the
/// More tab with the "Get Sift ready" checklist scrolled into view.
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

  Future<void> _completeOnboarding({required bool setup}) async {
    await OnboardingScreen.markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppShell(
          initialTab: setup ? 2 : 0,
          scrollToChecklist: setup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  onPressed: () => _completeOnboarding(setup: false),
                  child: Text(
                    'Skip',
                    style: SiftType.buttonLabel.copyWith(
                      color: s.stone,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final active = _currentPage == index;
                return AnimatedContainer(
                  duration: MotionTokens.standard,
                  curve: MotionTokens.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? s.accent : s.surfaceWarm2,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _currentPage == 2
                      ? () => _completeOnboarding(setup: true)
                      : () {
                          _pageController.nextPage(
                            duration: MotionTokens.emphasis,
                            curve: MotionTokens.easeOutCubic,
                          );
                        },
                  child: Text(
                    _currentPage == 2 ? 'Set up Sift' : 'Next',
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
        return _buildExchange(context);
      default:
        return _buildTrust(context);
    }
  }

  Widget _buildPromise(BuildContext context) {
    final s = AppTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: SiftMark(size: 80)),
          const SizedBox(height: 40),
          Text(
            'Your screenshots, remembered.',
            style: SiftType.serifDisplay.copyWith(color: s.ink),
          ),
          const SizedBox(height: 16),
          Text(
            'Sift keeps the things you save and brings them back the moment you ask.',
            style: SiftType.bodySans.copyWith(
              color: s.graphite,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            'Your screenshots live on this device. AI analysis sends images to the provider you pick — Local-only mode keeps everything on-device.',
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

  Widget _buildExchange(BuildContext context) {
    final s = AppTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask in plain words.',
            style: SiftType.serifDisplay.copyWith(color: s.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Sift answers from the screenshots you actually saved.',
            style: SiftType.bodySans.copyWith(
              color: s.graphite,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: MediaQuery.sizeOf(context).width * 0.9,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: s.paper,
                borderRadius: BorderRadius.circular(SiftRadii.rSheet),
                border: Border.all(color: s.divider),
                boxShadow: SiftElevation.sheet(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UserPill(
                    text: 'What was that flight price I screenshotted?',
                  ),
                  const SizedBox(height: 16),
                  EvidenceStrip(
                    sources: _mockSources,
                    thumbBuilder: _mockThumb,
                  ),
                  const SizedBox(height: 16),
                  const EssayBlock(
                    text:
                        'You saved a Google Flights result on Jan 12 — round trip to Lisbon, \$540.',
                    showActions: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Every answer is grounded in a screenshot you saved.',
            style: SiftType.bodySansMd.copyWith(
              fontSize: 13,
              color: s.stone,
            ),
          ),
        ],
      ),
    );
  }

  static final List<Screenshot> _mockSources = [
    Screenshot(
      id: 'mock-flight',
      fileName: 'mock-flight.png',
      filePath: '',
      timestamp: DateTime(2026, 1, 12, 9, 30),
    ),
    Screenshot(
      id: 'mock-price',
      fileName: 'mock-price.png',
      filePath: '',
      timestamp: DateTime(2026, 1, 12, 9, 31),
    ),
  ];

  Widget _mockThumb(Screenshot screenshot, int index) {
    return _MockThumb(
      icon: index == 0 ? Icons.flight_rounded : Icons.attach_money_rounded,
    );
  }

  Widget _buildTrust(BuildContext context) {
    final s = AppTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quietly private.',
            style: SiftType.serifDisplay.copyWith(color: s.ink),
          ),
          const SizedBox(height: 16),
          Text(
            'Everything lives on this device. Nothing leaves unless you decide it does.',
            style: SiftType.bodySans.copyWith(
              color: s.graphite,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          _trustRow(context, Icons.lock_outline_rounded, 'Your data, your call'),
          Divider(color: s.divider, height: 1, thickness: 1),
          _trustRow(context, Icons.storage_rounded, 'Stored locally'),
          Divider(color: s.divider, height: 1, thickness: 1),
          _trustRow(context, Icons.verified_user_outlined, 'You stay in control'),
        ],
      ),
    );
  }

  Widget _trustRow(BuildContext context, IconData icon, String title) {
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: s.ink),
          const SizedBox(width: 12),
          Text(
            title,
            style: SiftType.bodySans.copyWith(
              fontWeight: FontWeight.w600,
              color: s.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockThumb extends StatelessWidget {
  final IconData icon;

  const _MockThumb({required this.icon});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      width: SiftSpacing.thumb,
      height: SiftSpacing.thumb,
      decoration: BoxDecoration(
        color: s.surfaceWarm2,
        borderRadius: BorderRadius.circular(SiftRadii.rThumb),
        border: Border.all(color: s.divider),
      ),
      child: Icon(icon, size: 18, color: s.accent),
    );
  }
}
