import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/widgets/front_back_heatmap_fade.dart';

void main() {
  testWidgets('fades between front and back on a fixed icon footprint',
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

    expect(
      tester
          .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .crossFadeState,
      CrossFadeState.showFirst,
    );
    final footprint = tester.getSize(find.byType(FrontBackHeatmapFade));

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester
          .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .crossFadeState,
      CrossFadeState.showSecond,
    );
    expect(tester.getSize(find.byType(FrontBackHeatmapFade)), footprint);
  });
}
