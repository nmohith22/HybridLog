import '../models/fitness_schema.dart';

class ProgressionSession {
  final DateTime date;
  final double topWeight;
  final int topWeightReps;

  const ProgressionSession({
    required this.date,
    required this.topWeight,
    required this.topWeightReps,
  });
}

class ProgressionSuggestion {
  final double weight;
  final int reps;
  final String rationale;
  final List<ProgressionSession> supportingSessions;

  const ProgressionSuggestion({
    required this.weight,
    required this.reps,
    required this.rationale,
    required this.supportingSessions,
  });
}

class ProgressionService {
  static ProgressionSuggestion? suggestNextTarget(
    String exerciseName,
    List<DailyWorkout> history,
  ) {
    final sessions = <ProgressionSession>[];
    List<SetLog>? mostRecentSets;
    final sorted = history.toList()..sort((a, b) => b.date.compareTo(a.date));

    for (final workout in sorted) {
      final sets = workout.exercises
          .where((exercise) => exercise.exerciseName == exerciseName)
          .expand((exercise) => exercise.sets)
          .where((set) => set.reps > 0)
          .toList();
      if (sets.isEmpty) continue;
      mostRecentSets ??= sets;

      final topWeight =
          sets.map((set) => set.weight).reduce((a, b) => a > b ? a : b);
      final repsAtTopWeight = sets
          .where((set) => set.weight == topWeight)
          .map((set) => set.reps)
          .reduce((a, b) => a > b ? a : b);
      sessions.add(ProgressionSession(
        date: workout.date,
        topWeight: topWeight,
        topWeightReps: repsAtTopWeight,
      ));
      if (sessions.length == 3) break;
    }

    if (sessions.isEmpty) return null;

    final latest = sessions.first;
    final bodyweight = latest.topWeight == 0;
    final completedRepRange =
        !bodyweight && mostRecentSets!.every((set) => set.reps >= 12);

    final weight =
        completedRepRange ? latest.topWeight + 2.5 : latest.topWeight;
    final reps = bodyweight
        ? latest.topWeightReps + 1
        : completedRepRange
            ? 8
            : (latest.topWeightReps + 1).clamp(1, 12).toInt();
    final rationale = bodyweight
        ? 'Keep it bodyweight and aim for one more rep on your strongest set.'
        : completedRepRange
            ? 'Your recorded sets reached 12 reps. Try 2.5 lb more and build back toward 12 reps.'
            : 'Keep the same weight and aim for one more rep on your strongest set, up to 12.';

    return ProgressionSuggestion(
      weight: weight,
      reps: reps,
      rationale: rationale,
      supportingSessions: List.unmodifiable(sessions),
    );
  }
}
