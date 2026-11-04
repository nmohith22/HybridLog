import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/widget_service.dart';
import 'lego_animations.dart';

int runningDayIndexAt(double localX, double rowWidth) {
  if (!localX.isFinite || !rowWidth.isFinite || rowWidth <= 0) return 0;
  return (localX / rowWidth * 7).floor().clamp(0, 6).toInt();
}

class RunningBlockGraph extends StatefulWidget {
  final DatabaseService dbService;
  final VoidCallback? onChanged;
  final Function(bool)? onInteractionChanged;

  const RunningBlockGraph({super.key, required this.dbService, this.onChanged, this.onInteractionChanged});

  @override
  State<RunningBlockGraph> createState() => _RunningBlockGraphState();
}

class _RunningBlockGraphState extends State<RunningBlockGraph> {
  late PageController _pageController;
  int _currentWeekOffset = 1000; 
  Map<int, int> _weeklyBlocks = {for (var i = 0; i < 7; i++) i: 0};
  int _totalMiles = 0;
  double _dragAccumulator = 0.0;
  int _dragDayIndex = 0;
  int _pendingLocalChanges = 0;
  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentWeekOffset);
    _loadWeekData(0); 
    
    // Watch database for real-time state sync without full widget rebuilds
    _logSubscription = DatabaseService().watchRunningLogs().listen((_) {
      if (_pendingLocalChanges == 0) _loadWeekData(_currentWeekOffset - 1000);
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RunningBlockGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dbService != oldWidget.dbService) {
      _loadWeekData(_currentWeekOffset - 1000);
    }
  }

  DateTime _getStartOfWeek(int offsetFromCurrent) {
    DateTime now = DateTime.now();
    DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day).add(Duration(days: offsetFromCurrent * 7));
  }

  Future<void> _loadWeekData(int weekOffset) async {
    final startOfWeek = _getStartOfWeek(weekOffset);
    final logs = await widget.dbService.getRunningLogsForDateRange(
      startOfWeek, 
      startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59))
    );

    final newBlocks = {for (var i = 0; i < 7; i++) i: 0};
    int total = 0;
    for (var log in logs) {
      int dayIndex = log.date.difference(startOfWeek).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        newBlocks[dayIndex] = log.miles;
        total += log.miles;
      }
    }

    if (mounted && _currentWeekOffset - 1000 == weekOffset) {
      setState(() {
        _weeklyBlocks = newBlocks;
        _totalMiles = total;
      });
    }
  }

  void _startVerticalDrag(DragStartDetails details, double rowWidth) {
    _dragAccumulator = 0;
    _dragDayIndex = runningDayIndexAt(details.localPosition.dx, rowWidth);
    widget.onInteractionChanged?.call(true);
  }

  void _updateVerticalDrag(DragUpdateDetails details, int weekOffset) {
    _dragAccumulator -= details.delta.dy;
    while (_dragAccumulator >= 20) {
      _dragAccumulator -= 20;
      _queueBlockChange(_dragDayIndex, weekOffset, 1);
    }
    while (_dragAccumulator <= -20) {
      _dragAccumulator += 20;
      _queueBlockChange(_dragDayIndex, weekOffset, -1);
    }
  }

  void _queueBlockChange(int dayIndex, int weekOffset, int delta) {
    final current = _weeklyBlocks[dayIndex] ?? 0;
    final updated = (current + delta).clamp(0, 20).toInt();
    final actualDelta = updated - current;
    if (actualDelta == 0) {
      _dragAccumulator = 0;
      return;
    }
    setState(() {
      _weeklyBlocks[dayIndex] = updated;
      _totalMiles += actualDelta;
    });
    _pendingLocalChanges++;
    final targetDate = _getStartOfWeek(weekOffset).add(Duration(days: dayIndex));
    _saveQueue = _saveQueue.then((_) async {
      await widget.dbService.saveRunningBlock(targetDate, actualDelta);
      await WidgetService.updateRunningWidget();
      widget.onChanged?.call();
    }).catchError((Object error) {
      debugPrint('Could not save running block: $error');
    }).whenComplete(() {
      _pendingLocalChanges--;
      if (mounted && _pendingLocalChanges == 0) {
        _loadWeekData(_currentWeekOffset - 1000);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final containerColor = Theme.of(context).colorScheme.surface;

    // LegoPop only on the entire container for entrance
    return LegoPop(
      child: Container(
        height: 280, 
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: containerColor, 
          borderRadius: BorderRadius.circular(24), 
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08)),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (pageIndex) {
            setState(() => _currentWeekOffset = pageIndex);
            _loadWeekData(pageIndex - 1000);
          },
          itemBuilder: (context, pageIndex) {
            int offset = pageIndex - 1000;
            final startOfWeek = _getStartOfWeek(offset);
            final endOfWeek = startOfWeek.add(const Duration(days: 6));
            final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
            
            return AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                double pageOffset = 0.0;
                if (_pageController.position.haveDimensions) {
                  pageOffset = (_pageController.page! - pageIndex).abs();
                }
                final opacity = (1.0 - pageOffset).clamp(0.0, 1.0);
                
                return Opacity(
                  opacity: opacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${startOfWeek.month}/${startOfWeek.day} - ${endOfWeek.month}/${endOfWeek.day}', style: TextStyle(color: isDark ? Colors.grey[700] : Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w500)),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(begin: const Offset(0, .2), end: Offset.zero).animate(animation),
                                child: child,
                              ),
                            ),
                            child: Text('$_totalMiles mi', key: ValueKey(_totalMiles), style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: (details) => _startVerticalDrag(details, constraints.maxWidth),
                            onVerticalDragUpdate: (details) => _updateVerticalDrag(details, offset),
                            onVerticalDragEnd: (_) { _dragAccumulator = 0; widget.onInteractionChanged?.call(false); },
                            onVerticalDragCancel: () { _dragAccumulator = 0; widget.onInteractionChanged?.call(false); },
                            onTapUp: (details) => _queueBlockChange(runningDayIndexAt(details.localPosition.dx, constraints.maxWidth), offset, 1),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(7, (dayIndex) {
                                final miles = _weeklyBlocks[dayIndex] ?? 0;
                                return Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          alignment: Alignment.bottomCenter,
                                          color: Colors.transparent,
                                          child: AnimatedSize(
                                            duration: const Duration(milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.bottomCenter,
                                            child: Column(
                                              key: ValueKey('blocks-$miles'),
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: List.generate(miles, (blockIndex) => TweenAnimationBuilder<double>(
                                                key: ValueKey('block-$blockIndex'),
                                                tween: Tween(begin: 0, end: 1),
                                                duration: const Duration(milliseconds: 220),
                                                curve: Curves.easeOutBack,
                                                builder: (context, value, child) => Opacity(
                                                  opacity: value.clamp(0, 1),
                                                  child: Transform.scale(scale: value.clamp(0, 1), alignment: Alignment.bottomCenter, child: child),
                                                ),
                                                child: Container(
                                                  width: 24, height: 8, margin: const EdgeInsets.only(top: 2),
                                                  decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(2)),
                                                ),
                                              )),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(days[dayIndex], style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 9, fontWeight: FontWeight.bold)),
                                      Text('$miles', style: TextStyle(color: isDark ? Colors.grey[800] : Colors.grey[300], fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
