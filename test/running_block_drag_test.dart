import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/widgets/running_block_graph.dart';

void main() {
  test('maps the finger position to the matching day column', () {
    const rowWidth = 350.0;
    expect(runningDayIndexAt(0, rowWidth), 0);
    expect(runningDayIndexAt(50, rowWidth), 1);
    expect(runningDayIndexAt(150, rowWidth), 3);
    expect(runningDayIndexAt(349.9, rowWidth), 6);
    expect(runningDayIndexAt(400, rowWidth), 6);
  });
}
