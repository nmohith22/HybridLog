import '../models/fitness_schema.dart';

String formatWeightReps(double weight, int reps) {
  final weightText =
      weight % 1 == 0 ? weight.toInt().toString() : weight.toString();
  return '$weightText lbs x $reps reps';
}

String formatSetStep(SubSetLog step) {
  final work = formatWeightReps(step.weight, step.reps);
  if (step.exerciseName case final name?) return 'Superset · $name · $work';
  if (step.pauseSeconds case final seconds?) {
    final resumed = step.reps > 0 ? ' · $work' : '';
    return 'Rest-pause · ${seconds}s$resumed';
  }
  return 'Dropset · $work';
}
