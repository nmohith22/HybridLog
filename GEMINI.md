# Workout App (HybridLog) - Project Instructions

## Project Overview
A senior-engineered, high-performance fitness tracking application built with Flutter and Isar Database. The app focuses on a "quiet luxury" aesthetic with high-density information displays, a gesture-driven navigation model, and interactive home screen widgets.

## Technical Stack
- **Framework:** Flutter (Dart)
- **Database:** Isar (NoSQL, high-performance)
- **Navigation:** Gesture-based `PageView` (no bottom bar) with subtle side-arrow hints.
- **Animations:** Custom "Lego Video Game" suite (staggered pops, springy buttons).

## Resumption Instructions
- **Checkpoint-First:** When asked to "resume from the most recent chat" or "pick up where we left off," always check the **Checkpoint: May 3, 2026** section below. 
- **Priority:** If the user chat history is newer than this checkpoint, prioritize the chat context. Otherwise, use this checkpoint as the ground truth for state.

## Checkpoint: May 3, 2026 (Final State)
### 1. Widget Interactivity (`lib/services/widget_service.dart`)
- **Native Implementation:** `RunningWidgetProvider.kt`. Standardized naming across Manifest, Kotlin, and Dart (removed all "V2" remnants).
- **Atomic Refresh:** Uses `manager.updateAppWidget(ComponentName, views)` to hit all instances simultaneously.
- **Dirty View Fix:** Native code injects a unique timestamp (`System.currentTimeMillis()`) into intent URIs for every update. This forces Android to bypass its layout cache and repaint visuals in real-time.
- **Sync:** Manually opens `HomeWidgetPreferences` on every broadcast to guarantee latest data.

### 2. Animations & UI
- **LegoPop:** Applied to lists (Library, Favorites, History). For the **Block Graph**, LegoPop only wraps the entire container (triggers on screen entrance, not on block changes or week swipes).
- **Block Graph Logic:** Changes to block counts are **instant** (no animations for adding/deleting miles). Week swiping uses a simple horizontal swipe with an opacity fade gradient.
- **SpringyButton:** Applied to all interactable elements for a tactile feel.
- **Navigation:** PageView-based. A muted, right-pointing chevron (`chevron_right`) is located to the left of the "Weekly Breakdown" title on the Weights screen.

### 3. Weather Advice
- **Night-Aware:** Uses sunset `DateTime` to switch to Moon icons (`nightlight_round`) and night-appropriate advice after dark.
- **Precipitation:** Zero-tolerance policy. Any rain/snow overrides all advice to "Indoor workout recommended."
- **Holistic Logic:** Weights factors together (e.g., identifies "Horrible pacing" if high wind is combined with otherwise okay temps).

### 4. Database & Terminology
- **Muscle Names:** Standardized to **plural** (e.g., `front_deltoids`). Automatic migration logic exists in `_initializeData`.
- **Seeding:** Verification logic checks total exercise count against `initialExercises` to ensure new library additions are always present.

## Developer Guidelines
- **Widget Naming:** Kotlin class, Manifest receiver, and `WidgetService` name MUST all match `RunningWidgetProvider` exactly.
- **Theme:** Default is `ThemeMode.system`. Follow device preferences for Light/Dark mode. Toggle cycles System -> Light -> Dark.
- **Immersive Mode:** `SystemUiMode.immersiveSticky` is enforced to hide system UI bars.
