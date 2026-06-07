# Workout App (HybridLog) - Project Instructions

## Project Overview
A senior-engineered, high-performance fitness tracking application built with Flutter and Isar Database. The app focuses on a "quiet luxury" aesthetic with high-density information architecture, a gesture-driven navigation model, and interactive home screen widgets.

## Technical Stack
- **Framework:** Flutter (Dart)
- **Database:** Isar (NoSQL, local-only, encrypted)
- **Navigation:** Gesture-based `PageView` (no bottom bar) with subtle side-arrow hints.
- **Animations:** Custom "Lego Video Game" suite (staggered pops, springy buttons).
- **Native:** Kotlin-based Android AppWidgets with Atomic/Dirty View refreshes.

## Core Mandates
- **Privacy First:** Data is strictly local-only. NEVER introduce cloud sync, remote backends, or telemetry. All user metrics must stay in the device's Isar database.
- **Visual Integrity:** Maintain the "Quiet Luxury" palette (muted colors, high contrast text) and the "Lego" animation staggered timings (30ms delay, 400ms duration).
- **Widget Stability:** Any change to Widget logic must respect the `RunningWidgetProvider` naming and the "Dirty View" timestamp pattern to bypass Android's layout cache.

## GitHub & Deployment
- **Repository:** [https://github.com/nmohith22/HybridLog.git](https://github.com/nmohith22/HybridLog.git)
- **Releases:** The `release/HybridLog.apk` file must be updated and committed whenever a major UI or logic milestone is reached.
- **Workflow:** Always `git add .`, `git commit`, and `git push origin main` after verifying changes.

## Resumption Instructions
- **Checkpoint-First:** When asked to "resume from the most recent chat" or "pick up where we left off," always check the **Checkpoint: May 3, 2026** section below. 
- **Priority:** If the user chat history is newer than this checkpoint, prioritize the chat context. Otherwise, use this checkpoint as the ground truth for state.

## Checkpoint: June 7, 2026 (Multi-Muscle, Multi-Folder & History Redesign)
### 1. Schema & Data Updates
- **Multiple Target/Secondary Muscles:** Re-engineered the database schema in `Exercise` and `LoggedExercise` to use `List<String> targetMuscles` and `List<String> secondaryMuscles`. Legacy database models automatically migrate their single string fields into the new list attributes at startup.
- **Multi-Folder Organization:** Changed the exercise-to-folder mapping from a single folder relationship to a list (`List<String> folderNames`), allowing the same exercise to exist in multiple library folders.
- **Backup & Restore Compatibility:** Updated data backup JSON format and import logic to correctly serialize and deserialize target muscles and folder name list properties.

### 2. UI & Features
- **Body SVG Preview:** Added a side-by-side front/back anatomical body preview (in SVG) on the custom exercise creation screen. Highlights main target muscles in red and secondary muscles in orange as they are selected.
- **Multi-Select Chips & Checklists:** Implemented multi-select target/secondary muscle chips and a checklist toggle for folders in the exercise creator modal.
- **History Tab Redesign:** Rewrote the workout history section to render chronologically descending date/weekday cards grouped under a top-left year selector.
- **Workout Detail Modals:** Tapping a history card opens a modal overlay featuring an "X" header close button, date/weekday info, and cards for all logged exercises.

### 3. Toolchain & Build Fixes
- **Local Toolchain Setup:** Configured Windows local SDK path at `C:\Users\mskyl\android_sdk` and OpenJDK 17 at `C:\Users\mskyl\openjdk\jdk-17.0.11+9`.
- **Gradle Configuration:** Fixed the hardcoded `org.gradle.java.home` path in `android/gradle.properties` to map to the new JDK path, resolving build environment discrepancies.

### 4. Fatigue Calculation Overhaul
- **Volume-Load Model:** Replaced naive rep-counting with a proper `weight × reps` volume-load metric per set. Bodyweight exercises use a 25 lb fallback.
- **Time Decay:** Sessions today count at 100% while sessions 7 days ago decay to ~30%, so the heatmap naturally cools as recovery progresses.
- **High-Rep & Multi-Set Bonuses:** Sets averaging >20 reps get a 1.15× endurance multiplier. Cumulative set bonuses scale from 1.05× (3 sets) to 1.15× (5+ sets).
- **Sub-Muscle Roll-Up:** `bicep_short_head`, `bicep_long_head`, `tricep_long_head`, `forearm`, `adductors`, and `upper_back` now roll their fatigue up into their parent muscle group for correct SVG heatmap rendering.
- **Per-Muscle Thresholds:** Calibrated individually (e.g., biceps = 4000 lb·reps, chest = 14000 lb·reps) instead of using 3 flat tiers.
- **Secondary Muscle Credit:** Secondary muscles receive 40% of the volume-load.

## Checkpoint: May 25, 2026 (UI Swap & Navigation Fix)
### 1. Navigation & Page Order
- **Primary Page:** The app now opens to the **Running Log** (index 0).
- **Secondary Page:** **Resistance Training** (Weekly Breakdown) is now index 1.
- **Settings:** The settings wheel has been moved to the Running Log screen.
- **Hints:** Navigation chevrons updated: Right chevron on Running Log, Left chevron on Resistance Training.

### 2. Logging & Input Stability
- **Keyboard Fix:** Replaced `UniqueKey` with stable `ValueKey` in the logging sheet to prevent keyboard dismissal on input.
- **Input Enforcement:** Weight and Reps fields now strictly enforce numeric input via `TextInputType` and `FilteringTextInputFormatter`.

## Checkpoint: May 3, 2026 (GitHub Final Release)
### 1. Source Control & Deployment
- **Status:** Initialized and pushed to GitHub.
- **Release Tracking:** Latest release APK is tracked in the `release/HybridLog.apk` directory.
- **Privacy:** Confirmed local-only architecture with no remote hooks.

### 2. Widget Interactivity (`lib/services/widget_service.dart`)
- **Native Implementation:** `RunningWidgetProvider.kt`.
- **Atomic Refresh:** Uses `manager.updateAppWidget(ComponentName, views)` for universal instance updates.
- **Dirty View Fix:** Native code injects unique timestamps into intent URIs to bypass Android's layout cache and ensure real-time visual updates.

### 3. Animations & UI
- **LegoPop:** Global staggered entry (30ms/400ms). Applied to the Block Graph container only on initial load.
- **Block Graph:** Instant updates for adding/deleting blocks. Simple swipe/fade for week navigation.
- **Night-Aware:** Sunset-based `DateTime` logic toggles Moon icons (`nightlight_round`) and nighttime advice.
- **Navigation:** Muted `chevron_right` located to the left of the "Weekly Breakdown" title on the Weights screen.

### 4. Database & Terminology
- **Muscle Names:** Strictly plural (e.g., `front_deltoids`).
- **Seeding:** High-integrity verify-and-seed logic ensures library completeness.

## Developer Guidelines
- **Widget Naming:** MUST match `RunningWidgetProvider` exactly.
- **Immersive Mode:** `SystemUiMode.immersiveSticky` is mandatory.
- **Theme:** Follow `ThemeMode.system` by default.
