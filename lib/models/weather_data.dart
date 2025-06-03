class WeatherData {
  final double temperature;
  final double humidity;
  final String condition;
  final String location;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.condition,
    required this.location,
    required this.timestamp,
  });
}