import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const String _tutorialSeenKey = 'has_seen_main_tutorial';
  static const String _workoutTutorialSeenKey = 'has_seen_workout_tutorial';

  static GlobalKey? createFolderKey;
  static GlobalKey? exerciseCardKey;
  static GlobalKey? appDrawerKey;
  static GlobalKey? historyTabKey;

  static Future<bool> hasSeenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tutorialSeenKey) ?? false;
  }

  static Future<bool> hasSeenWorkoutTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_workoutTutorialSeenKey) ?? false;
  }

  static Future<void> markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialSeenKey, true);
  }

  static Future<void> markWorkoutTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_workoutTutorialSeenKey, true);
  }

  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tutorialSeenKey);
    await prefs.remove(_workoutTutorialSeenKey);
  }

  static void showMainTutorial({
    required BuildContext context,
    required GlobalKey runningGraphKey,
    required GlobalKey runningYearlyHistoryKey,
    required GlobalKey settingsKey,
    required GlobalKey swipeNavKey,
    required VoidCallback onNavigateToWorkout,
    required VoidCallback onFinish,
  }) {
    List<TargetFocus> targets = [
      TargetFocus(
        identify: "RunningGraph",
        keyTarget: runningGraphKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Running Log", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Here you can track your daily running mileage. The blocks fill up as you add more miles for the day.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "YearlyHistory",
        keyTarget: runningYearlyHistoryKey,
        alignSkip: Alignment.topLeft,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Yearly History", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("This heatmap shows your running consistency over the entire year. Tap any square to view details.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "Settings",
        keyTarget: settingsKey,
        alignSkip: Alignment.bottomLeft,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Text("Settings & Themes", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Tap here to backup your data, change to our custom monkeytype-style themes, or replay this tutorial.", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "SwipeNav",
        keyTarget: swipeNavKey,
        alignSkip: Alignment.topLeft,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text("Resistance Training", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("We'll now swipe over to the workout side of the app to continue the tour.", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.right),
                ],
              );
            },
          )
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.85,
      onFinish: () {
        onNavigateToWorkout();
        onFinish();
      },
      onSkip: () {
        onFinish();
        return true;
      },
    ).show(context: context);
  }

  static void showWorkoutTutorial({
    required BuildContext context,
    required GlobalKey createFolderKey,
    required GlobalKey exerciseCardKey,
    required GlobalKey appDrawerKey,
    required GlobalKey historyTabKey,
    required VoidCallback onFinish,
  }) {
    List<TargetFocus> targets = [
      TargetFocus(
        identify: "CreateFolder",
        keyTarget: createFolderKey,
        alignSkip: Alignment.bottomLeft,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Create Folders", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Tap here to create custom workout folders like 'Push Day' or 'Legs'.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "ExerciseCard",
        keyTarget: exerciseCardKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Detailed View", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Long-press any exercise card (or tap the detailed view icon in the menu) to jump into its detailed workout history and metrics chart.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "AppDrawer",
        keyTarget: appDrawerKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Text("Exercise Library", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Pull up this bottom drawer to view all exercises in the library. From there, you can star them to add them to your folders.", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                ],
              );
            },
          )
        ],
      ),
      TargetFocus(
        identify: "HistoryTab",
        keyTarget: historyTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Text("Workout History", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("Inside the drawer, tap the history tab to view a chronological timeline of all your past workouts.", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                ],
              );
            },
          )
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "DONE",
      paddingFocus: 10,
      opacityShadow: 0.85,
      onFinish: onFinish,
      onSkip: () {
        onFinish();
        return true;
      },
    ).show(context: context);
  }
}
