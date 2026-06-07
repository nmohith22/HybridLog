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

class RunningWidgetProvider : HomeWidgetProvider() {
    
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val totalMiles = prefs.getInt("total_miles", 0)
        
        Log.e("RunningWidget", "Visual Sync Start. Total: $totalMiles")

        val dayLabels = arrayOf("M", "T", "W", "T", "F", "S", "S")

        // Force instance loop for extreme reliability
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.running_widget_final)
            
            // ATOMIC TIMESTAMP to bypass Android layout caching
            views.setTextViewText(R.id.total_miles, "$totalMiles mi")
            
            for (i in 0..6) {
                val miles = prefs.getInt("day_${i}_miles", 0)
                
                // DAY LABEL
                val decId = context.resources.getIdentifier("btn_dec_$i", "id", context.packageName)
                if (decId != 0) {
                    views.setTextViewText(decId, dayLabels[i])
                    val decUri = Uri.parse("hybridlog://decrement_day?dayIndex=$i&ts=${System.currentTimeMillis()}")
                    val decIntent = HomeWidgetBackgroundIntent.getBroadcast(context, decUri)
                    views.setOnClickPendingIntent(decId, decIntent)
                }

                // BLOCKS
                val incId = context.resources.getIdentifier("btn_inc_$i", "id", context.packageName)
                if (incId != 0) {
                    val blocks = StringBuilder()
                    for (b in 0 until miles) blocks.append("█ ")
                    if (blocks.isEmpty()) blocks.append("  ")
                    views.setTextViewText(incId, blocks.toString())
                    
                    val incUri = Uri.parse("hybridlog://increment_day?dayIndex=$i&ts=${System.currentTimeMillis()}")
                    val incIntent = HomeWidgetBackgroundIntent.getBroadcast(context, incUri)
                    views.setOnClickPendingIntent(incId, incIntent)
                }

                // MILEAGE TEXT
                val milesTextId = context.resources.getIdentifier("text_miles_$i", "id", context.packageName)
                if (milesTextId != 0) {
                    if (miles > 0) {
                        views.setTextViewText(milesTextId, "$miles mi")
                        views.setViewVisibility(milesTextId, View.VISIBLE)
                    } else {
                        views.setViewVisibility(milesTextId, View.GONE)
                    }
                }
            }
            
            // Push update specifically to this ID
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        // When receiving ANY action, refresh ALL instances immediately
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, RunningWidgetProvider::class.java)
        val ids = manager.getAppWidgetIds(component)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        
        onUpdate(context, manager, ids, prefs)
    }
}
