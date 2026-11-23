import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/services/theme_service.dart';
import 'package:workout_app/screens/home_screen.dart';
import 'package:workout_app/widgets/dashboard_header.dart';
import 'package:workout_app/widgets/theme_picker_widget.dart';

void main() {
  testWidgets('an exercise name scrolls only when the card clips it',
      (tester) async {
    for (final width in [480.0, 80.0, 480.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
        width: width,
        child: const MarqueeText(
            text: 'Barbell Bench Press', style: TextStyle(fontSize: 18)),
      ))));
      expect(find.byType(SingleChildScrollView),
          width == 80 ? findsOneWidget : findsNothing);
    }
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Settings follows the selected palette while the dialog is open',
      (tester) async {
    final service = ThemeService();
    addTearDown(() => service.setTheme('system'));
    await tester.pumpWidget(ListenableBuilder(
      listenable: service,
      builder: (_, __) => MaterialApp(
        theme: service.getThemeDataFor(service.currentThemeId == 'system'
            ? 'light'
            : service.currentThemeId),
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () =>
                      showTrainingSettings(context, onImported: () {}),
                  child: const Text('Open settings'),
                ))),
      ),
    ));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    final dark = find.text('Quiet Luxury Dark');
    await tester.drag(find.byType(ListView), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(dark.hitTestable(), findsOneWidget);
    await tester.tap(dark);
    await tester.pumpAndSettle();
    final surface = tester
        .widgetList<Material>(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Material)),
        )
        .first;
    expect(surface.color,
        service.themes.firstWhere((theme) => theme.id == 'dark').card);
    expect(find.text('Use system theme'), findsOneWidget);
  });

  testWidgets('both dashboards keep named, tappable controls on small phones',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    for (final running in [true, false]) {
      var navigated = false;
      var openedSettings = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeService().getThemeDataFor(running ? 'sakura' : 'nord'),
        home: Scaffold(
            body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: DashboardHeader(
            title: running ? 'Running log' : 'Workouts',
            running: running,
            onSettings: () => openedSettings = true,
            onNavigate: () => navigated = true,
          ),
        )),
      ));
      final navigation =
          find.byTooltip(running ? 'Go to workouts' : 'Go to running log');
      expect(tester.getSize(navigation), const Size(48, 48));
      await tester.tap(navigation);
      await tester.tap(find.byTooltip('Settings'));
      expect(navigated && openedSettings, isTrue);
      expect(tester.takeException(), isNull);
    }
  });
}
