
class PumpStatus {
  final Pump pump;

  PumpStatus({
    required this.pump,
  });

  // Create from Firebase data
  factory PumpStatus.fromFirebase(Map<String, dynamic> data) {
    return PumpStatus(
      pump: Pump.fromFirebase(data['pump'] ?? {}),
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'pump': pump.toFirebase(),
    };
  }

  // Create from MQTT data
  factory PumpStatus.fromMqtt(Map<String, dynamic> data) {
    return PumpStatus(
      pump: Pump.fromMqtt(data['pump'] ?? {}),
    );
  }

  // Copy with method
  PumpStatus copyWith({
    Pump? pump,
  }) {
    return PumpStatus(
      pump: pump ?? this.pump,
    );
  }

  @override
  String toString() {
    return 'PumpStatus(pump: $pump)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PumpStatus && other.pump == pump;
  }

  @override
  int get hashCode => pump.hashCode;
}

class Pump {
  final WaterPump waterPump;

  Pump({
    required this.waterPump,
  });

  // Create from Firebase data
  factory Pump.fromFirebase(Map<String, dynamic> data) {
    return Pump(
      waterPump: WaterPump.fromFirebase(data['water_pump'] ?? {}),
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'water_pump': waterPump.toFirebase(),
    };
  }

  // Create from MQTT data
  factory Pump.fromMqtt(Map<String, dynamic> data) {
    return Pump(
      waterPump: WaterPump.fromMqtt(data['water_pump'] ?? {}),
    );
  }

  // Copy with method
  Pump copyWith({
    WaterPump? waterPump,
  }) {
    return Pump(
      waterPump: waterPump ?? this.waterPump,
    );
  }

  @override
  String toString() {
    return 'Pump(waterPump: $waterPump)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Pump && other.waterPump == waterPump;
  }

  @override
  int get hashCode => waterPump.hashCode;
}

class WaterPump {
  final bool isActive;

  WaterPump({
    required this.isActive,
  });

  // Create from Firebase data
  factory WaterPump.fromFirebase(Map<String, dynamic> data) {
    return WaterPump(
      isActive: data['is_active'] ?? false,
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'is_active': isActive,
    };
  }

  // Create from MQTT data
  factory WaterPump.fromMqtt(Map<String, dynamic> data) {
    return WaterPump(
      isActive: data['is_active'] ?? data['active'] ?? false,
    );
  }

  // Copy with method
  WaterPump copyWith({
    bool? isActive,
  }) {
    return WaterPump(
      isActive: isActive ?? this.isActive,
    );
  }

  // Convenience getters
  String get status => isActive ? 'Running' : 'Stopped';
  String get statusIcon => isActive ? '🟢' : '🔴';

  @override
  String toString() {
    return 'WaterPump(isActive: $isActive, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WaterPump && other.isActive == isActive;
  }

  @override
  int get hashCode => isActive.hashCode;
}