import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/utils/weight_reps_format.dart';

void main() {
  test('formats whole and fractional weights before reps', () {
    expect(formatWeightReps(135, 10), '135 lbs x 10 reps');
    expect(formatWeightReps(42.5, 8), '42.5 lbs x 8 reps');
  });
}
