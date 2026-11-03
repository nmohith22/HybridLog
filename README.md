# HybridLog

HybridLog is an Android app for tracking strength workouts and running.

## Features

- Log strength workouts, sets, weight, and reps; organize favorite exercises into folders.
- Browse workout history with session muscle heatmaps and recovery estimates.
- Generate workout plans with Needle3 using recent workouts, training focus, and available equipment. Plans can be saved to Favorites.
- Ask Needle to read, create, update, or delete exercises, folders, workouts, and runs. Changes require approval; deletion also requires a checked confirmation.
- Track runs and update the Android home-screen widget.
- Choose a visual theme and import or export app data from Settings.

Needle3 is bundled with the app and runs on-device on ARM Android devices. The release app does not request the Android Internet permission, and the app sends no workout or running data over a network. Import and export are user-initiated through Android's file picker and share sheet. Backups include exercises, favorites and folders, workout sets and dropsets, rest-pause settings, logged muscle data, running logs, and the selected theme. Older backups remain supported. Needle3 is provided under Apache-2.0; its license is included with the bundled model. [Needle3 source](https://github.com/cactus-compute/needle).

## Install

Download the latest Android APK: **[Download HybridLog 1.0.7 for Android](https://github.com/nmohith22/HybridLog/releases/download/v1.0.7/HybridLog-1.0.7.apk)** | [All releases](https://github.com/nmohith22/HybridLog/releases).

## Build

Requires Flutter, the Android SDK and NDK, and CMake.

```sh
flutter pub get
flutter build apk --release
```
