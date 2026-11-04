# HybridLog

HybridLog is an Android app for tracking strength workouts and running.

## Features

- Log strength workouts, sets, weight, and reps; organize favorite exercises into folders.
- Browse workout history with session muscle heatmaps and recovery estimates.
- Use Steel, the bundled Needle3 assistant, in a themed chat modal to plan workouts from history and equipment, draft logs from plain text, ask history questions, or get weekly recaps and progression suggestions.
- Save unavailable equipment locally so workout plans can account for the user's equipment profile.
- Ask Steel to read, create, update, or delete exercises, folders, workouts, and runs. Changes require approval; deletion also requires a checked confirmation.
- Track runs, see live conditions and sunrise/sunset for a saved city, and update the Android home-screen widget.
- Choose a visual theme and import or export app data from Settings.
- Release builds run Flutter tests and a local, LLM-free pytest/Ragas evaluation of Steel's operation guardrails, with Ragas telemetry disabled.

Needle3 is bundled with the app and runs on-device on ARM Android devices. Workout and running logs stay on the device. Weather uses a manually entered city: HybridLog stores the preference locally and refreshes its conditions automatically when the running weather card opens. Each lookup sends that city and its matched coordinates to Open-Meteo; the app does not read device location or use IP-based location lookup. Open-Meteo may log request IP addresses and coordinates for service operation; its [terms and privacy notice](https://open-meteo.com/en/terms) say those logs are deleted after 90 days. The free weather API is for non-commercial use. Weather data is attributed to Open-Meteo and location data to GeoNames. Import and export are user-initiated through Android's file picker and share sheet. Backups include exercises, favorites and folders, workout sets and dropsets, rest-pause settings, logged muscle data, running logs, the selected theme, and the saved equipment profile. Older backups remain supported. [Steel's conversation and safety guardrails](STEEL_GUARDRAILS.md). Needle3 is provided under Apache-2.0; its license is included with the bundled model. [Needle3 source](https://github.com/cactus-compute/needle).

## Install

Download the latest Android APK: **[Download HybridLog 1.0.15 for Android](https://github.com/nmohith22/HybridLog/releases/download/v1.0.15/HybridLog-1.0.15.apk)** | [All releases](https://github.com/nmohith22/HybridLog/releases).

## Build

Requires Flutter, the Android SDK and NDK, and CMake.

```sh
flutter pub get
flutter build apk --release
```
