import 'muscle_fatigue_service.dart';

class RecoveryPredictor {
  static const double recoveredThreshold = .20;

  static double calculateDaysToRecovery(
      Map<DateTime, Map<String, double>> sessions,
      String muscle,
      DateTime now) {
    bool recoveredAt(int minutes) =>
        (MuscleFatigueService.recentLoad(
                sessions, now.add(Duration(minutes: minutes)))[muscle] ??
            0) <=
        recoveredThreshold;
    if (recoveredAt(0)) return 0;

    var earliest = 0;
    var latest = MuscleFatigueService.window.inMinutes;
    while (latest - earliest > 1) {
      final midpoint = (earliest + latest) ~/ 2;
      if (recoveredAt(midpoint)) {
        latest = midpoint;
      } else {
        earliest = midpoint;
      }
    }
    return latest / Duration.minutesPerDay;
  }

  /// Returns a human-readable string for recovery time (e.g., "36h", "2d", "Ready")
  static String formatRecoveryTime(double days) {
    if (days <= 0.0) return "Ready";

    if (days < 1.0) {
      int hours = (days * 24).round();
      if (hours == 0) return "Ready";
      return "${hours}h";
    }

    if (days < 2.0) {
      int hours = ((days - 1.0) * 24).round();
      if (hours == 0) return "1d";
      return "1d ${hours}h";
    }

    return "${days.round()}d";
  }
}
