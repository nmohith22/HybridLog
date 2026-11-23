import 'package:flutter/material.dart';
import '../services/data_backup_service.dart';
import '../services/theme_service.dart';
import 'lego_animations.dart';

enum _SettingsAction { exportData, importData, tutorial }

Future<void> showTrainingSettings(
  BuildContext context, {
  required VoidCallback onImported,
  VoidCallback? onReplayTutorial,
}) async {
  final service = ThemeService();
  final action = await showDialog<_SettingsAction>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final next = service.nextQuickThemeId;
        return AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(
                  switch (next) {
                    'light' => Icons.light_mode_outlined,
                    'dark' => Icons.dark_mode_outlined,
                    _ => Icons.brightness_auto_outlined,
                  },
                  color: colors.primary),
              title: Text(next == 'system'
                  ? 'Use system theme'
                  : 'Switch to $next mode'),
              onTap: () {
                Navigator.pop(dialogContext);
                service.setTheme(next);
              },
            ),
            const Divider(),
            ListTile(
                leading:
                    Icon(Icons.file_upload_outlined, color: colors.primary),
                title: const Text('Export data'),
                onTap: () =>
                    Navigator.pop(dialogContext, _SettingsAction.exportData)),
            ListTile(
                leading:
                    Icon(Icons.file_download_outlined, color: colors.primary),
                title: const Text('Import data'),
                onTap: () =>
                    Navigator.pop(dialogContext, _SettingsAction.importData)),
            const Divider(),
            if (onReplayTutorial != null)
              ListTile(
                  leading: Icon(Icons.school_outlined, color: colors.primary),
                  title: const Text('Replay tutorial'),
                  onTap: () =>
                      Navigator.pop(dialogContext, _SettingsAction.tutorial)),
            ThemePickerWidget(selectedId: service.currentThemeId),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'))
          ],
        );
      },
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == _SettingsAction.tutorial) {
    onReplayTutorial?.call();
    return;
  }
  final importing = action == _SettingsAction.importData;
  final error = importing
      ? await DataBackupService.importData()
      : await DataBackupService.exportData();
  if (!context.mounted) return;
  if (importing && error == null) onImported();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(error ??
        (importing
            ? 'Data imported successfully'
            : 'Data exported successfully')),
  ));
}

class ThemePickerWidget extends StatelessWidget {
  const ThemePickerWidget({super.key, required this.selectedId});
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final service = ThemeService();
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Appearance',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: colors.onSurface),
          ),
        ),
        SizedBox(
          width: 400,
          height: 88 + MediaQuery.textScalerOf(context).scale(14),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: service.themes.length,
            itemBuilder: (context, index) {
              final t = service.themes[index];
              final isSelected = t.id == selectedId;

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
                child: SpringyButton(
                  onTap: () {
                    service.setTheme(t.id);
                  },
                  child: Semantics(
                      button: true,
                      selected: isSelected,
                      child: Container(
                        width: 148,
                        decoration: BoxDecoration(
                          color: t.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? t.accent
                                : (t.isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : Colors.black.withOpacity(0.15)),
                            width: isSelected ? 2.5 : 1.0,
                          ),
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
                                const Spacer(),
                                if (isSelected)
                                  Icon(Icons.check_circle,
                                      color: t.text, size: 18),
                              ],
                            ),
                          ],
                        ),
                      )),
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
