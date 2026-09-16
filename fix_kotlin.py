import re

with open('android/app/src/main/kotlin/com/example/workout_app/RunningWidgetProvider.kt', 'r', encoding='utf-8') as f:
    code = f.read()

# Replace refresh intent to use Kotlin intercept
old_refresh = '''            // REFRESH INTENT (On icon)
            val refreshUri = Uri.parse("hybridlog://refresh_widget?ts=")
            val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(context, refreshUri)
            views.setOnClickPendingIntent(R.id.widget_refresh, refreshIntent)'''

new_refresh = '''            // REFRESH INTENT (Intercepted by Kotlin first)
            val customRefreshIntent = Intent(context, RunningWidgetProvider::class.java).apply {
                action = "REFRESH_WIDGET"
            }
            val pendingCustomRefreshIntent = PendingIntent.getBroadcast(
                context,
                1, // unique request code
                customRefreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_refresh, pendingCustomRefreshIntent)'''

code = code.replace(old_refresh, new_refresh)

# Add REFRESH_WIDGET to onReceive
old_onreceive = '''        if (intent.action == "INCREMENT_TALLY") {
            val dayOfWeek = intent.getIntExtra("dayOfWeek", -1)
            if (dayOfWeek != -1) {
                // Optimistic UI Update
                val currentMiles = prefs.getInt("day__miles", 0)
                prefs.edit().putInt("day__miles", currentMiles + 1).apply()
                
                // Re-render instantly with the new value
                onUpdate(context, manager, ids, prefs)
                
                // Forward the background intent to Flutter to persist the data
                val incUri = Uri.parse("hybridlog://increment_day?dayIndex=&ts=")
                val flutterPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(context, incUri)
                try {
                    flutterPendingIntent.send()
                } catch (e: PendingIntent.CanceledException) {
                    Log.e("RunningWidget", "Failed to forward intent to flutter", e)
                }
            }
        } else {'''

new_onreceive = '''        if (intent.action == "INCREMENT_TALLY") {
            val dayOfWeek = intent.getIntExtra("dayOfWeek", -1)
            if (dayOfWeek != -1) {
                // Optimistic UI Update
                val currentMiles = prefs.getInt("day__miles", 0)
                prefs.edit().putInt("day__miles", currentMiles + 1).apply()
                
                // Re-render instantly with the new value
                onUpdate(context, manager, ids, prefs)
                
                // Forward the background intent to Flutter to persist the data
                val incUri = Uri.parse("hybridlog://increment_day?dayIndex=&ts=")
                val flutterPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(context, incUri)
                try {
                    flutterPendingIntent.send()
                } catch (e: PendingIntent.CanceledException) {
                    Log.e("RunningWidget", "Failed to forward intent to flutter", e)
                }
            }
        } else if (intent.action == "REFRESH_WIDGET") {
            val refreshUri = Uri.parse("hybridlog://refresh_widget?ts=")
            val flutterPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(context, refreshUri)
            try {
                flutterPendingIntent.send()
            } catch (e: PendingIntent.CanceledException) {
                Log.e("RunningWidget", "Failed to forward refresh intent to flutter", e)
            }
        } else {'''

code = code.replace(old_onreceive, new_onreceive)

with open('android/app/src/main/kotlin/com/example/workout_app/RunningWidgetProvider.kt', 'w', encoding='utf-8') as f:
    f.write(code)
