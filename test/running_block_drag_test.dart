import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/database_service.dart';
import 'package:workout_app/widgets/running_block_graph.dart';

void main() {
  test('week offsets preserve Monday across daylight saving time', () {
    final currentWeek = runningWeekStartFor(DateTime(2026, 11, 3), 0);
    final previousWeek = runningWeekStartFor(DateTime(2026, 11, 3), -1);
    final nextWeek = runningWeekStartFor(DateTime(2026, 11, 3), 1);

    expect(currentWeek, DateTime(2026, 11, 2));
    expect(previousWeek, DateTime(2026, 10, 26));
    expect(previousWeek.weekday, DateTime.monday);
    expect(nextWeek, DateTime(2026, 11, 9));
  });

  testWidgets('each weekday increments and decrements its own date',
      (tester) async {
    final db = _RunningDatabase();
    await tester.pumpWidget(_graph(db));
    await tester.pumpAndSettle();

    final monday = runningWeekStartFor(DateTime.now(), 0);
    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final date = DateTime(monday.year, monday.month, monday.day + dayIndex);
      final dayCell = find.byKey(ValueKey('run-day-0-$dayIndex'));

      await tester.drag(dayCell, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(db.countFor(date), 3, reason: 'upward drag on day $dayIndex');
      expect(db.lastSavedDate, date);
      expect(db.lastDelta, 1);

      await tester.drag(dayCell, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(db.countFor(date), 2, reason: 'downward drag on day $dayIndex');
      expect(db.lastSavedDate, date);
      expect(db.lastDelta, -1);
    }
  });

  testWidgets('the prior week starts Monday and keeps weekend edits in place',
      (tester) async {
    final db = _RunningDatabase();
    await tester.pumpWidget(_graph(db));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();

    final monday = runningWeekStartFor(DateTime.now(), -1);
    expect(db.lastRangeStart, monday);

    for (final dayIndex in [0, 5, 6]) {
      final date = DateTime(monday.year, monday.month, monday.day + dayIndex);
      final dayCell = find.byKey(ValueKey('run-day--1-$dayIndex'));

      await tester.drag(dayCell, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(db.lastSavedDate, date);
      expect(db.lastDelta, 1);
      expect(db.countFor(date), 3);

      await tester.drag(dayCell, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(db.lastSavedDate, date);
      expect(db.lastDelta, -1);
      expect(db.countFor(date), 2);
    }
  });
}

Widget _graph(_RunningDatabase db) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 350,
          height: 280,
          child: RunningBlockGraph(dbService: db),
        ),
      ),
    );

class _RunningDatabase implements DatabaseService {
  final Map<DateTime, int> _counts = {};
  DateTime? lastRangeStart;
  DateTime? lastSavedDate;
  int? lastDelta;

  int countFor(DateTime date) => _counts[DateTime(date.year, date.month, date.day)] ?? 0;

  @override
  Future<Isar> get database => throw UnimplementedError();

  @override
  Future<void> saveRunningBlock(DateTime date, int additionalMiles) async {
    final day = DateTime(date.year, date.month, date.day);
    lastSavedDate = day;
    lastDelta = additionalMiles;
    _counts[day] = ((_counts[day] ?? 0) + additionalMiles).clamp(0, 20).toInt();
  }

  @override
  Future<List<RunningLog>> getRunningLogsForDateRange(
      DateTime start, DateTime end) async {
    lastRangeStart = DateTime(start.year, start.month, start.day);
    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final day = DateTime(start.year, start.month, start.day + dayIndex);
      _counts.putIfAbsent(day, () => 2);
    }

    return [
      for (final entry in _counts.entries)
        if (!entry.key.isBefore(start) && !entry.key.isAfter(end))
          RunningLog()
            ..date = DateTime.utc(entry.key.year, entry.key.month, entry.key.day)
            ..miles = entry.value,
    ];
  }

  @override
  Future<List<RunningLog>> getRunningLogsForWeek(DateTime startOfWeek) async =>
      getRunningLogsForDateRange(
          startOfWeek,
          DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + 7)
              .subtract(const Duration(microseconds: 1)));

  @override
  Stream<void> watchRunningLogs() => const Stream<void>.empty();
}
