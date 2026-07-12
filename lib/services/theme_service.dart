import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppTheme {
  final String id;
  final String name;
  final Color background;
  final Color card;
  final Color accent;
  final Color text;
  final Color subText;
  final bool isDark;

  const AppTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.card,
    required this.accent,
    required this.text,
    required this.subText,
    required this.isDark,
  });
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _themeFileName = 'app_theme_selection.txt';

  // Available themes list
  final List<AppTheme> themes = [
    // System Theme
    const AppTheme(
      id: 'system',
      name: 'System Default',
      background: Color(0xFF120E15), // dark fallback
      card: Color(0xFF1A1523),
      accent: Color(0xFFD93846),
      text: Colors.white,
      subText: Colors.grey,
      isDark: true,
    ),
    // Quiet Luxury Light
    const AppTheme(
      id: 'light',
      name: 'Quiet Luxury Light',
      background: Color(0xFFF2F2F7),
      card: Colors.white,
      accent: Color(0xFFC05545),
      text: Color(0xFF2C2C2E),
      subText: Color(0xFF5E7D5E),
      isDark: false,
    ),
    // Quiet Luxury Dark
    const AppTheme(
      id: 'dark',
      name: 'Quiet Luxury Dark',
      background: Color(0xFF120E15),
      card: Color(0xFF1A1523),
      accent: Color(0xFFD93846),
      text: Colors.white,
      subText: Colors.grey,
      isDark: true,
    ),
    // Carbon
    const AppTheme(
      id: 'carbon',
      name: 'Carbon',
      background: Color(0xFF2B2B2B),
      card: Color(0xFF333333),
      accent: Color(0xFFF6C177),
      text: Color(0xFFE0DEF4),
      subText: Color(0xFF908E9F),
      isDark: true,
    ),
    // Serika Dark
    const AppTheme(
      id: 'serika_dark',
      name: 'Serika Dark',
      background: Color(0xFF323437),
      card: Color(0xFF2C2E31),
      accent: Color(0xFFE2B714),
      text: Color(0xFFD1D0C5),
      subText: Color(0xFF646669),
      isDark: true,
    ),
    // Nord
    const AppTheme(
      id: 'nord',
      name: 'Nord',
      background: Color(0xFF2E3440),
      card: Color(0xFF3B4252),
      accent: Color(0xFF88C0D0),
      text: Color(0xFFECEFF4),
      subText: Color(0xFF4C566A),
      isDark: true,
    ),
    // Sakura
    const AppTheme(
      id: 'sakura',
      name: 'Sakura',
      background: Color(0xFFF5E6E8),
      card: Colors.white,
      accent: Color(0xFFE88392),
      text: Color(0xFF5F4B56),
      subText: Color(0xFFA58D9E),
      isDark: false,
    ),
    // Cyberpunk
    const AppTheme(
      id: 'cyberpunk',
      name: 'Cyberpunk',
      background: Color(0xFF181926),
      card: Color(0xFF23253B),
      accent: Color(0xFFFF0055),
      text: Color(0xFF00FFCC),
      subText: Color(0xFF6E6A86),
      isDark: true,
    ),
    // Botanical
    const AppTheme(
      id: 'botanical',
      name: 'Botanical',
      background: Color(0xFF7B9E89),
      card: Color(0xFFEAF4EC),
      accent: Color(0xFF384F3D),
      text: Color(0xFF1C2D20),
      subText: Color(0xFF5C7866),
      isDark: false,
    ),
    // Laser
    const AppTheme(
      id: 'laser',
      name: 'Laser',
      background: Color(0xFF181524),
      card: Color(0xFF231E36),
      accent: Color(0xFF00E8C6),
      text: Color(0xFFD91D81),
      subText: Color(0xFF5C5482),
      isDark: true,
    ),
    // Modern Ink
    const AppTheme(
      id: 'modern_ink',
      name: 'Modern Ink',
      background: Color(0xFFF7F7F7),
      card: Colors.white,
      accent: Color(0xFF000000),
      text: Color(0xFF1A1A1A),
      subText: Color(0xFF7F7F7F),
      isDark: false,
    ),
    // Terra
    const AppTheme(
      id: 'terra',
      name: 'Terra',
      background: Color(0xFF2C2421),
      card: Color(0xFF3A302C),
      accent: Color(0xFFDE8F6E),
      text: Color(0xFFE6D5C3),
      subText: Color(0xFF736058),
      isDark: true,
    ),
    // Matrix
    const AppTheme(
      id: 'matrix',
      name: 'Matrix',
      background: Color(0xFF000000),
      card: Color(0xFF0D0D0D),
      accent: Color(0xFF15FF00),
      text: Color(0xFF39FF14),
      subText: Color(0xFF008000),
      isDark: true,
    ),
    // Red Dragon
    const AppTheme(
      id: 'red_dragon',
      name: 'Red Dragon',
      background: Color(0xFF1A0F10),
      card: Color(0xFF2B191B),
      accent: Color(0xFFFF3E3E),
      text: Color(0xFFEDD2D2),
      subText: Color(0xFF634244),
      isDark: true,
    ),
    // Dracula
    const AppTheme(
      id: 'dracula',
      name: 'Dracula',
      background: Color(0xFF282A36),
      card: Color(0xFF44475A),
      accent: Color(0xFFFF79C6),
      text: Color(0xFFF8F8F2),
      subText: Color(0xFF6272A4),
      isDark: true,
    ),
    // Gruvbox
    const AppTheme(
      id: 'gruvbox',
      name: 'Gruvbox',
      background: Color(0xFF282828),
      card: Color(0xFF3C3836),
      accent: Color(0xFFFE8019),
      text: Color(0xFFEBDBB2),
      subText: Color(0xFFA89984),
      isDark: true,
    ),
    // Catppuccin
    const AppTheme(
      id: 'catppuccin',
      name: 'Catppuccin',
      background: Color(0xFF1E1E2E),
      card: Color(0xFF313244),
      accent: Color(0xFFCBA6F7),
      text: Color(0xFFCDD6F4),
      subText: Color(0xFF9399B2),
      isDark: true,
    ),
    // Tokyo Night
    const AppTheme(
      id: 'tokyo_night',
      name: 'Tokyo Night',
      background: Color(0xFF1A1B26),
      card: Color(0xFF24283B),
      accent: Color(0xFF7AA2F7),
      text: Color(0xFFC0CAF5),
      subText: Color(0xFF565F89),
      isDark: true,
    ),
    // Monokai
    const AppTheme(
      id: 'monokai',
      name: 'Monokai',
      background: Color(0xFF272822),
      card: Color(0xFF3E3D32),
      accent: Color(0xFFF92672),
      text: Color(0xFFF8F8F2),
      subText: Color(0xFF75715E),
      isDark: true,
    ),
  ];

  String _currentThemeId = 'system';

  String get currentThemeId => _currentThemeId;

  AppTheme get activeTheme {
    return themes.firstWhere((t) => t.id == _currentThemeId, orElse: () => themes[0]);
  }

  // Get resolved theme for active color definitions
  AppTheme getResolvedTheme(BuildContext context) {
    if (_currentThemeId == 'system') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return themes.firstWhere((t) => t.id == (isDark ? 'dark' : 'light'));
    }
    return activeTheme;
  }

  // Initialize service, loading preference from file
  Future<void> init() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (themes.any((t) => t.id == content)) {
          _currentThemeId = content;
        }
      }
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
    }
  }

  // Change active theme and save to file
  Future<void> setTheme(String themeId) async {
    if (_currentThemeId == themeId) return;
    if (!themes.any((t) => t.id == themeId)) return;

    _currentThemeId = themeId;
    notifyListeners();

    try {
      final file = await _getSettingsFile();
      await file.writeAsString(themeId);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_themeFileName');
  }

  ThemeMode get themeMode {
    if (_currentThemeId == 'system') return ThemeMode.system;
    final theme = activeTheme;
    return theme.isDark ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData getThemeDataFor(String themeId) {
    final theme = themes.firstWhere((t) => t.id == themeId, orElse: () => themes[0]);
    final isDark = theme.isDark;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: theme.accent,
      scaffoldBackgroundColor: theme.background,
      cardColor: theme.card,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: theme.accent,
              secondary: theme.subText,
              surface: theme.card,
              onSurface: theme.text,
              surfaceContainerHighest: theme.card.withOpacity(0.8),
            )
          : ColorScheme.light(
              primary: theme.accent,
              secondary: theme.subText,
              surface: theme.card,
              onSurface: theme.text,
              surfaceContainerHighest: theme.card.withOpacity(0.8),
            ),
      useMaterial3: true,
      dialogBackgroundColor: theme.card,
      dividerColor: theme.subText.withOpacity(0.2),
    );
  }
}
