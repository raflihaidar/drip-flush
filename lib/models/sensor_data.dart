class SensorData {
  final Sensor sensor;

  SensorData({
    required this.sensor,
  });

  // Create from Firebase data - Enhanced for multiple sensors
  factory SensorData.fromFirebase(Map<String, dynamic> data) {
    print("📊 SensorData - Full data received: $data");
    print("📊 SensorData - Data type: ${data.runtimeType}");
    print("📊 SensorData - Sensor data: ${data['sensor']}");
    print("📊 SensorData - Sensor data type: ${data['sensor'].runtimeType}");
    
    try {
      final rawSensorData = data['sensor'];
      if (rawSensorData == null) {
        print("❌ SensorData - No 'sensor' key found, using default");
        return SensorData(sensor: Sensor.getDefault());
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
        return SensorData(sensor: Sensor.getDefault());
      }
      
      print("📊 SensorData - Converted sensor data: $sensorData");
      final sensor = Sensor.fromFirebase(sensorData);
      print("✅ SensorData - Successfully created: $sensor");
      return SensorData(sensor: sensor);
      
    } catch (e) {
      print("❌ SensorData - Error parsing: $e");
      print("❌ SensorData - Error type: ${e.runtimeType}");
      return SensorData(sensor: Sensor.getDefault());
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
  final SoilSensor soilSensor1;
  final SoilSensor soilSensor2;

  Sensor({
    required this.soilSensor1,
    required this.soilSensor2,
  });

  // Create default sensor with both sensors
  factory Sensor.getDefault() {
    return Sensor(
      soilSensor1: SoilSensor(value: 0.0, sensorId: 'sensor_1'),
      soilSensor2: SoilSensor(value: 0.0, sensorId: 'sensor_2'),
    );
  }

  // Create from Firebase data - Enhanced for multiple sensors
  factory Sensor.fromFirebase(Map<String, dynamic> data) {
    print("🔍 Sensor - Data received: $data");
    print("🔍 Sensor - Data type: ${data.runtimeType}");
    
    try {
      SoilSensor soilSensor1;
      SoilSensor soilSensor2;

      // Check for multiple sensor structure
      if (data.containsKey('soil_sensor_1') && data.containsKey('soil_sensor_2')) {
        // Multi-sensor structure
        print("🔍 Sensor - Multi-sensor structure detected");
        
        final rawSoilSensor1 = data['soil_sensor_1'];
        final rawSoilSensor2 = data['soil_sensor_2'];
        
        soilSensor1 = _parseSoilSensor(rawSoilSensor1, 'sensor_1') ?? 
                      SoilSensor(value: 0.0, sensorId: 'sensor_1');
        soilSensor2 = _parseSoilSensor(rawSoilSensor2, 'sensor_2') ?? 
                      SoilSensor(value: 0.0, sensorId: 'sensor_2');
      } 
      // Check for single sensor structure (backward compatibility)
      else if (data.containsKey('soil_sensor')) {
        print("🔍 Sensor - Single sensor structure detected (backward compatibility)");
        
        final rawSoilSensor = data['soil_sensor'];
        soilSensor1 = _parseSoilSensor(rawSoilSensor, 'sensor_1') ?? 
                      SoilSensor(value: 0.0, sensorId: 'sensor_1');
        soilSensor2 = SoilSensor(value: 0.0, sensorId: 'sensor_2'); // Default for sensor 2
      }
      // Check for sensors array structure
      else if (data.containsKey('soil_sensors') && data['soil_sensors'] is List) {
        print("🔍 Sensor - Array sensor structure detected");
        
        final sensors = data['soil_sensors'] as List;
        soilSensor1 = sensors.isNotEmpty 
            ? _parseSoilSensor(sensors[0], 'sensor_1') ?? SoilSensor(value: 0.0, sensorId: 'sensor_1')
            : SoilSensor(value: 0.0, sensorId: 'sensor_1');
        soilSensor2 = sensors.length > 1 
            ? _parseSoilSensor(sensors[1], 'sensor_2') ?? SoilSensor(value: 0.0, sensorId: 'sensor_2')
            : SoilSensor(value: 0.0, sensorId: 'sensor_2');
      }
      else {
        print("⚠️ Sensor - No recognized sensor structure, using defaults");
        soilSensor1 = SoilSensor(value: 0.0, sensorId: 'sensor_1');
        soilSensor2 = SoilSensor(value: 0.0, sensorId: 'sensor_2');
      }
      
      final result = Sensor(
        soilSensor1: soilSensor1,
        soilSensor2: soilSensor2,
      );
      print("✅ Sensor - Successfully created: $result");
      return result;
      
    } catch (e) {
      print("❌ Sensor - Error parsing: $e");
      print("❌ Sensor - Error type: ${e.runtimeType}");
      return Sensor.getDefault();
    }
  }

  // Helper method to parse individual soil sensor
  static SoilSensor? _parseSoilSensor(dynamic rawData, String defaultId) {
    try {
      if (rawData == null) return null;
      
      Map<String, dynamic> sensorData;
      if (rawData is Map<String, dynamic>) {
        sensorData = rawData;
      } else if (rawData is Map) {
        sensorData = Map<String, dynamic>.from(rawData);
      } else {
        print("❌ _parseSoilSensor - Unexpected data type: ${rawData.runtimeType}");
        return null;
      }
      
      return SoilSensor.fromFirebase(sensorData, defaultId);
    } catch (e) {
      print("❌ _parseSoilSensor - Error: $e");
      return null;
    }
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'soil_sensor_1': soilSensor1.toFirebase(),
      'soil_sensor_2': soilSensor2.toFirebase(),
    };
  }

  // Create from MQTT data
  factory Sensor.fromMqtt(Map<String, dynamic> data) {
    return Sensor(
      soilSensor1: SoilSensor.fromMqtt(data['soil_sensor_1'] ?? {}, 'sensor_1'),
      soilSensor2: SoilSensor.fromMqtt(data['soil_sensor_2'] ?? {}, 'sensor_2'),
    );
  }

  // Copy with method
  Sensor copyWith({
    SoilSensor? soilSensor1,
    SoilSensor? soilSensor2,
  }) {
    return Sensor(
      soilSensor1: soilSensor1 ?? this.soilSensor1,
      soilSensor2: soilSensor2 ?? this.soilSensor2,
    );
  }

  // Convenience getters
  List<SoilSensor> get allSensors => [soilSensor1, soilSensor2];
  
  double get averageHumidity => (soilSensor1.value + soilSensor2.value) / 2;
  
  bool get hasValidData => soilSensor1.value > 0 || soilSensor2.value > 0;
  
  String get overallCondition {
    if (!hasValidData) return 'No Data';
    
    final avg = averageHumidity;
    if (avg >= 40 && avg <= 70) return 'Optimal';
    if (avg < 40) return 'Dry';
    if (avg > 70) return 'Too Wet';
    return 'Need Attention';
  }

  @override
  String toString() {
    return 'Sensor(sensor1: $soilSensor1, sensor2: $soilSensor2)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Sensor && 
           other.soilSensor1 == soilSensor1 && 
           other.soilSensor2 == soilSensor2;
  }

  @override
  int get hashCode => soilSensor1.hashCode ^ soilSensor2.hashCode;
}

class SoilSensor {
  final double value;
  final String sensorId;
  final DateTime? lastUpdate;
  final bool isActive;

  SoilSensor({
    required this.value,
    required this.sensorId,
    this.lastUpdate,
    this.isActive = true,
  });

  // Create from Firebase data - Enhanced with sensor ID
  factory SoilSensor.fromFirebase(Map<String, dynamic> data, String defaultId) {
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

      final sensorId = data['sensor_id']?.toString() ?? defaultId;
      final isActive = data['is_active'] ?? true;
      
      DateTime? lastUpdate;
      if (data['last_update'] != null) {
        try {
          if (data['last_update'] is String) {
            lastUpdate = DateTime.parse(data['last_update']);
          } else if (data['last_update'] is int) {
            lastUpdate = DateTime.fromMillisecondsSinceEpoch(data['last_update']);
          }
        } catch (e) {
          print("⚠️ SoilSensor - Error parsing last_update: $e");
        }
      }
      
      final result = SoilSensor(
        value: parsedValue,
        sensorId: sensorId,
        lastUpdate: lastUpdate,
        isActive: isActive,
      );
      print("✅ SoilSensor - Final result: $result");
      return result;
      
    } catch (e) {
      print("❌ SoilSensor - Error parsing: $e");
      print("❌ SoilSensor - Error type: ${e.runtimeType}");
      return SoilSensor(value: 0.0, sensorId: defaultId);
    }
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'value': value,
      'sensor_id': sensorId,
      'is_active': isActive,
      'last_update': lastUpdate?.toIso8601String(),
    };
  }

  // Create from MQTT data
  factory SoilSensor.fromMqtt(Map<String, dynamic> data, String defaultId) {
    final value = (data['value'] ?? data['soil_humidity'] ?? data['humidity'] ?? 0.0).toDouble();
    final sensorId = data['sensor_id']?.toString() ?? defaultId;
    final isActive = data['is_active'] ?? true;
    
    return SoilSensor(
      value: value,
      sensorId: sensorId,
      lastUpdate: DateTime.now(),
      isActive: isActive,
    );
  }

  // Copy with method
  SoilSensor copyWith({
    double? value,
    String? sensorId,
    DateTime? lastUpdate,
    bool? isActive,
  }) {
    return SoilSensor(
      value: value ?? this.value,
      sensorId: sensorId ?? this.sensorId,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isActive: isActive ?? this.isActive,
    );
  }

  // Convenience getters untuk analisis tanah
  bool get isOptimal => value >= 40 && value <= 70;

  String get condition {
    if (!isActive) return 'Inactive';
    if (value == 0.0) return 'No Data';
    if (isOptimal) return 'Optimal';
    if (value < 40) return 'Dry';
    if (value > 70) return 'Too Wet';
    return 'Need Attention';
  }

  String get conditionColor {
    switch (condition) {
      case 'Optimal': return 'green';
      case 'Dry': return 'orange';
      case 'Too Wet': return 'blue';
      case 'Inactive': return 'grey';
      case 'No Data': return 'grey';
      default: return 'red';
    }
  }

  @override
  String toString() {
    return 'SoilSensor(id: $sensorId, value: ${value}%, condition: $condition, active: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SoilSensor && 
           other.value == value && 
           other.sensorId == sensorId;
  }

  @override
  int get hashCode => value.hashCode ^ sensorId.hashCode;
}

