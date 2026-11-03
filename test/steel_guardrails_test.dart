import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/services/steel_guardrails.dart';

void main() {
  group('Steel operation guardrails', () {
    test('allows an explicitly requested create', () {
      expect(
        SteelGuardrails.allowsOperation(
          'Add an exercise named Incline Press.',
          'create',
        ),
        isTrue,
      );
    });

    test('does not turn a request for advice into a create', () {
      expect(
        SteelGuardrails.allowsOperation(
          'What exercise should I add to my workout?',
          'create',
        ),
        isFalse,
      );
    });

    test('blocks negated and bulk deletion requests', () {
      expect(
        SteelGuardrails.allowsOperation('Do not delete my run.', 'delete'),
        isFalse,
      );
      expect(
        SteelGuardrails.allowsOperation('Delete all of my runs.', 'delete'),
        isFalse,
      );
      expect(
        SteelGuardrails.isBulkDeleteRequest('Remove both workouts.'),
        isTrue,
      );
    });
  });
}
