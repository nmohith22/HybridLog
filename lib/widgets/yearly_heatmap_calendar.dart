import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/fitness_schema.dart';
import 'lego_animations.dart';

enum CalendarView { year, month, week }

class YearlyHeatmapCalendar extends StatefulWidget {
  final DatabaseService dbService;
  final int selectedYear;
  final Function(int) onYearChanged;

  const YearlyHeatmapCalendar({
    super.key, 
    required this.dbService, 
    required this.selectedYear,
    required this.onYearChanged,
  });

  @override
  State<YearlyHeatmapCalendar> createState() => _YearlyHeatmapCalendarState();
}

class _YearlyHeatmapCalendarState extends State<YearlyHeatmapCalendar> {
  CalendarView _currentView = CalendarView.year;
  
  int? _selectedMonth;
  int? _selectedWeek;
  Map<DateTime, double> _weeklyData = {};
  DateTime? _weekStartDate;

  final List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
  }

  void _onMonthTapped(int index) {
    setState(() { _selectedMonth = index; _currentView = CalendarView.month; });
  }

  Future<void> _onWeekTapped(int index) async {
    _weekStartDate = DateTime(widget.selectedYear, _selectedMonth! + 1, 1).add(Duration(days: index * 7));
    while (_weekStartDate!.weekday != DateTime.monday) {
      _weekStartDate = _weekStartDate!.subtract(const Duration(days: 1));
    }
    final endDate = _weekStartDate!.add(const Duration(days: 6));
    final logs = await widget.dbService.getRunningLogsForDateRange(_weekStartDate!, endDate);
    
    _weeklyData.clear();
    for (var log in logs) { _weeklyData[log.date] = log.miles.toDouble(); }
    
    setState(() { _selectedWeek = index; _currentView = CalendarView.week; });
  }

  void _navigateBack() {
    setState(() {
      if (_currentView == CalendarView.week) _currentView = CalendarView.month;
      else if (_currentView == CalendarView.month) _currentView = CalendarView.year;
    });
  }

  String _getWeekRangeString(int monthIndex, int weekIndex) {
    DateTime firstOfMonth = DateTime(widget.selectedYear, monthIndex + 1, 1);
    int offset = (firstOfMonth.weekday - DateTime.monday) % 7;
    DateTime firstMonday = firstOfMonth.subtract(Duration(days: offset));
    DateTime startOfWeek = firstMonday.add(Duration(days: weekIndex * 7));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    return '${startOfWeek.month}/${startOfWeek.day} - ${endOfWeek.month}/${endOfWeek.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentView != CalendarView.year)
              TextButton.icon(
                onPressed: _navigateBack,
                icon: Icon(Icons.arrow_back_ios, size: 16, color: primaryColor),
                label: Text(_currentView == CalendarView.month ? 'Back to Year' : 'Back to Month', style: TextStyle(color: primaryColor)),
              )
            else
              Text('Yearly Overview', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        // We use a fixed height container here to ensure the nested lists render correctly
        SizedBox(
          height: 350,
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _buildCurrentView()),
        ),
      ],
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case CalendarView.year: return _buildYearView();
      case CalendarView.month: return _buildMonthView();
      case CalendarView.week: return _buildWeekView();
    }
  }

  Widget _buildYearView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1523) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return GridView.builder(
      key: const ValueKey('year_view'),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
      itemCount: 12,
      itemBuilder: (context, index) {
        return LegoPop(
          index: index,
          child: SpringyButton(
            onTap: () => _onMonthTapped(index),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
              ),
              child: Center(child: Text(_months[index], style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return ListView.builder(
      key: const ValueKey('month_view'),
      itemCount: 5, // Most months span 5 calendar weeks
      itemBuilder: (context, index) {
        final dateRange = _getWeekRangeString(_selectedMonth!, index);
        return LegoPop(
          index: index,
          child: SpringyButton(
            onTap: () => _onWeekTapped(index),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: cardColor, 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03)),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
              ),
              child: ListTile(
                title: Text(dateRange, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    return ListView.builder(
      key: const ValueKey('week_view'),
      itemCount: 7,
      itemBuilder: (context, index) {
        final currentDate = _weekStartDate!.add(Duration(days: index));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Row(
            children: [
              Expanded(child: Text(days[index], style: TextStyle(color: textColor))),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: _weeklyData[currentDate]?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    filled: true,
                    fillColor: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[200],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => widget.dbService.saveRunningBlock(currentDate, int.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 8),
              const Text('mi', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}
