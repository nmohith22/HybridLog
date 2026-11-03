# HybridLog

HybridLog is an Android app for tracking strength workouts and running.

## Features

- **Strength workouts:** Log exercises, sets, weight, and reps. Search and filter the exercise library, add custom exercises, and organize favorites into folders.
- **All Workouts:** Browse sessions by year, view workout details, and see a front or back muscle heatmap on each session card.
- **Needle3 workout planner:** Generate a plan from recent workouts, training focus, exercise familiarity, and recovery state. Mark unavailable equipment to request substitutions, then save the plan to a Favorites folder. The Apache-2.0 Needle3 model downloads on first use (about 35 MB); inference runs on-device on ARM Android devices. [Needle3 source](https://github.com/cactus-compute/needle).
- **Recovery:** Review a weekly muscle fatigue heatmap and estimated recovery times.
- **Running:** Track mileage, view weather advice, and update the Android home-screen widget.
- **Themes and data:** Choose a color theme and import or export workout data from Settings.

Workout and running logs are stored locally. Workout planning runs locally after the Needle3 model download. Weather advice uses online weather and location services.

## Install

Download the latest Android APK: **[Download HybridLog 1.0.5 for Android](https://github.com/nmohith22/HybridLog/releases/download/v1.0.5/HybridLog-1.0.5.apk)** | [All releases](https://github.com/nmohith22/HybridLog/releases).

## Build

Requires Flutter, the Android SDK and NDK, and CMake.

```sh
flutter pub get
flutter build apk --release
```
