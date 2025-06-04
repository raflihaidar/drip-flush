class SensorData {
  final Sensor sensor;

  SensorData({
    required this.sensor,
  });

  // Create from Firebase data - FIXED TYPE CASTING
  factory SensorData.fromFirebase(Map<String, dynamic> data) {
    print("📊 SensorData - Full data received: $data");
    print("📊 SensorData - Data type: ${data.runtimeType}");
    print("📊 SensorData - Sensor data: ${data['sensor']}");
    print("📊 SensorData - Sensor data type: ${data['sensor'].runtimeType}");
    
    try {
      final rawSensorData = data['sensor'];
      if (rawSensorData == null) {
        print("❌ SensorData - No 'sensor' key found, using default");
        return SensorData(sensor: Sensor(soilSensor: SoilSensor(value: 0.0)));
      }
      
      // Safe conversion from Object? to Map<String, dynamic>
      Map<String, dynamic> sensorData;
      if (rawSensorData is Map<String, dynamic>) {
        sensorData = rawSensorData;
      } else if (rawSensorData is Map) {
        // Convert Map<Object?, Object?> to Map<String, dynamic>
        sensorData = Map<String, dynamic>.from(rawSensorData);
      } else {
        print("❌ SensorData - Unexpected sensor data type: ${rawSensorData.runtimeType}");
        return SensorData(sensor: Sensor(soilSensor: SoilSensor(value: 0.0)));
      }
      
      print("📊 SensorData - Converted sensor data: $sensorData");
      final sensor = Sensor.fromFirebase(sensorData);
      print("✅ SensorData - Successfully created: $sensor");
      return SensorData(sensor: sensor);
      
    } catch (e) {
      print("❌ SensorData - Error parsing: $e");
      print("❌ SensorData - Error type: ${e.runtimeType}");
      return SensorData(sensor: Sensor(soilSensor: SoilSensor(value: 0.0)));
    }
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'sensor': sensor.toFirebase(),
    };
  }

  // Create from MQTT data
  factory SensorData.fromMqtt(Map<String, dynamic> data) {
    return SensorData(
      sensor: Sensor.fromMqtt(data['sensor'] ?? {}),
    );
  }

  // Copy with method
  SensorData copyWith({
    Sensor? sensor,
  }) {
    return SensorData(
      sensor: sensor ?? this.sensor,
    );
  }

  @override
  String toString() {
    return 'SensorData(sensor: $sensor)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorData && other.sensor == sensor;
  }

  @override
  int get hashCode => sensor.hashCode;
}

class Sensor {
  final SoilSensor soilSensor;

  Sensor({
    required this.soilSensor,
  });

  // Create from Firebase data - FIXED TYPE CASTING
  factory Sensor.fromFirebase(Map<String, dynamic> data) {
    print("🔍 Sensor - Data received: $data");
    print("🔍 Sensor - Data type: ${data.runtimeType}");
    print("🔍 Sensor - Soil sensor data: ${data['soil_sensor']}");
    print("🔍 Sensor - Soil sensor data type: ${data['soil_sensor'].runtimeType}");
    
    try {
      final rawSoilSensorData = data['soil_sensor'];
      if (rawSoilSensorData == null) {
        print("❌ Sensor - No 'soil_sensor' key found, using default");
        return Sensor(soilSensor: SoilSensor(value: 0.0));
      }
      
      // Safe conversion from Object? to Map<String, dynamic>
      Map<String, dynamic> soilSensorData;
      if (rawSoilSensorData is Map<String, dynamic>) {
        soilSensorData = rawSoilSensorData;
      } else if (rawSoilSensorData is Map) {
        // Convert Map<Object?, Object?> to Map<String, dynamic>
        soilSensorData = Map<String, dynamic>.from(rawSoilSensorData);
      } else {
        print("❌ Sensor - Unexpected soil sensor data type: ${rawSoilSensorData.runtimeType}");
        return Sensor(soilSensor: SoilSensor(value: 0.0));
      }
      
      print("🔍 Sensor - Converted soil sensor data: $soilSensorData");
      final soilSensor = SoilSensor.fromFirebase(soilSensorData);
      print("✅ Sensor - Successfully created: $soilSensor");
      return Sensor(soilSensor: soilSensor);
      
    } catch (e) {
      print("❌ Sensor - Error parsing: $e");
      print("❌ Sensor - Error type: ${e.runtimeType}");
      return Sensor(soilSensor: SoilSensor(value: 0.0));
    }
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'soil_sensor': soilSensor.toFirebase(),
    };
  }

  // Create from MQTT data
  factory Sensor.fromMqtt(Map<String, dynamic> data) {
    return Sensor(
      soilSensor: SoilSensor.fromMqtt(data['soil_sensor'] ?? {}),
    );
  }

  // Copy with method
  Sensor copyWith({
    SoilSensor? soilSensor,
  }) {
    return Sensor(
      soilSensor: soilSensor ?? this.soilSensor,
    );
  }

  @override
  String toString() {
    return 'Sensor(soilSensor: $soilSensor)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Sensor && other.soilSensor == soilSensor;
  }

  @override
  int get hashCode => soilSensor.hashCode;
}

