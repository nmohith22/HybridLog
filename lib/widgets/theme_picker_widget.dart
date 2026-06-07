import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'lego_animations.dart';

class ThemePickerWidget extends StatelessWidget {
  const ThemePickerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ThemeService();
    final activeThemeId = service.currentThemeId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'THEMES',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: service.themes.length,
            itemBuilder: (context, index) {
              final t = service.themes[index];
              final isSelected = t.id == activeThemeId;
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
                child: SpringyButton(
                  onTap: () {
                    service.setTheme(t.id);
                  },
                  child: Container(
                    width: 120,
                    decoration: BoxDecoration(
                      color: t.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? t.accent
                            : (t.isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.15)),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: t.accent.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.name,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            _buildColorDot(t.accent),
                            const SizedBox(width: 4),
                            _buildColorDot(t.card),
                            const SizedBox(width: 4),
                            _buildColorDot(t.subText),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withOpacity(0.15), width: 0.5),
      ),
    );
  }
}
