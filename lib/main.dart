import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/theme_controller.dart';
import 'providers/screenshot_provider.dart';
import 'services/lam_service.dart';
import 'services/action_service.dart';
import 'services/watcher_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/app_shell.dart';
import 'widgets/sift_mark.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('screenshots');
  await Hive.openBox('actions');
  await Hive.openBox('chat');

  final themeController = await ThemeController.load();
  final screenshotProvider = ScreenshotProvider()..loadScreenshots();
  final lamService = LAMService();
  final actionService = ActionService();
  final watcherService = WatcherService(
    provider: screenshotProvider,
    actionService: actionService,
  );

  runApp(
    SiftApp(
      themeController: themeController,
      screenshotProvider: screenshotProvider,
      lamService: lamService,
      actionService: actionService,
      watcherService: watcherService,
    ),
  );
}

class SiftApp extends StatelessWidget {
  final ThemeController themeController;
  final ScreenshotProvider screenshotProvider;
  final LAMService lamService;
  final ActionService actionService;
  final WatcherService watcherService;

  const SiftApp({
    super.key,
    required this.themeController,
    required this.screenshotProvider,
    required this.lamService,
    required this.actionService,
    required this.watcherService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: screenshotProvider),
        Provider.value(value: lamService),
        Provider.value(value: actionService),
        ChangeNotifierProvider.value(value: watcherService),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'Sift',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: controller.themeMode,
            builder: (context, child) {
              Motion.reduced = MediaQuery.disableAnimationsOf(context);
              return MediaQuery.withClampedTextScaling(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.6,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const AppStartup(),
          );
        },
      ),
    );
  }
}

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _checking = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (Motion.enabled) {
      _pulse.repeat(reverse: true);
    }
    _checkOnboarding();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _checkOnboarding() async {
    final showOnboarding = await OnboardingScreen.shouldShow();
    if (!mounted) return;
    setState(() {
      _showOnboarding = showOnboarding;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOutSine),
            ),
            child: const SiftMark(size: 56),
          ),
        ),
      );
    }

    if (_showOnboarding) {
      return const OnboardingScreen();
    }

    return const AppShell();
  }
}
