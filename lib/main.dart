import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'services/database_service.dart';
import 'services/widget_service.dart';
import 'screens/main_navigation.dart';
import 'services/theme_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // IMMERSIVE FULLSCREEN MODE
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialize theme service
  await ThemeService().init();
  
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
  @override
  void initState() {
    super.initState();
    ThemeService().addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeService().removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  void toggleTheme() {
    final service = ThemeService();
    final current = service.currentThemeId;
    if (current == 'system') {
      service.setTheme('light');
    } else if (current == 'light') {
      service.setTheme('dark');
    } else {
      service.setTheme('system');
    }
  }

  bool get isDarkMode => ThemeService().getResolvedTheme(context).isDark;

  @override
  Widget build(BuildContext context) {
    final service = ThemeService();
    final currentId = service.currentThemeId;
    
    ThemeData lightTheme;
    ThemeData darkTheme;
    
    if (currentId == 'system') {
      lightTheme = service.getThemeDataFor('light');
      darkTheme = service.getThemeDataFor('dark');
    } else {
      final activeThemeData = service.getThemeDataFor(currentId);
      lightTheme = activeThemeData;
      darkTheme = activeThemeData;
    }

    return MaterialApp(
      title: 'HybridLog',
      debugShowCheckedModeBanner: false,
      themeMode: service.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: const MainNavigation(),
    );
  }
}
