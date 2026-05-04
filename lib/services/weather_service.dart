import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temp;
  final double apparentTemp; // Wind chill / Heat index
  final double rain;
  final double snow;
  final double wind;
  final int aqi;
  final String city;
  final String state;
  final DateTime? sunset;
  final List<HourlyForecast> forecast;

  WeatherData({
    required this.temp,
    required this.apparentTemp,
    required this.rain,
    required this.snow,
    required this.wind,
    required this.aqi,
    required this.city,
    required this.state,
    this.sunset,
    required this.forecast,
  });
}

class HourlyForecast {
  final DateTime time;
  final double temp;
  final double apparentTemp;
  final double rain;
  final double snow;
  final double wind;

  HourlyForecast({
    required this.time,
    required this.temp,
    required this.apparentTemp,
    required this.rain,
    required this.snow,
    required this.wind,
  });
}

class WeatherService {
  static Future<WeatherData?> getLocalWeather({String? manualCity}) async {
    try {
      double? lat;
      double? lon;
      String city = "Local";
      String state = "Area";

      if (manualCity != null && manualCity.isNotEmpty) {
        // GEOCODE MANUAL CITY
        final geoUrl = 'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(manualCity)}&format=json&limit=1';
        final geoResponse = await http.get(Uri.parse(geoUrl), headers: {'User-Agent': 'HybridLogApp'});
        if (geoResponse.statusCode == 200) {
          final geoData = jsonDecode(geoResponse.body);
          if (geoData.isNotEmpty) {
            lat = double.parse(geoData[0]['lat']);
            lon = double.parse(geoData[0]['lon']);
            final displayName = geoData[0]['display_name'] as String;
            final parts = displayName.split(',');
            city = parts[0].trim();
            state = parts.length > 2 ? parts[2].trim() : "";
          }
        }
      }

      if (lat == null || lon == null) {
        // FALLBACK TO IP
        final ipResponse = await http.get(Uri.parse('http://ip-api.com/json'));
        if (ipResponse.statusCode == 200) {
          final ipData = jsonDecode(ipResponse.body);
          lat = ipData['lat']?.toDouble();
          lon = ipData['lon']?.toDouble();
          city = ipData['city'] ?? "Local";
          state = ipData['region'] ?? "Area";
        }
      }

      if (lat == null || lon == null) return null;

      // GET WEATHER & SUNSET (Added apparent_temperature)
      final weatherUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&hourly=temperature_2m,apparent_temperature,rain,snowfall,wind_speed_10m&daily=sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch&forecast_days=2&timezone=auto';
      final aqiUrl = 'https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&hourly=us_aqi&forecast_days=2';

      final responses = await Future.wait([
        http.get(Uri.parse(weatherUrl)),
        http.get(Uri.parse(aqiUrl)),
      ]);

      if (responses[0].statusCode != 200 || responses[1].statusCode != 200) return null;

      final weatherJson = jsonDecode(responses[0].body);
      final aqiJson = jsonDecode(responses[1].body);

      final hourly = weatherJson['hourly'];
      final daily = weatherJson['daily'];
      final aqiHourly = aqiJson['hourly'];
      
      DateTime? sunsetDT;
      if (daily['sunset'] != null && daily['sunset'].isNotEmpty) {
        sunsetDT = DateTime.parse(daily['sunset'][0]);
      }

      final now = DateTime.now();
      int currentIndex = 0;
      for (int i = 0; i < hourly['time'].length; i++) {
        final time = DateTime.parse(hourly['time'][i]);
        if (time.hour == now.hour) {
          currentIndex = i;
          break;
        }
      }

      List<HourlyForecast> forecast = [];
      for (int i = currentIndex; i < currentIndex + 4 && i < hourly['time'].length; i++) {
        forecast.add(HourlyForecast(
          time: DateTime.parse(hourly['time'][i]),
          temp: hourly['temperature_2m'][i].toDouble(),
          apparentTemp: hourly['apparent_temperature'][i].toDouble(),
          rain: hourly['rain'][i].toDouble(),
          snow: hourly['snowfall'][i].toDouble(),
          wind: hourly['wind_speed_10m'][i].toDouble(),
        ));
      }

      return WeatherData(
        temp: hourly['temperature_2m'][currentIndex].toDouble(),
        apparentTemp: hourly['apparent_temperature'][currentIndex].toDouble(),
        rain: hourly['rain'][currentIndex].toDouble(),
        snow: hourly['snowfall'][currentIndex].toDouble(),
        wind: hourly['wind_speed_10m'][currentIndex].toDouble(),
        aqi: aqiHourly['us_aqi'][currentIndex].toInt(),
        city: city,
        state: state,
        sunset: sunsetDT,
        forecast: forecast,
      );
    } catch (e) {
      print('Weather Error: $e');
      return null;
    }
  }
}
