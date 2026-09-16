class RecoveryPredictor {
  // In home_screen.dart, fatigue drops to ~30% over 7 days, which means 10 days to reach 0.
  // Formula used: decayFactor = 1.0 - (daysAgo / 10.0)
  // Which implies: Volume = InitialVolume * (1 - days/10)
  // Intensity = Volume / Threshold
  // So: Intensity_Current = Intensity_Initial * (1 - daysAgo/10)
  // If we know Intensity_Current today (which is already decayed), 
  // we can extrapolate how many MORE days it takes to drop to the "Recovered" threshold (e.g. 20%).
  
  static const double recoveredThreshold = 0.2; // 20% intensity is considered "recovered"

  /// Returns the number of days until the muscle is considered recovered.
  /// If already recovered, returns 0.0.
  static double calculateDaysToRecovery(double currentIntensity) {
    if (currentIntensity <= recoveredThreshold) {
      return 0.0;
    }
    
    // Extrapolating linear decay:
    // It decays from 1.0 to 0.0 in exactly 10 days.
    // So it loses 0.1 intensity per day.
    // Remaining days = (currentIntensity - threshold) / decayRate
    const double decayRatePerDay = 0.1;
    
    double daysRemaining = (currentIntensity - recoveredThreshold) / decayRatePerDay;
    return daysRemaining > 0 ? daysRemaining : 0.0;
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
