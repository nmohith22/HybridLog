import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/database_service.dart';
import 'package:workout_app/widgets/running_block_graph.dart';

void main() {
  testWidgets(
      'vertical drags change the day under the finger in both directions',
      (tester) async {
    final db = _RunningDatabase();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 350,
          height: 280,
          child: RunningBlockGraph(dbService: db),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final thursday = find.byKey(const ValueKey('run-day-0-3'));
    final wednesday = find.byKey(const ValueKey('run-day-0-2'));
    final thursdayCount = find.byKey(const ValueKey('run-day-count-0-3'));
    final wednesdayCount = find.byKey(const ValueKey('run-day-count-0-2'));
    expect(tester.widget<Text>(thursdayCount).data, '2');
    expect(tester.widget<Text>(wednesdayCount).data, '0');

    await tester.drag(thursday, const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(thursdayCount).data, '3');
    expect(tester.widget<Text>(wednesdayCount).data, '0');

    await tester.drag(thursday, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(thursdayCount).data, '2');
    expect(tester.widget<Text>(wednesdayCount).data, '0');
  });
}

class _RunningDatabase implements DatabaseService {
  final Map<DateTime, int> _counts = {};

  @override
  Future<Isar> get database => throw UnimplementedError();

  @override
  Future<void> saveRunningBlock(DateTime date, int additionalMiles) async {
    final day = DateTime(date.year, date.month, date.day);
    _counts[day] = ((_counts[day] ?? 0) + additionalMiles).clamp(0, 20).toInt();
  }

  @override
  Future<List<RunningLog>> getRunningLogsForDateRange(
      DateTime start, DateTime end) async {
    final thursday = DateTime(start.year, start.month, start.day)
        .add(const Duration(days: 3));
    _counts.putIfAbsent(thursday, () => 2);
    return [
      for (final entry in _counts.entries)
        if (!entry.key.isBefore(start) && !entry.key.isAfter(end))
          RunningLog()
            ..date = entry.key
            ..miles = entry.value,
    ];
  }

  @override
  Future<List<RunningLog>> getRunningLogsForWeek(DateTime startOfWeek) async =>
      getRunningLogsForDateRange(startOfWeek,
          startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59)));

  @override
  Stream<void> watchRunningLogs() => const Stream<void>.empty();
}
