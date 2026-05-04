import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'services/database_service.dart';
import 'services/widget_service.dart';
import 'screens/main_navigation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // IMMERSIVE FULLSCREEN MODE
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // Non-blocking background initialization
  DatabaseService().database.catchError((e) {
    debugPrint('Database initialization failed: $e');
    return Isar.getInstance()!; // Try to recover
  });

  if (!kIsWeb) {
    // Handle background actions from the widget
    HomeWidget.registerInteractivityCallback(_backgroundCallback);
    // Non-blocking widget update
    WidgetService.updateRunningWidget().catchError((e) => debugPrint('Initial widget update failed: $e'));
  }

  runApp(const WorkoutApp());
}

// Background handler for widget interactions
@pragma('vm:entry-point')
Future<void> _backgroundCallback(Uri? uri) async {
  try {
    debugPrint('--- BACKGROUND CALLBACK TRIGGERED ---');
    debugPrint('URI: $uri');
    if (uri?.scheme == 'hybridlog') {
      await WidgetService.handleWidgetAction(uri);
    }
  } catch (e) {
    debugPrint('CRITICAL: Background Callback Failed: $e');
  }
}

class WorkoutApp extends StatefulWidget {
  const WorkoutApp({super.key});

  static _WorkoutAppState? of(BuildContext context) => context.findAncestorStateOfType<_WorkoutAppState>();

  @override
  State<WorkoutApp> createState() => _WorkoutAppState();
}

class _WorkoutAppState extends State<WorkoutApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme() {
    setState(() {
      // Toggle logic: System -> Light -> Dark -> System
      if (_themeMode == ThemeMode.system) _themeMode = ThemeMode.light;
      else if (_themeMode == ThemeMode.light) _themeMode = ThemeMode.dark;
      else _themeMode = ThemeMode.system;
    });
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HybridLog',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFFC05545), // Muted Terracotta/Red
        scaffoldBackgroundColor: const Color(0xFFF2F2F7), // Softer Apple-like gray
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFC05545),
          secondary: Color(0xFF5E7D5E), // Muted Sage Green
          surface: Colors.white,
          onSurface: Color(0xFF2C2C2E),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepOrange,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepOrange,
          secondary: Colors.deepOrangeAccent,
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}
