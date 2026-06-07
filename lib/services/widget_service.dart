import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'database_service.dart';
import '../models/fitness_schema.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:isar/isar.dart';

class WidgetService {
  static const String _androidWidgetName = 'RunningWidgetProvider';

  static Future<void> updateRunningWidget() async {
    if (kIsWeb) return;
    try {
      final db = await DatabaseService().database;
      
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
      
      final List<RunningLog> logs = await db.runningLogs.filter().dateBetween(startOfWeek, endOfWeek).findAll();
      
      Map<int, int> weeklyBlocks = {for (var i = 0; i < 7; i++) i: 0};
      int total = 0;
      for (var log in logs) {
        int dayIndex = log.date.difference(startOfWeek).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          int miles = log.miles; 
          weeklyBlocks[dayIndex] = miles;
          total += miles;
        }
      }

      // SAVE RAW DATA TO HOME WIDGET
      debugPrint('Pushing to Widget: Total=$total, Weekly=$weeklyBlocks');
      await HomeWidget.saveWidgetData<int>('total_miles', total);
      for (int i = 0; i < 7; i++) {
        await HomeWidget.saveWidgetData<int>('day_${i}_miles', weeklyBlocks[i] ?? 0);
      }

      // Moderate delay to ensure SharedPreferences has physically flushed to disk
      await Future.delayed(const Duration(milliseconds: 300));

      // TRIGGER NATIVE UPDATE
      final res = await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: 'com.example.workout_app.RunningWidgetProvider',
      );
      debugPrint('Widget Update Result: $res');
    } catch (e) {
      debugPrint('Widget Update Error: $e');
    }
  }

  // Handle widget interactions
  static Future<void> handleWidgetAction(Uri? uri) async {
    debugPrint('Widget Action Received: $uri');
    if (uri == null) return;
    
    try {
      final db = await DatabaseService().database;
      final dayIndexString = uri.queryParameters['dayIndex'];
      debugPrint('Day Index String: $dayIndexString');
      if (dayIndexString == null) return;
      final dayIndex = int.tryParse(dayIndexString);
      if (dayIndex == null) return;

      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final targetDate = startOfWeek.add(Duration(days: dayIndex));

      int change = 0;
      if (uri.host == 'increment_day') change = 1;
      else if (uri.host == 'decrement_day') change = -1;

      debugPrint('Action: ${uri.host}, Change: $change, Date: $targetDate');

      if (change != 0) {
        await DatabaseService().saveRunningBlock(targetDate, change);
        await updateRunningWidget();
        debugPrint('Widget Updated Successfully');
      }
    } catch (e) {
      debugPrint('Widget Action Error: $e');
      rethrow; // Pass to main wrapper
    }
  }
}
