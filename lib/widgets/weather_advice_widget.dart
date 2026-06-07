import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import 'dart:math';
import 'lego_animations.dart';

class WeatherAdviceWidget extends StatelessWidget {
  final WeatherData? data;
  final bool isLoading;
  final VoidCallback? onRetry;
  final VoidCallback? onSearch;

  const WeatherAdviceWidget({super.key, required this.data, required this.isLoading, this.onRetry, this.onSearch});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = Theme.of(context).colorScheme.secondary;
    final borderColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);

    if (isLoading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }

    if (data == null) {
      return SpringyButton(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
          child: Column(children: [
            Icon(Icons.location_off, color: secondaryTextColor, size: 28),
            const SizedBox(height: 8),
            Center(child: Text("Tap to enable location advice", style: TextStyle(color: secondaryTextColor, fontWeight: FontWeight.w600))),
            if (onSearch != null) TextButton(onPressed: onSearch, child: Text("Or search manually", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12))),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: borderColor),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: SpringyButton(
                onTap: onSearch,
                child: Row(
                  children: [
                    Flexible(child: Text("OUTDOOR ADVICE - ${data!.city.toUpperCase()}, ${data!.state.toUpperCase()}", style: TextStyle(color: secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    Icon(Icons.search, color: secondaryTextColor, size: 10),
                  ],
                ),
              )),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${data!.temp.toInt()}°F", style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Feels ${data!.apparentTemp.toInt()}°", style: TextStyle(color: secondaryTextColor, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildOverallAdvice(textColor),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.air, color: Colors.blueGrey, size: 14),
              const SizedBox(width: 6),
              Text("${data!.wind.toInt()} mph wind", style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(width: 12),
              const Icon(Icons.wb_twilight, color: Colors.orangeAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                data!.sunset != null 
                  ? "Sunset at ${data!.sunset!.hour > 12 ? data!.sunset!.hour - 12 : (data!.sunset!.hour == 0 ? 12 : data!.sunset!.hour)}:${data!.sunset!.minute.toString().padLeft(2, '0')} ${data!.sunset!.hour >= 12 ? 'PM' : 'AM'}" 
                  : "Sunset N/A", 
                style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500)
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
            children: data!.forecast.take(4).map((f) => _buildHourlyItem(f, textColor, secondaryTextColor)).toList()
          ),
          ],
          ),
          );
          }

  Widget _buildOverallAdvice(Color textColor) {
    final Map<String, dynamic> result = _getAdviceAndIcon(data!);
    return Row(
      children: [
        Icon(result['icon'], color: result['color'], size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text(result['text'], style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600))),
      ],
    );
  }

  Map<String, dynamic> _getAdviceAndIcon(WeatherData data) {
    // Rotate every 2 hours
    final timeSeed = (DateTime.now().hour ~/ 2) + (DateTime.now().day * 12);
    Random r = Random(timeSeed); 
    
    final temp = data.apparentTemp;
    final wind = data.wind;
    final rain = data.rain;
    final snow = data.snow;
    final aqi = data.aqi;

    // NIGHT CHECK
    final now = DateTime.now();
    bool isNight = false;
    if (data.sunset != null) {
      // If now is after sunset, it's night.
      isNight = now.isAfter(data.sunset!);
    }

    // 0. ABSOLUTE HARD NO: ANY PRECIPITATION
    if (rain > 0 || snow > 0) {
      if (snow > 0) return {'text': _pick(snowMessages, r), 'icon': Icons.ac_unit, 'color': Colors.white};
      return {'text': _pick(rainMessages, r), 'icon': Icons.umbrella, 'color': Colors.blueGrey};
    }

    // 0.1 NIGHT ADVICE
    if (isNight) {
      final nightMessages = [
        "Sun's down. Maybe hit the treadmill or just recover.",
        "Night run? Make sure you're visible and safe.",
        "After hours. Weights only tonight?",
        "Moon's out. Perfect for a quiet indoor session.",
        "Late start. Stay in the light, stay safe."
      ];
      return {'text': _pick(nightMessages, r), 'icon': Icons.nightlight_round, 'color': Colors.amberAccent};
    }

    // SCORING (Lower is better)
    double penalty = 0;
    
    // Wind Penalty
    if (wind > 18) penalty += 50;
    else if (wind > 10) penalty += 20;
    else if (wind > 5) penalty += 5;
    
    // Precip Penalty
    if (snow > 0) penalty += 40;
    if (rain > 0.1) penalty += 30;
    else if (rain > 0.01) penalty += 10;
    
    // Temp Penalty
    if (temp < 0) penalty += 60;
    else if (temp < 32) penalty += 25;
    else if (temp < 45) penalty += 10;
    else if (temp > 95) penalty += 40;
    else if (temp > 85) penalty += 20;
    
    // AQI Penalty
    if (aqi > 100) penalty += 100;

    // COMBINATION LOGIC
    
    // 1. DANGEROUS / HARD NO
    if (penalty >= 60 || aqi > 100) {
      if (aqi > 100) return {'text': _pick(aqiMessages, r), 'icon': Icons.warning_amber_rounded, 'color': Colors.yellowAccent};
      if (snow > 0 && wind > 10) return {'text': "Blizzard conditions. Don't even think about it.", 'icon': Icons.ac_unit, 'color': Colors.white};
      if (rain > 0.05 && wind > 15) return {'text': "Stormy and gale-force winds. Absolute treadmill day.", 'icon': Icons.thunderstorm, 'color': Colors.blueGrey};
      if (temp < 20) return {'text': "Dangerously cold. Respect the lungs, stay inside.", 'icon': Icons.dangerous, 'color': Colors.redAccent};
      return {'text': "Hostile conditions. Indoor workout highly recommended.", 'icon': Icons.home, 'color': Colors.orangeAccent};
    }

    // 2. COMPROMISED (High wind or Light rain but okay temp)
    if (penalty >= 20) {
      if (wind > 12 && temp > 45 && temp < 75) return {'text': "Great temp, but the wind will fight your pace. Gym?", 'icon': Icons.air, 'color': Colors.lightBlueAccent};
      if (rain > 0 && temp > 55) return {'text': "Light rain, but warm enough. Embrace the grind?", 'icon': Icons.umbrella, 'color': Colors.blueGrey};
      if (temp < 40 && wind < 5) return {'text': "Freezing but dead calm. Perfect for a focused tempo run.", 'icon': Icons.check_circle, 'color': Colors.greenAccent};
      return {'text': "Sub-optimal. Dress right or hit the treadmill.", 'icon': Icons.info_outline, 'color': Colors.amberAccent};
    }

    // 3. IDEAL
    if (wind <= 3 && temp >= 48 && temp <= 72 && rain == 0 && snow == 0) {
      return {'text': _pick(idealWindMessages, r), 'icon': Icons.auto_awesome, 'color': Colors.amberAccent};
    }

    // 4. PERFECT (Default good)
    return {'text': _pick(perfectMessages, r), 'icon': Icons.wb_sunny, 'color': Colors.orangeAccent};
  }

  String _pick(List<String> list, Random r) => list[r.nextInt(list.length)];

  Widget _buildHourlyItem(HourlyForecast f, Color textColor, Color secondaryTextColor) {
    IconData icon = Icons.wb_sunny_outlined;
    if (f.rain > 0.01) icon = Icons.cloudy_snowing;
    else if (f.apparentTemp < 40) icon = Icons.ac_unit;
    else if (f.wind > 15) icon = Icons.air;

    return Column(children: [
      Text("${f.time.hour % 12 == 0 ? 12 : f.time.hour % 12}${f.time.hour >= 12 ? 'pm' : 'am'}", style: TextStyle(color: secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Icon(icon, color: secondaryTextColor, size: 20),
      const SizedBox(height: 4),
      Text("${f.temp.toInt()}°", style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
    ]);
  }

  // --- MASSIVE MESSAGE DATABASE ---
  static const extremeWindMessages = [
    "20+ mph wind? You're running in place. Treadmill.", "Basically a hurricane for runners. Gym day.",
    "Don't fight the gale. Stay inside.", "Extreme wind detected. High resistance, low reward.",
    "The wind will win today. Workout indoors.", "Safety alert: Wind speeds are too high for a safe run."
  ];

  static const highWindMessages = [
    "Strong winds today. Horrible for pacing.", "Fighting the wind is a different kind of cardio. Gym?",
    "Windy out there. Expect a struggle on the return leg.", "Hold onto your hat! High resistance today.",
    "Windy conditions. Maybe a weight-heavy day instead?", "Breezy is nice, this is just annoying. Treadmill time?"
  ];

  static const idealWindMessages = [
    "Zero wind. Absolute perfection for a run.", "Dead calm out there. Ideal Hybrid conditions.",
    "Under 3mph wind—pacing will be effortless.", "The air is still. Time for a PR.",
    "No wind resistance today. Pure speed incoming.", "Perfect stillness. Get those miles in."
  ];

  static const subZeroMessages = [
    "I don't even have to tell you. Get on the treadmill.", "Absolute zero vibes. No way.", "It's negative out there. Stay alive, stay inside.",
    "Your lungs will freeze. Treadmill day.", "Don't be a hero. It's dangerous cold.", "Just get on the treadmill. Seriously.", 
    "Frostbite speedrun? No. Stay inside.", "Even the polar bears are inside today.", "Workout at home. It's too cold for logic.",
    "The air is literally sharp. Don't do it.", "Hibernation mode engaged. Indoor miles only.", "The treadmill is your only friend today."
  ];

  static const freezingMessages = [
    "Freezing! Maybe stick to the treadmill.", "Hard pass on the outdoors today.", "Ice on the path. Safety first.",
    "Your car won't even start. Why would you run?", "It's a winter wonderland. Stay in the heat.", "Breath looks like smoke. Indoor cardio.",
    "Lungs won't thank you for this cold.", "Save the outdoor miles for spring.", "Too cold for a good tempo. Hit the gym.",
    "Zero motivation for this temp. Stay warm.", "Your sweat will turn to ice. Inside.", "Winter's grip is real today. Indoor work."
  ];

  static const jacketMessages = [
    "Good to run, but layer up with jackets!", "Tights and a windbreaker required.", "Don't forget the beanie and gloves.",
    "Crisp air! Grab a warm outer layer.", "Perfect for high-intensity, with a jacket.", "Protect the core. Double layer today.",
    "Chilly miles ahead. Zip up!", "Gloves are a must-have right now.", "Stay warm until the heart rate climbs.",
    "Winter running gear enabled. Layer up.", "Don't let the wind bite. Jacket time.", "Thermal base layer highly recommended."
  ];

  static const longSleeveMessages = [
    "Just wear a longsleeve!", "Light coverage is all you need.", "Perfect temperature for a tech tee.",
    "Fresh air, light layers. Let's go.", "No jacket needed once you're moving.", "Long sleeves and shorts weather.",
    "Ideal training temp. Don't overdress.", "A light quarter-zip is perfect.", "Prime hybrid weather. Long sleeves on.",
    "Keep the chill off with one solid layer.", "Snap a photo, it's longsleeve season.", "The sweet spot of running temps."
  ];

  static const perfectMessages = [
    "Perfect weather, bring sunglasses!", "Shorts and a tee. Peak performance.", "Sun's out, Hybrid miles out.",
    "Hydration and shades. Let's get it.", "Beautiful day for a recovery run.", "Sunglasses required. Sky is clear.",
    "The road is calling. Minimal layers.", "Tank top weather? Almost. Shades on.", "Don't forget the SPF. Perfect run.",
    "Pure hybrid bliss today. Get outside.", "Shades on, pace up. It's gorgeous.", "This is what we train for. Sunshine."
  ];

  static const rainMessages = [
    "Raining outside. Hard pass.", "Unless you're a fish, stay inside.", "Soggy shoes are the worst. Gym day.",
    "Save your joints, don't slip in the rain.", "Indoor miles > Wet miles.", "Rain check? Definitely. Hit the weights.",
    "Waterlogged path. Not worth the risk.", "The treadmill is dry. The road is not.", "Stormy vibes. Stay in the power rack.",
    "Don't get sick for a run. Indoor work."
  ];

  static const snowMessages = [
    "Snowing! Watch your step.", "Blizzard warnings? Stay home.", "Snowy miles are for the bold, but risky.",
    "Ice under that snow. Be careful.", "Winter magic, but indoor logic.", "The world is white. The gym is warm.",
    "Traction will be an issue. Treadmill.", "Don't slip on the hybrid grind. Inside.", "Fresh powder is for skiing, not running."
  ];

  static const aqiMessages = [
    "Poor air quality. Be careful.", "Lungs need clean air. Stay inside.", "AQI is high. Don't risk the respiratory hit.",
    "Smoky or hazy? Weights only today.", "Bad air day. Keep the intensity indoor.", "Don't breathe the junk. Stay home.",
    "Safety override: High AQI detected.", "Indoor cardio is the healthy choice today."
  ];
}
