package com.example.workout_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import android.util.Log
import android.net.Uri
import java.util.Calendar

class RunningWidgetProvider : HomeWidgetProvider() {
    
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        
        // Get today's day index and date string
        val calendar = Calendar.getInstance()
        var dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) - 2
        if (dayOfWeek < 0) dayOfWeek += 7
        
        val month = calendar.get(Calendar.MONTH) + 1
        val day = calendar.get(Calendar.DAY_OF_MONTH)
        val dateString = "$month/$day"
        
        val todayMiles = prefs.getInt("day_${dayOfWeek}_miles", 0)
        
        // Theme Colors (Safely parsed from Hex Strings)
        val bgColor = try { Color.parseColor(prefs.getString("theme_bg_hex", "#120E15")) } catch (e: Exception) { Color.parseColor("#120E15") }
        val accentColor = try { Color.parseColor(prefs.getString("theme_accent_hex", "#D93846")) } catch (e: Exception) { Color.parseColor("#D93846") }
        val textColor = try { Color.parseColor(prefs.getString("theme_text_hex", "#AAAAAA")) } catch (e: Exception) { Color.parseColor("#AAAAAA") }
        val subTextColor = try { Color.parseColor(prefs.getString("theme_subText_hex", "#888888")) } catch (e: Exception) { Color.parseColor("#888888") }

        val dayLabelsFull = arrayOf("MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY")

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.running_widget_final)
            
            // APPLY COLORS
            views.setInt(R.id.widget_background, "setBackgroundColor", bgColor)
            views.setTextColor(R.id.today_miles, accentColor)
            views.setTextColor(R.id.day_title, textColor)
            views.setTextColor(R.id.miles_label, subTextColor)
            views.setInt(R.id.widget_refresh, "setColorFilter", subTextColor)

            // OPEN APP INTENT (on Title)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                data = Uri.parse("hybridlog://open_app?ts=${System.currentTimeMillis()}")
            }
            val pendingLaunchIntent = PendingIntent.getActivity(
                context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.day_title, pendingLaunchIntent)

            // INCREMENT INTENT (Optimistic update via native side first)
            val customIncIntent = Intent(context, RunningWidgetProvider::class.java).apply {
                action = "INCREMENT_TALLY"
                data = Uri.parse("hybridlog://native_increment?dayOfWeek=$dayOfWeek&ts=${System.currentTimeMillis()}")
                putExtra("dayOfWeek", dayOfWeek)
            }
            val uniqueId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            val pendingCustomIncIntent = PendingIntent.getBroadcast(
                context,
                uniqueId,
                customIncIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_increment_area, pendingCustomIncIntent)
            
            // REFRESH INTENT (On icon)
            val refreshUri = Uri.parse("hybridlog://refresh_widget?ts=${System.currentTimeMillis()}")
            val refreshIntent = HomeWidgetBackgroundIntent.getBroadcast(context, refreshUri)
            views.setOnClickPendingIntent(R.id.widget_refresh, refreshIntent)
            
            // Set data
            views.setTextViewText(R.id.day_title, "${dayLabelsFull[dayOfWeek]} $dateString")
            views.setTextViewText(R.id.today_miles, "$todayMiles")
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, RunningWidgetProvider::class.java)
        val ids = manager.getAppWidgetIds(component)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        if (intent.action == "INCREMENT_TALLY") {
            val dayOfWeek = intent.getIntExtra("dayOfWeek", -1)
            if (dayOfWeek != -1) {
                // Optimistic UI Update
                val currentMiles = prefs.getInt("day_${dayOfWeek}_miles", 0)
                prefs.edit().putInt("day_${dayOfWeek}_miles", currentMiles + 1).apply()
                
                // Re-render instantly with the new value
                onUpdate(context, manager, ids, prefs)
                
                // Forward the background intent to Flutter to persist the data
                val incUri = Uri.parse("hybridlog://increment_day?dayIndex=$dayOfWeek&ts=${System.currentTimeMillis()}")
                val flutterPendingIntent = HomeWidgetBackgroundIntent.getBroadcast(context, incUri)
                try {
                    flutterPendingIntent.send()
                } catch (e: PendingIntent.CanceledException) {
                    Log.e("RunningWidget", "Failed to forward intent to flutter", e)
                }
            }
        } else {
            // Normal widget updates (e.g. from Flutter push or system)
            onUpdate(context, manager, ids, prefs)
        }
    }
}
