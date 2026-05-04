import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../services/database_service.dart';
import '../models/fitness_schema.dart';
import '../widgets/yearly_heatmap_calendar.dart';
import '../widgets/running_block_graph.dart';
import '../widgets/weather_advice_widget.dart';
import '../services/weather_service.dart';
import '../widgets/lego_animations.dart';

class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key});

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  int _yearlyTotal = 0;
  int _selectedYear = DateTime.now().year;
  bool _isGraphInteracting = false;
  WeatherData? _weatherData;
  bool _isWeatherLoading = true;
  String? _manualCity;

  @override
  void initState() {
    super.initState();
    _calculateYearlyTotal();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    final data = await WeatherService.getLocalWeather(manualCity: _manualCity);
    if (mounted) {
      setState(() {
        _weatherData = data;
        _isWeatherLoading = false;
      });
    }
  }

  Future<void> _calculateYearlyTotal() async {
    final db = await DatabaseService().database;
    final startOfYear = DateTime(_selectedYear, 1, 1);
    final endOfYear = DateTime(_selectedYear, 12, 31, 23, 59, 59);
    
    final logs = await db.runningLogs.filter()
        .dateBetween(startOfYear, endOfYear)
        .findAll();
        
    if (mounted) {
      setState(() {
        _yearlyTotal = logs.fold(0, (sum, log) => sum + log.miles);
      });
    }
  }

  void _showCitySearch() {
    TextEditingController controller = TextEditingController(text: _manualCity);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1523),
        title: const Text("Enter City", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "e.g. New York, London",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              setState(() {
                _manualCity = controller.text.trim();
                _isWeatherLoading = true;
              });
              _loadWeather();
              Navigator.pop(context);
            },
            child: const Text("Search", style: TextStyle(color: Color(0xFFD93846), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showYearPicker() async {
    final db = await DatabaseService().database;
    final allLogs = await db.runningLogs.where().findAll();
    Set<int> availableYears = allLogs.map((l) => l.date.year).toSet();
    availableYears.add(DateTime.now().year); 
    
    List<int> sortedYears = availableYears.toList()..sort((a, b) => b.compareTo(a));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1523),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Year", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: sortedYears.length,
                  itemBuilder: (context, index) {
                    final year = sortedYears[index];
                    final isSelected = year == _selectedYear;
                    return ListTile(
                      title: Text('$year', textAlign: TextAlign.center, style: TextStyle(color: isSelected ? const Color(0xFFD93846) : Colors.white, fontSize: 20, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      onTap: () {
                        setState(() {
                          _selectedYear = year;
                        });
                        _calculateYearlyTotal();
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return StreamBuilder<void>(
      stream: DatabaseService().watchRunningLogs(),
      builder: (context, _) {
        _calculateYearlyTotal(); // Refresh total when stream fires
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: _isGraphInteracting ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Running Log',
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      ),
                      GestureDetector(
                        onTap: _showYearPicker,
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$_selectedYear TOTAL', style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 12),
                              ],
                            ),
                            Text('$_yearlyTotal mi', style: TextStyle(color: primaryColor, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  LegoPop(
                    index: 0,
                    child: RunningBlockGraph(
                      dbService: DatabaseService(),
                      onChanged: () => _calculateYearlyTotal(),
                      onInteractionChanged: (isInteracting) {
                        setState(() => _isGraphInteracting = isInteracting);
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  LegoPop(
                    index: 1,
                    child: WeatherAdviceWidget(
                      data: _weatherData,
                      isLoading: _isWeatherLoading,
                      onRetry: _loadWeather,
                      onSearch: _showCitySearch,
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  LegoPop(
                    index: 2,
                    child: YearlyHeatmapCalendar(
                      dbService: DatabaseService(),
                      selectedYear: _selectedYear,
                      onYearChanged: (year) {
                        setState(() {
                          _selectedYear = year;
                        });
                        _calculateYearlyTotal();
                      },
                    ),
                  ),
                  const SizedBox(height: 40), 
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}
