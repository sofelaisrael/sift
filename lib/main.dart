import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'services/lam_service.dart';
import 'services/action_service.dart';
import 'providers/screenshot_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('screenshots');
  await Hive.openBox('actions');
  
  runApp(const ScreenSortApp());
}

class ScreenSortApp extends StatelessWidget {
  const ScreenSortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ScreenshotProvider()..loadScreenshots(),
        ),
        Provider(create: (_) => LAMService()),
        Provider(create: (_) => ActionService()),
      ],
      child: MaterialApp(
        title: 'ScreenSort',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
