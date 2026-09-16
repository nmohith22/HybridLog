import re

with open('android/app/src/main/kotlin/com/example/workout_app/RunningWidgetProvider.kt', 'r', encoding='utf-8') as f:
    code = f.read()

code = code.replace('views.setInt(R.id.widget_refresh, "setColorFilter", subTextColor)', '// views.setInt(R.id.widget_refresh, "setColorFilter", subTextColor) // Removed to prevent ActionException on some Android versions')

with open('android/app/src/main/kotlin/com/example/workout_app/RunningWidgetProvider.kt', 'w', encoding='utf-8') as f:
    f.write(code)
