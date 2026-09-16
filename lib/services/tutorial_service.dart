import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const String _tutorialSeenKey = 'has_seen_main_tutorial';

  static Future<bool> hasSeenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tutorialSeenKey) ?? false;
  }

  static Future<void> markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialSeenKey, true);
  }

  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tutorialSeenKey);
  }

  static void showMainTutorial({
    required BuildContext context,
    required GlobalKey runningGraphKey,
    required GlobalKey settingsKey,
    required GlobalKey swipeNavKey,
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
                  Text(
                    "Running Log",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Here you can track your daily running mileage. The blocks fill up as you add more miles for the day.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
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
                  Text(
                    "Resistance Training",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Swipe left or tap this chevron to flip over to the weightlifting and workout side of the app.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.right,
                  ),
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
                  Text(
                    "Settings & Themes",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Tap here to backup your data, change to our custom monkeytype-style themes, or replay this tutorial.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
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
      onFinish: onFinish,
      onSkip: () {
        onFinish();
        return true;
      },
    ).show(context: context);
  }
}
