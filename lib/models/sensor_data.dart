class SensorData {
  final double soilTemperature;
  final double soilMoisture;
  final double airTemperature;
  final double airHumidity;
  final double lightIntensity;
  final double ph;
  final DateTime timestamp;
  final String sensorId;
  final int batteryLevel;
  final String location;

  SensorData({
    required this.soilTemperature,
    required this.soilMoisture,
    required this.airTemperature,
    required this.airHumidity,
    required this.lightIntensity,
    required this.ph,
    required this.timestamp,
    required this.sensorId,
    this.batteryLevel = 100,
    this.location = 'greenhouse',
  });

  // Create from Firebase data
  factory SensorData.fromFirebase(Map<String, dynamic> data) {
    return SensorData(
      soilTemperature: (data['soil_temperature'] ?? 0.0).toDouble(),
      soilMoisture: (data['soil_moisture'] ?? 0.0).toDouble(),
      airTemperature: (data['air_temperature'] ?? 0.0).toDouble(),
      airHumidity: (data['air_humidity'] ?? 0.0).toDouble(),
      lightIntensity: (data['light_intensity'] ?? 0.0).toDouble(),
      ph: (data['ph'] ?? 7.0).toDouble(),
      timestamp: data['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp']) 
          : DateTime.now(),
      sensorId: data['sensor_id'] ?? 'default_sensor',
      batteryLevel: data['battery_level'] ?? 100,
      location: data['location'] ?? 'greenhouse',
    );
  }

  // Create from MQTT data
  factory SensorData.fromMqtt(Map<String, dynamic> data) {
    return SensorData(
      soilTemperature: (data['soil_temp'] ?? data['soilTemperature'] ?? 0.0).toDouble(),
      soilMoisture: (data['soil_moisture'] ?? data['soilMoisture'] ?? 0.0).toDouble(),
      airTemperature: (data['air_temp'] ?? data['airTemperature'] ?? 0.0).toDouble(),
      airHumidity: (data['air_humidity'] ?? data['airHumidity'] ?? 0.0).toDouble(),
      lightIntensity: (data['light'] ?? data['lightIntensity'] ?? 0.0).toDouble(),
      ph: (data['ph'] ?? 7.0).toDouble(),
      timestamp: data['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp']) 
          : DateTime.now(),
      sensorId: data['sensor_id'] ?? data['sensorId'] ?? 'default_sensor',
      batteryLevel: data['battery'] ?? data['batteryLevel'] ?? 100,
      location: data['location'] ?? 'greenhouse',
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'soil_temperature': soilTemperature,
      'soil_moisture': soilMoisture,
      'air_temperature': airTemperature,
      'air_humidity': airHumidity,
      'light_intensity': lightIntensity,
      'ph': ph,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'sensor_id': sensorId,
      'battery_level': batteryLevel,
      'location': location,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  // Convert to MQTT format
  Map<String, dynamic> toMqtt() {
    return {
      'soil_temp': soilTemperature,
      'soil_moisture': soilMoisture,
      'air_temp': airTemperature,
      'air_humidity': airHumidity,
      'light': lightIntensity,
      'ph': ph,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'sensor_id': sensorId,
      'battery': batteryLevel,
      'location': location,
    };
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'soilTemperature': soilTemperature,
      'soilMoisture': soilMoisture,
      'airTemperature': airTemperature,
      'airHumidity': airHumidity,
      'lightIntensity': lightIntensity,
      'ph': ph,
      'timestamp': timestamp.toIso8601String(),
      'sensorId': sensorId,
      'batteryLevel': batteryLevel,
      'location': location,
    };
  }

  // Create from JSON
  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      soilTemperature: (json['soilTemperature'] ?? 0.0).toDouble(),
      soilMoisture: (json['soilMoisture'] ?? 0.0).toDouble(),
      airTemperature: (json['airTemperature'] ?? 0.0).toDouble(),
      airHumidity: (json['airHumidity'] ?? 0.0).toDouble(),
      lightIntensity: (json['lightIntensity'] ?? 0.0).toDouble(),
      ph: (json['ph'] ?? 7.0).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      sensorId: json['sensorId'] ?? 'default_sensor',
      batteryLevel: json['batteryLevel'] ?? 100,
      location: json['location'] ?? 'greenhouse',
    );
  }

  // Copy with modifications
  SensorData copyWith({
    double? soilTemperature,
    double? soilMoisture,
    double? airTemperature,
    double? airHumidity,
    double? lightIntensity,
    double? ph,
    DateTime? timestamp,
    String? sensorId,
    int? batteryLevel,
    String? location,
  }) {
    return SensorData(
      soilTemperature: soilTemperature ?? this.soilTemperature,
      soilMoisture: soilMoisture ?? this.soilMoisture,
      airTemperature: airTemperature ?? this.airTemperature,
      airHumidity: airHumidity ?? this.airHumidity,
      lightIntensity: lightIntensity ?? this.lightIntensity,
      ph: ph ?? this.ph,
      timestamp: timestamp ?? this.timestamp,
      sensorId: sensorId ?? this.sensorId,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      location: location ?? this.location,
    );
  }

  // Check if sensor data is healthy
  bool get isHealthy {
    return batteryLevel > 20 &&
           soilTemperature >= -10 && soilTemperature <= 50 &&
           airTemperature >= -20 && airTemperature <= 60 &&
           soilMoisture >= 0 && soilMoisture <= 100 &&
           airHumidity >= 0 && airHumidity <= 100 &&
           ph >= 0 && ph <= 14;
  }

  // Check if watering is needed
  bool get needsWatering {
    return soilMoisture < 30.0; // Less than 30% moisture
  }

  // Get soil moisture status
  String get soilMoistureStatus {
    if (soilMoisture >= 70) return 'High';
    if (soilMoisture >= 50) return 'Good';
    if (soilMoisture >= 30) return 'Medium';
    if (soilMoisture >= 15) return 'Low';
    return 'Critical';
  }

  // Get temperature status
  String get temperatureStatus {
    if (soilTemperature >= 15 && soilTemperature <= 25) return 'Optimal';
    if (soilTemperature >= 10 && soilTemperature <= 30) return 'Good';
    if (soilTemperature < 10) return 'Too Cold';
    return 'Too Hot';
  }

  // Get light intensity status
  String get lightStatus {
    if (lightIntensity >= 800) return 'High';
    if (lightIntensity >= 400) return 'Good';
    if (lightIntensity >= 200) return 'Medium';
    if (lightIntensity >= 50) return 'Low';
    return 'Very Low';
  }

  @override
  String toString() {
    return 'SensorData{soilTemp: ${soilTemperature}°C, soilMoisture: ${soilMoisture}%, airTemp: ${airTemperature}°C, humidity: ${airHumidity}%, light: ${lightIntensity}lux, pH: $ph, battery: ${batteryLevel}%, time: $timestamp}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorData &&
        other.soilTemperature == soilTemperature &&
        other.soilMoisture == soilMoisture &&
        other.airTemperature == airTemperature &&
        other.airHumidity == airHumidity &&
        other.lightIntensity == lightIntensity &&
        other.ph == ph &&
        other.sensorId == sensorId &&
        other.batteryLevel == batteryLevel &&
        other.location == location;
  }

  @override
  int get hashCode {
    return Object.hash(
      soilTemperature,
      soilMoisture,
      airTemperature,
      airHumidity,
      lightIntensity,
      ph,
      sensorId,
      batteryLevel,
      location,
    );
  }
}