import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RunningWeather {
  final String city;
  final String? region;
  final String country;
  final double temperatureF;
  final double feelsLikeF;
  final double windMph;
  final double precipitationIn;
  final int weatherCode;
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime fetchedAt;

  const RunningWeather({
    required this.city,
    required this.region,
    required this.country,
    required this.temperatureF,
    required this.feelsLikeF,
    required this.windMph,
    required this.precipitationIn,
    required this.weatherCode,
    required this.sunrise,
    required this.sunset,
    required this.fetchedAt,
  });

  String get location => [city, region, country]
      .where((part) => part != null && part.isNotEmpty)
      .join(', ');

  String get conditions => switch (weatherCode) {
        0 => 'Clear sky',
        1 => 'Mostly clear',
        2 => 'Partly cloudy',
        3 => 'Overcast',
        45 || 48 => 'Foggy',
        51 || 53 || 55 || 56 || 57 => 'Drizzle',
        61 || 63 || 65 || 66 || 67 => 'Rain',
        71 || 73 || 75 || 77 => 'Snow',
        80 || 81 || 82 => 'Rain showers',
        85 || 86 => 'Snow showers',
        95 || 96 || 99 => 'Thunderstorms',
        _ => 'Current conditions',
      };

  String get runningAdvice {
    if (weatherCode >= 95 && weatherCode <= 99) {
      return 'Thunderstorms nearby. Consider waiting for conditions to improve.';
    }
    if (precipitationIn >= 0.04 || (weatherCode >= 51 && weatherCode <= 86)) {
      return 'Wet conditions. Take care on slippery paths and roads.';
    }
    if (feelsLikeF >= 90) {
      return 'Hot conditions. Consider an easier pace and bring water.';
    }
    if (feelsLikeF <= 32) {
      return 'Freezing conditions. Dress warmly and watch for slick surfaces.';
    }
    if (windMph >= 20) {
      return 'Windy conditions may make exposed routes feel tougher.';
    }
    return 'Conditions look favorable for a run.';
  }
}

class WeatherService {
  static const _timeout = Duration(seconds: 12);

  static Future<RunningWeather> forCity(String input) async {
    final cityQuery = input.trim();
    if (cityQuery.length < 2 || cityQuery.length > 100) {
      throw const FormatException(
          'Enter a city or town name (2–100 characters).');
    }

    final geocoding = await _getJson(Uri.https(
      'geocoding-api.open-meteo.com',
      '/v1/search',
      {'name': cityQuery, 'count': '1', 'language': 'en', 'format': 'json'},
    ));
    final results = geocoding['results'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      throw const FormatException(
          'I could not find that place. Try adding a state or country.');
    }
    final place = Map<String, dynamic>.from(results.first as Map);
    final latitude = _number(place['latitude'], 'latitude');
    final longitude = _number(place['longitude'], 'longitude');
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException(
          'The selected location has invalid coordinates.');
    }

    final forecast = await _getJson(Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current':
            'temperature_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
        'daily': 'sunrise,sunset',
        'temperature_unit': 'fahrenheit',
        'wind_speed_unit': 'mph',
        'precipitation_unit': 'inch',
        'timezone': 'auto',
      },
    ));
    final current = forecast['current'];
    final daily = forecast['daily'];
    if (current is! Map) {
      throw const FormatException(
          'Weather conditions are unavailable right now.');
    }
    final sunrise = _firstDateTime(daily, 'sunrise');
    final sunset = _firstDateTime(daily, 'sunset');

    return RunningWeather(
      city: _string(place['name'], 'place name'),
      region: place['admin1'] is String ? place['admin1'] as String : null,
      country: place['country'] is String ? place['country'] as String : '',
      temperatureF: _number(current['temperature_2m'], 'temperature'),
      feelsLikeF:
          _number(current['apparent_temperature'], 'feels-like temperature'),
      windMph: _number(current['wind_speed_10m'], 'wind speed'),
      precipitationIn: _number(current['precipitation'], 'precipitation'),
      weatherCode: _integer(current['weather_code'], 'weather code'),
      sunrise: sunrise,
      sunset: sunset,
      fetchedAt: DateTime.now(),
    );
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException(
            'Weather service is unavailable right now. Please try again.');
      }
      final body =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException(
            'Weather service returned an invalid response.');
      }
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      throw const FormatException(
          'Weather lookup timed out. Check your connection and try again.');
    } on IOException {
      throw const FormatException(
          'Could not reach the weather service. Check your connection.');
    } finally {
      client.close(force: true);
    }
  }

  static double _number(Object? value, String field) {
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Weather data is missing $field.');
  }

  static int _integer(Object? value, String field) {
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw FormatException('Weather data is missing $field.');
  }

  static String _string(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw FormatException('Weather data is missing $field.');
  }

  static DateTime? _firstDateTime(Object? daily, String field) {
    if (daily is! Map) return null;
    final values = daily[field];
    if (values is! List || values.isEmpty || values.first is! String) {
      return null;
    }
    return DateTime.tryParse(values.first as String);
  }
}