// Enhanced debugger for multi-sensor testing
class SensorDataDebugger {
  static void testMultiSensorFirebaseStructure() {
    // Test dengan struktur multi-sensor Firebase
    final testData = {
      "sensor": {
        "soil_sensor_1": {
          "value": 55.5,
          "sensor_id": "sensor_1",
          "is_active": true,
          "last_update": "2025-06-05T10:30:00.000Z"
        },
        "soil_sensor_2": {
          "value": 62.3,
          "sensor_id": "sensor_2", 
          "is_active": true,
          "last_update": "2025-06-05T10:30:05.000Z"
        }
      }
    };
    
    print("🧪 === TESTING MULTI-SENSOR FIREBASE STRUCTURE ===");
    print("🧪 Test data: $testData");
    
    try {
      final sensorData = SensorData.fromFirebase(testData);
      print("🧪 Result: $sensorData");
      print("🧪 Sensor 1 - Value: ${sensorData.sensor.soilSensor1.value}%, Condition: ${sensorData.sensor.soilSensor1.condition}");
      print("🧪 Sensor 2 - Value: ${sensorData.sensor.soilSensor2.value}%, Condition: ${sensorData.sensor.soilSensor2.condition}");
      print("🧪 Average: ${sensorData.sensor.averageHumidity.toStringAsFixed(1)}%");
      print("🧪 Overall Condition: ${sensorData.sensor.overallCondition}");
      print("✅ Multi-sensor Test PASSED!");
    } catch (e) {
      print("❌ Multi-sensor Test FAILED: $e");
    }
    
    print("🧪 === END MULTI-SENSOR TEST ===");
  }

  static void testBackwardCompatibility() {
    // Test backward compatibility dengan struktur single sensor
    final testData = {
      "sensor": {
        "soil_sensor": {
          "value": 45.0
        }
      }
    };
    
    print("🧪 === TESTING BACKWARD COMPATIBILITY ===");
    print("🧪 Test data: $testData");
    
    try {
      final sensorData = SensorData.fromFirebase(testData);
      print("🧪 Result: $sensorData");
      print("🧪 Sensor 1 - Value: ${sensorData.sensor.soilSensor1.value}%, Condition: ${sensorData.sensor.soilSensor1.condition}");
      print("🧪 Sensor 2 - Value: ${sensorData.sensor.soilSensor2.value}%, Condition: ${sensorData.sensor.soilSensor2.condition}");
      print("✅ Backward Compatibility Test PASSED!");
    } catch (e) {
      print("❌ Backward Compatibility Test FAILED: $e");
    }
    
    print("🧪 === END BACKWARD COMPATIBILITY TEST ===");
  }
  
  static void debugStep(String step, dynamic data) {
    print("🔍 DEBUG [$step]: $data");
  }
}