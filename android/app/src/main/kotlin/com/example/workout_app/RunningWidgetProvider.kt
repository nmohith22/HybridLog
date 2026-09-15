package com.example.workout_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
        
        // Get today's day index (0 for Monday, 6 for Sunday) to match Dart logic
        val calendar = Calendar.getInstance()
        var dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) - 2
        if (dayOfWeek < 0) dayOfWeek += 7
        
        val todayMiles = prefs.getInt("day_${dayOfWeek}_miles", 0)
        
        Log.e("RunningWidget", "Visual Sync Start. Today ($dayOfWeek): $todayMiles")

        val dayLabelsFull = arrayOf("MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY")

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.running_widget_final)
            
            // OPEN APP INTENT (on Title)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                data = Uri.parse("hybridlog://open_app?ts=${System.currentTimeMillis()}")
            }
            val pendingLaunchIntent = PendingIntent.getActivity(
                context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.day_title, pendingLaunchIntent)

            // INCREMENT INTENT (on the entire widget root or a big button)
            val incUri = Uri.parse("hybridlog://increment_day?dayIndex=$dayOfWeek&ts=${System.currentTimeMillis()}")
            val incIntent = HomeWidgetBackgroundIntent.getBroadcast(context, incUri)
            views.setOnClickPendingIntent(R.id.widget_increment_area, incIntent)
            
            // Set data
            views.setTextViewText(R.id.day_title, dayLabelsFull[dayOfWeek])
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
        onUpdate(context, manager, ids, prefs)
    }
}