class SoilSensor {
  final double value;

  SoilSensor({
    required this.value,
  });

  // Create from Firebase data - FIXED TYPE CASTING
  factory SoilSensor.fromFirebase(Map<String, dynamic> data) {
    print("🌱 SoilSensor - Data received: $data");
    print("🌱 SoilSensor - Data type: ${data.runtimeType}");
    print("🌱 SoilSensor - Raw value: ${data['value']} (${data['value'].runtimeType})");
    
    try {
      final rawValue = data['value'];
      double parsedValue = 0.0;
      
      if (rawValue == null) {
        print("⚠️ SoilSensor - Value is null, using default 0.0");
        parsedValue = 0.0;
      } else if (rawValue is num) {
        parsedValue = rawValue.toDouble();
        print("✅ SoilSensor - Parsed as num: $parsedValue");
      } else if (rawValue is String) {
        parsedValue = double.tryParse(rawValue) ?? 0.0;
        print("✅ SoilSensor - Parsed from string: $parsedValue");
      } else {
        print("⚠️ SoilSensor - Unknown type (${rawValue.runtimeType}), trying toString conversion");
        final stringValue = rawValue.toString();
        parsedValue = double.tryParse(stringValue) ?? 0.0;
        print("✅ SoilSensor - Converted via toString: $parsedValue");
      }
      
      final result = SoilSensor(value: parsedValue);
      print("✅ SoilSensor - Final result: $result");
      return result;
      
    } catch (e) {
      print("❌ SoilSensor - Error parsing: $e");
      print("❌ SoilSensor - Error type: ${e.runtimeType}");
      return SoilSensor(value: 0.0);
    }
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'value': value,
    };
  }

  // Create from MQTT data
  factory SoilSensor.fromMqtt(Map<String, dynamic> data) {
    return SoilSensor(
      value: (data['value'] ?? data['soil_humidity'] ?? 0.0).toDouble(),
    );
  }

  // Copy with method
  SoilSensor copyWith({
    double? value,
  }) {
    return SoilSensor(
      value: value ?? this.value,
    );
  }

  // Convenience getters untuk analisis tanah
  bool get isOptimal => value >= 40 && value <= 70;

  String get condition {
    if (isOptimal) return 'Optimal';
    if (value < 40) return 'Kering';
    if (value > 70) return 'Terlalu Lembab';
    return 'Perlu Perhatian';
  }

  @override
  String toString() {
    return 'SoilSensor(value: ${value}%, condition: $condition)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SoilSensor && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

// Untuk testing dan debugging
class SensorDataDebugger {
  static void testFirebaseStructure() {
    // Test dengan struktur Firebase yang sebenarnya
    final testData = {
      "sensor": {
        "soil_sensor": {
          "value": 55
        }
      }
    };
    
    print("🧪 === TESTING FIREBASE STRUCTURE ===");
    print("🧪 Test data: $testData");
    
    try {
      final sensorData = SensorData.fromFirebase(testData);
      print("🧪 Result: $sensorData");
      print("🧪 Value: ${sensorData.sensor.soilSensor.value}%");
      print("🧪 Condition: ${sensorData.sensor.soilSensor.condition}");
      print("✅ Test PASSED!");
    } catch (e) {
      print("❌ Test FAILED: $e");
    }
    
    print("🧪 === END TEST ===");
  }
  
  static void debugStep(String step, dynamic data) {
    print("🔍 DEBUG [$step]: $data");
  }
}