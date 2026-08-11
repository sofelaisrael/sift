import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/theme_controller.dart';
import 'providers/screenshot_provider.dart';
import 'services/lam_service.dart';
import 'services/action_service.dart';
import 'services/watcher_service.dart';
import 'services/ocr_service.dart';
import 'services/ingest_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/app_shell.dart';
import 'widgets/sift_mark.dart';
import 'theme/app_theme.dart';
import 'theme/motion_tokens.dart';

/// Registers the OFL licenses for the bundled fonts so they appear under
/// Settings > About > Licenses. Never fatal: a missing license file must not
/// blank-screen the app at startup.
Future<void> _registerFontLicenses() async {
  String? sourceSerif;
  String? jetBrains;
  try {
    sourceSerif = await rootBundle.loadString('assets/fonts/OFL-SourceSerif4.txt');
  } catch (_) {}
  try {
    jetBrains = await rootBundle.loadString('assets/fonts/OFL-JetBrainsMono.txt');
  } catch (_) {}
  if (sourceSerif != null || jetBrains != null) {
    LicenseRegistry.addLicense(() async* {
      if (sourceSerif != null) {
        yield LicenseEntryWithLineBreaks(['Source Serif 4'], sourceSerif);
      }
      if (jetBrains != null) {
        yield LicenseEntryWithLineBreaks(['JetBrains Mono'], jetBrains);
      }
    });
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _registerFontLicenses();
  await Hive.initFlutter();
  await Hive.openBox('screenshots');
  await Hive.openBox('actions');
  await Hive.openBox('chat');
  await Hive.openBox('ingest');
  await Hive.openBox('hidden_paths');

  final themeController = await ThemeController.load();
  final ocrService = OCRService();
  final screenshotProvider = ScreenshotProvider(ocr: ocrService)
    ..loadScreenshots();
  final lamService = LAMService();
  final actionService = ActionService();
  final ingestService = IngestService(
    provider: screenshotProvider,
    ocr: ocrService,
  );
  final watcherService = WatcherService(
    provider: screenshotProvider,
    actionService: actionService,
    isIngesting: () => ingestService.isIngesting,
  );
  ingestService.onPassComplete = watcherService.scanNow;

  runApp(
    SiftApp(
      themeController: themeController,
      screenshotProvider: screenshotProvider,
      lamService: lamService,
      actionService: actionService,
      watcherService: watcherService,
      ingestService: ingestService,
    ),
  );
}

class SiftApp extends StatelessWidget {
  final ThemeController themeController;
  final ScreenshotProvider screenshotProvider;
  final LAMService lamService;
  final ActionService actionService;
  final WatcherService watcherService;
  final IngestService ingestService;

  const SiftApp({
    super.key,
    required this.themeController,
    required this.screenshotProvider,
    required this.lamService,
    required this.actionService,
    required this.watcherService,
    required this.ingestService,
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
        ChangeNotifierProvider.value(value: ingestService),
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
              MotionTokens.reduced = MediaQuery.disableAnimationsOf(context);
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
      duration: MotionTokens.pulseCycle,
    );
    if (MotionTokens.enabled) {
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
