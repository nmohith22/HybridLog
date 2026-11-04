import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/weather_service.dart';

class WeatherAdviceWidget extends StatefulWidget {
  const WeatherAdviceWidget({super.key});

  @override
  State<WeatherAdviceWidget> createState() => _WeatherAdviceWidgetState();
}

class _WeatherAdviceWidgetState extends State<WeatherAdviceWidget> {
  static const _cityPreferenceKey = 'running_weather_city';
  final _cityController = TextEditingController();
  RunningWeather? _weather;
  String? _error;
  bool _loading = false;
  bool _editingCity = true;
  bool _hasSavedCity = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCity();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCity = prefs.getString(_cityPreferenceKey);
      if (mounted && savedCity != null && savedCity.trim().isNotEmpty) {
        setState(() {
          _cityController.text = savedCity;
          _editingCity = false;
          _hasSavedCity = true;
        });
        await _loadWeather(cityOverride: savedCity);
      }
    } catch (_) {
      // Weather remains usable if a local preference cannot be read.
    }
  }

  Future<void> _loadWeather({String? cityOverride}) async {
    if (_loading) return;
    final city = (cityOverride ?? _cityController.text).trim();
    if (city.length < 2 || city.length > 100) {
      setState(() => _error = 'Enter a city or town name (2–100 characters).');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _weather = null;
    });
    try {
      final weather = await WeatherService.forCity(city);
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _editingCity = false;
        _hasSavedCity = true;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cityPreferenceKey, city);
      } catch (_) {
        // Keep the current lookup even if saving the preferred city fails.
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Weather could not be loaded. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weather = _weather;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = theme.colorScheme.onSurface.withOpacity(0.7);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withOpacity(0.08)),
        boxShadow: theme.brightness == Brightness.dark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  weather?.location ?? 'RUN CONDITIONS',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (_hasSavedCity && !_editingCity)
                IconButton(
                  tooltip: 'Change city',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading
                      ? null
                      : () => setState(() => _editingCity = true),
                  icon: Icon(Icons.edit_location_alt_outlined,
                      color: subTextColor, size: 20),
                ),
              if (_loading)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editingCity) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    enabled: !_loading,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _loadWeather(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: const InputDecoration(
                      labelText: 'City or town',
                      hintText: 'Madison, WI',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: FilledButton(
                    onPressed: _loading ? null : _loadWeather,
                    child: Text(_loading ? 'Loading' : 'Get weather'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'When you request weather, your city and coordinates go to Open-Meteo. No device location is used.',
              style: TextStyle(color: subTextColor, fontSize: 11),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
            if (!_editingCity)
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _loadWeather(cityOverride: _cityController.text),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
              ),
          ],
          if (weather != null) ...[
            const SizedBox(height: 16),
            Divider(color: textColor.withOpacity(0.1)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_weatherIcon(weather.weatherCode),
                    color: theme.colorScheme.primary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(weather.conditions,
                          style: TextStyle(color: subTextColor, fontSize: 13)),
                    ],
                  ),
                ),
                Text(
                  '${weather.temperatureF.round()}°F',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 30,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _weatherDetail(
                    Icons.thermostat,
                    'Feels ${weather.feelsLikeF.round()}°F',
                    textColor,
                    subTextColor),
                _weatherDetail(Icons.air, '${weather.windMph.round()} mph wind',
                    textColor, subTextColor),
                _weatherDetail(
                    Icons.water_drop_outlined,
                    '${weather.precipitationIn.toStringAsFixed(2)} in precip.',
                    textColor,
                    subTextColor),
                if (weather.sunrise != null)
                  _weatherDetail(
                      Icons.wb_twilight,
                      'Sunrise ${DateFormat.jm().format(weather.sunrise!)}',
                      textColor,
                      subTextColor),
                if (weather.sunset != null)
                  _weatherDetail(
                      Icons.nightlight_outlined,
                      'Sunset ${DateFormat.jm().format(weather.sunset!)}',
                      textColor,
                      subTextColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(weather.runningAdvice,
                style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              'Updated ${DateFormat.jm().format(weather.fetchedAt)} · Weather by Open-Meteo · Location data by GeoNames',
              style: TextStyle(color: subTextColor, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weatherDetail(
      IconData icon, String label, Color textColor, Color subTextColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: subTextColor),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: textColor, fontSize: 12)),
      ],
    );
  }

  IconData _weatherIcon(int code) => switch (code) {
        0 || 1 => Icons.wb_sunny_outlined,
        2 || 3 => Icons.cloud_outlined,
        45 || 48 => Icons.cloud_outlined,
        51 ||
        53 ||
        55 ||
        56 ||
        57 ||
        61 ||
        63 ||
        65 ||
        66 ||
        67 ||
        80 ||
        81 ||
        82 =>
          Icons.grain,
        71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
        95 || 96 || 99 => Icons.thunderstorm,
        _ => Icons.cloud_outlined,
      };
}
