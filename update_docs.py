import re

# Update GEMINI.md
with open('GEMINI.md', 'r', encoding='utf-8') as f:
    gemini = f.read()

checkpoint = '''## Checkpoint: September 15, 2026 (Widget Tally Counter & Optimistic UI)
### 1. Widget Redesign
- **Tally Counter Layout:** Replaced the 7-day week view with a compact 2x2 daily tally counter focusing on today's miles.
- **Optimistic UI Updates:** Shifted widget tap handling to the native Kotlin layer (RunningWidgetProvider) to instantly increment the counter and redraw the UI in 0ms, bypassing the Flutter background start delay. The click is then forwarded to Flutter silently to persist in the Isar database.
- **Theme Inheritance:** The widget now dynamically inherits its background, text, and accent colors from the active theme chosen inside the main app. Colors are passed as hex strings (#FF...) rather than integers to prevent Android ClassCastException crashes when reading 64-bit Dart values from SharedPreferences.
- **Widget Crash Resolved:** Fixed a silent ActionException in Android's RemoteViews caused by attempting to use setColorFilter on an ImageView inside the widget, which froze all visual updates.
- **Lifecycle Refresh:** Integrated WidgetsBindingObserver into the main app lifecycle to automatically push updates to the widget when the user closes or backgrounds the app.
- **Manual Refresh:** Added a small refresh icon to the widget that triggers a direct database fetch without incrementing the tally.
'''
gemini = re.sub(r'## Checkpoint: September 15, 2026.*?## Checkpoint: July 11, 2026', checkpoint + '\n## Checkpoint: July 11, 2026', gemini, flags=re.DOTALL)

with open('GEMINI.md', 'w', encoding='utf-8') as f:
    f.write(gemini)

# Update README.md
with open('README.md', 'r', encoding='utf-8') as f:
    readme = f.read()

# Add bullet to recent updates
readme = readme.replace('- Interactive l_chart exercise history with touch tooltips and max-weight tracking.', '- Interactive l_chart exercise history with touch tooltips and max-weight tracking.\n- Interactive native Android AppWidgets with zero-latency optimistic UI and dynamic theme inheritance.')

with open('README.md', 'w', encoding='utf-8') as f:
    f.write(readme)
