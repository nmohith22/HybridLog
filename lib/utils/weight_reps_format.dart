String formatWeightReps(double weight, int reps) {
  final weightText = weight % 1 == 0 ? weight.toInt().toString() : weight.toString();
  return '$weightText lbs x $reps reps';
}
