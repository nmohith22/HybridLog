import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/fitness_schema.dart';
import 'neural_net.dart';

class RecommendationEngine {
  static const Map<String, List<String>> _splitDefinitions = {
    'Push': ['chest', 'front_deltoids', 'side_deltoids', 'triceps'],
    'Pull': ['lats', 'upper_back', 'traps', 'back_deltoids', 'biceps', 'bicep_short_head', 'bicep_long_head', 'lower_back', 'forearm'],
    'Legs': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Upper': ['chest', 'front_deltoids', 'side_deltoids', 'triceps', 'lats', 'upper_back', 'traps', 'back_deltoids', 'biceps', 'lower_back'],
    'Lower': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Fullbody': [], // Special case, all match
    'Shoulders': ['front_deltoids', 'side_deltoids', 'back_deltoids'],
    'Arms': ['biceps', 'bicep_short_head', 'bicep_long_head', 'triceps', 'tricep_long_head', 'forearm'],
    'Shoulders and Arms': ['front_deltoids', 'side_deltoids', 'back_deltoids', 'biceps', 'bicep_short_head', 'bicep_long_head', 'triceps', 'tricep_long_head', 'forearm'],
    'Back': ['lats', 'upper_back', 'traps', 'back_deltoids', 'lower_back'],
    'Chest': ['chest'],
    'Chest and Back': ['chest', 'lats', 'upper_back', 'traps', 'back_deltoids', 'lower_back'],
    'Posterior': ['lats', 'upper_back', 'traps', 'back_deltoids', 'lower_back', 'glutes', 'hamstrings', 'calves'],
    'Anterior': ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'biceps', 'quads'],
  };

  /// Main entry point to build a custom folder
  static Future<List<Exercise>> generateWorkout({
    required List<Exercise> allExercises,
    required Map<String, double> currentFatigue,
    required List<String> splitTypes,
    required bool onlyFamiliar,
  }) async {
    // 1. Prepare the Neural Network (3 inputs -> 4 hidden -> 1 output)
    final nn = NeuralNetwork([3, 4, 1]);

    // 2. Synthesize a training dataset reflecting expert heuristic rules
    // Features: [Split Match (0-1), Fatigue Penalty (0-1), Is Familiar (0-1)]
    // Target: [Affinity (0-1)]
    List<List<double>> trainingData = [];
    List<List<double>> targets = [];

    // Rule 1: Perfect Match (Fits split, not fatigued, familiar) -> Highly Recommended
    trainingData.add([1.0, 0.0, 1.0]); targets.add([1.0]);
    // Rule 2: Good Match (Fits split, not fatigued, unfamiliar)
    trainingData.add([1.0, 0.0, 0.0]); targets.add([onlyFamiliar ? 0.0 : 0.8]);
    // Rule 3: Fatigued (Fits split, highly fatigued, familiar) -> Avoid
    trainingData.add([1.0, 1.0, 1.0]); targets.add([0.1]);
    // Rule 4: Wrong Split (Doesn't fit split, not fatigued, familiar) -> Avoid completely
    trainingData.add([0.0, 0.0, 1.0]); targets.add([0.0]);
    // Rule 5: Wrong Split + Fatigued -> Avoid completely
    trainingData.add([0.0, 1.0, 1.0]); targets.add([0.0]);
    // Rule 6: Moderate Fatigue -> Moderate penalty
    trainingData.add([1.0, 0.5, 1.0]); targets.add([0.6]);
    // Rule 7: Complete random -> 0.0
    trainingData.add([0.0, 1.0, 0.0]); targets.add([0.0]);

    // 3. Train the Network (Lightning fast on-device Backpropagation)
    debugPrint('Training on-device neural network...');
    nn.train(trainingData, targets, 150, 0.5);

    // 4. Score all exercises
    List<Map<String, dynamic>> scoredExercises = [];

    for (var ex in allExercises) {
      if (onlyFamiliar && !ex.isFavorite && ex.folderNames.isEmpty) {
        continue; // Skip if strict familiar and it's new
      }

      double splitMatch = _calculateSplitMatch(ex, splitTypes);
      double fatiguePenalty = _calculateFatiguePenalty(ex, currentFatigue);
      double isFamiliar = ex.isFavorite ? 1.0 : (ex.folderNames.isNotEmpty ? 0.5 : 0.0);

      // Inference
      List<double> prediction = nn.forward([splitMatch, fatiguePenalty, isFamiliar]);
      double score = prediction[0];

      // Add a tiny bit of random noise to break ties
      final randomNoise = (Random().nextDouble() * 0.1);
      
      scoredExercises.add({
        'exercise': ex,
        'score': score + randomNoise,
      });
    }

    // 5. Sort by highest score
    scoredExercises.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // 6. Return top 6-8 exercises to form a sensible workout volume
    int workoutSize = 6 + Random().nextInt(3); // 6 to 8 exercises
    return scoredExercises.take(workoutSize).map((e) => e['exercise'] as Exercise).toList();
  }

  static double _calculateSplitMatch(Exercise ex, List<String> splits) {
    if (splits.contains('Fullbody') || splits.isEmpty) return 1.0;
    
    List<String> validMuscles = [];
    for (var split in splits) {
      validMuscles.addAll(_splitDefinitions[split] ?? []);
    }
    
    List<String> allMuscles = [...ex.targetMuscles, ...ex.secondaryMuscles];
    if (allMuscles.isEmpty && ex.targetMuscle.isNotEmpty) allMuscles.add(ex.targetMuscle);

    bool hasMatch = allMuscles.any((m) {
      // Handle pluralization mapping
      String baseM = m;
      if (baseM.endsWith('s') && !validMuscles.contains(baseM)) baseM = baseM.substring(0, baseM.length - 1);
      return validMuscles.contains(m) || validMuscles.contains('${m}s') || validMuscles.contains(baseM);
    });
    
    return hasMatch ? 1.0 : 0.0;
  }

  static double _calculateFatiguePenalty(Exercise ex, Map<String, double> fatigueMap) {
    List<String> mains = ex.targetMuscles.isNotEmpty ? ex.targetMuscles : [ex.targetMuscle];
    double maxFatigue = 0.0;
    for (var m in mains) {
      double f = fatigueMap[m] ?? 0.0;
      if (f > maxFatigue) maxFatigue = f;
    }
    return maxFatigue.clamp(0.0, 1.0);
  }
}
