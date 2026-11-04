import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/widgets/front_back_heatmap_fade.dart';

void main() {
  testWidgets('crossfades front to back quickly on a fixed icon footprint',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 54,
        height: 70,
        child: FrontBackHeatmapFade(
          front: ColoredBox(key: ValueKey('front'), color: Colors.red),
          back: ColoredBox(key: ValueKey('back'), color: Colors.blue),
        ),
      ),
    ));

    expect(find.byType(AnimatedCrossFade), findsNothing);
    final footprint = tester.getSize(find.byType(FrontBackHeatmapFade));

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    final fades =
        tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fades, hasLength(2));
    expect(
        fades.every(
            (fade) => fade.duration == const Duration(milliseconds: 600)),
        isTrue);
    final fadeFinder = find.descendant(
      of: find.byType(FrontBackHeatmapFade),
      matching: find.byType(FadeTransition),
    );
    final transitions = tester.widgetList<FadeTransition>(fadeFinder);
    expect(transitions, hasLength(2));
    expect(transitions.every((fade) => fade.opacity.value > 0), isTrue);
    expect(tester.getSize(find.byType(FrontBackHeatmapFade)), footprint);

    await tester.pump(const Duration(milliseconds: 300));
    final completed = tester.widgetList<FadeTransition>(fadeFinder).toList();
    expect(completed.first.opacity.value, 0);
    expect(completed.last.opacity.value, 1);
  });
}
