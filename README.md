# 🧊 HybridLog
HybridLog is a high-performance, minimalist fitness tracker designed for the sophisticated athlete. It combines high-density information architecture with a tactile aesthetic to turn every workout into a building block for your future self.

---

## Aesthetic & Philosophy

*   **Quiet Luxury:** A muted, non-intrusive color palette.
*   **Tactile Feedback:** Every interaction uses animation suite—staggered pops, springy buttons, and satisfying snapping transitions.
*   **Gesture-Driven:** No cluttered navigation bars. Navigate through your training history and planning with smooth, horizontal swipes.

---

## 🚀 Key Features

*   **🏗️ Building Block Graph:** A vertical-drag running mileage tracker. Add miles like blocks and watch your week build up.
*   **⚖️ Resistance Training Tracking:** Log exercises, sets, and reps with a UI optimized for speed and stability. Organizes exercises across folders, featuring advanced filtering (by muscle & manufacturer), clean hierarchical naming for long exercises, and custom sorting (A-Z, Z-A, and Most Recent).
*   **🌙 Environment-Aware Weather Intelligence:** Real-time outdoor workout advice that adjusts for temperature, wind, and sunset. Features a night-mode moon icon and safety tips after dark.
*   **📦 Muscle-Group Visualization:** Standardized anatomical tracking (e.g., "Front Deltoids") featuring multiple main/secondary muscle selections and interactive front/back body SVG previews.
*   **🔥 Volume-Load Fatigue Heatmap:** Real-time muscle recovery visualization using a calibrated `weight × reps` volume-load model with time-decay, high-rep bonuses, and per-muscle thresholds.
*   **📅 High-Density Workout History:** Dynamic chronological log organized by year-based selectors with collapsible weekday date cards and dedicated details popups.
*   **🏠 Live Home-Screen Widget:** Keep your weekly progress at a glance with a real-time, interactive Android widget that bypasses OS caching for instant sync.
*   **🎨 Custom Theming & Monkeytype-like Palettes:** Choose from 11 custom themes (Carbon, Serika Dark, Nord, Cyberpunk, Laser, Sakura, Botanical, Modern Ink, Terra, Matrix, Red Dragon) via a horizontal visual preview selector showcasing actual color combinations.

---

## 🛠️ Technology Stack

*   **Framework:** [Flutter](https://flutter.dev/) (3.x)
*   **Database:** [Isar](https://isar.dev/) - An ultra-fast, cross-platform NoSQL database.
*   **State Management:** Service-based architecture with Stream-based real-time UI updates.
*   **Native Integration:** Kotlin-based Android AppWidgets with custom atomic broadcast receivers.

---

## 🛡️ Privacy & Data Integrity

**Your data belongs to you.**
*   **Local Only:** HybridLog does not use any cloud backends. All workout history, mileage, and personal metrics are stored strictly on your device using the encrypted Isar database.
*   **Zero Remote Access:** No user data is ever uploaded, shared, or accessible from GitHub or any remote server.
*   **Offline First:** Works anywhere.

---

## 📥 Getting Started

### Installation
You can download the latest compiled version directly from this repository: **[Download HybridLog.apk](release/HybridLog.apk)**.

1.  Download [HybridLog.apk](release/HybridLog.apk) to your Android device.
2.  Enable "Install from Unknown Sources" in your device settings.
3.  Open the APK to install and start tracking.

---

Have fun!
