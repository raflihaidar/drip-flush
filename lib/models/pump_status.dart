class PumpStatus {
  final bool isActive;
  final DateTime? lastActivated;
  final DateTime? lastDeactivated;
  final Duration totalRunTime;
  final String status; // 'running', 'stopped', 'error', 'maintenance'
  final double flowRate; // liters per minute
  final bool autoMode;
  final int scheduledDuration; // minutes
  final String pumpId;
  final double pressure; // bar
  final int cyclesCount;
  final DateTime? nextScheduledRun;
  final Map<String, dynamic> settings;

  PumpStatus({
    required this.isActive,
    this.lastActivated,
    this.lastDeactivated,
    this.totalRunTime = Duration.zero,
    this.status = 'stopped',
    this.flowRate = 0.0,
    this.autoMode = false,
    this.scheduledDuration = 10,
    this.pumpId = 'main_pump',
    this.pressure = 0.0,
    this.cyclesCount = 0,
    this.nextScheduledRun,
    this.settings = const {},
  });

  // Create from Firebase data
  factory PumpStatus.fromFirebase(Map<String, dynamic> data) {
    return PumpStatus(
      isActive: data['is_active'] ?? false,
      lastActivated: data['last_activated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['last_activated'])
          : null,
      lastDeactivated: data['last_deactivated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['last_deactivated'])
          : null,
      totalRunTime: Duration(minutes: data['total_run_time_minutes'] ?? 0),
      status: data['status'] ?? 'stopped',
      flowRate: (data['flow_rate'] ?? 0.0).toDouble(),
      autoMode: data['auto_mode'] ?? false,
      scheduledDuration: data['scheduled_duration'] ?? 10,
      pumpId: data['pump_id'] ?? 'main_pump',
      pressure: (data['pressure'] ?? 0.0).toDouble(),
      cyclesCount: data['cycles_count'] ?? 0,
      nextScheduledRun: data['next_scheduled_run'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['next_scheduled_run'])
          : null,
      settings: Map<String, dynamic>.from(data['settings'] ?? {}),
    );
  }

  // Create from MQTT data
  factory PumpStatus.fromMqtt(Map<String, dynamic> data) {
    return PumpStatus(
      isActive: data['active'] ?? data['is_active'] ?? false,
      lastActivated: data['last_on'] != null || data['last_activated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              data['last_on'] ?? data['last_activated'])
          : null,
      lastDeactivated: data['last_off'] != null || data['last_deactivated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              data['last_off'] ?? data['last_deactivated'])
          : null,
      totalRunTime: Duration(
          minutes: data['runtime'] ?? data['total_run_time_minutes'] ?? 0),
      status: data['state'] ?? data['status'] ?? 'stopped',
      flowRate: (data['flow'] ?? data['flow_rate'] ?? 0.0).toDouble(),
      autoMode: data['auto'] ?? data['auto_mode'] ?? false,
      scheduledDuration: data['duration'] ?? data['scheduled_duration'] ?? 10,
      pumpId: data['pump_id'] ?? data['id'] ?? 'main_pump',
      pressure: (data['pressure'] ?? 0.0).toDouble(),
      cyclesCount: data['cycles'] ?? data['cycles_count'] ?? 0,
      nextScheduledRun: data['next_run'] != null || data['next_scheduled_run'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              data['next_run'] ?? data['next_scheduled_run'])
          : null,
      settings: Map<String, dynamic>.from(data['settings'] ?? data['config'] ?? {}),
    );
  }

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'is_active': isActive,
      'last_activated': lastActivated?.millisecondsSinceEpoch,
      'last_deactivated': lastDeactivated?.millisecondsSinceEpoch,
      'total_run_time_minutes': totalRunTime.inMinutes,
      'status': status,
      'flow_rate': flowRate,
      'auto_mode': autoMode,
      'scheduled_duration': scheduledDuration,
      'pump_id': pumpId,
      'pressure': pressure,
      'cycles_count': cyclesCount,
      'next_scheduled_run': nextScheduledRun?.millisecondsSinceEpoch,
      'settings': settings,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  // Convert to MQTT format
  Map<String, dynamic> toMqtt() {
    return {
      'active': isActive,
      'last_on': lastActivated?.millisecondsSinceEpoch,
      'last_off': lastDeactivated?.millisecondsSinceEpoch,
      'runtime': totalRunTime.inMinutes,
      'state': status,
      'flow': flowRate,
      'auto': autoMode,
      'duration': scheduledDuration,
      'pump_id': pumpId,
      'pressure': pressure,
      'cycles': cyclesCount,
      'next_run': nextScheduledRun?.millisecondsSinceEpoch,
      'config': settings,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'isActive': isActive,
      'lastActivated': lastActivated?.toIso8601String(),
      'lastDeactivated': lastDeactivated?.toIso8601String(),
      'totalRunTimeMinutes': totalRunTime.inMinutes,
      'status': status,
      'flowRate': flowRate,
      'autoMode': autoMode,
      'scheduledDuration': scheduledDuration,
      'pumpId': pumpId,
      'pressure': pressure,
      'cyclesCount': cyclesCount,
      'nextScheduledRun': nextScheduledRun?.toIso8601String(),
      'settings': settings,
    };
  }

  // Create from JSON
  factory PumpStatus.fromJson(Map<String, dynamic> json) {
    return PumpStatus(
      isActive: json['isActive'] ?? false,
      lastActivated: json['lastActivated'] != null
          ? DateTime.parse(json['lastActivated'])
          : null,
      lastDeactivated: json['lastDeactivated'] != null
          ? DateTime.parse(json['lastDeactivated'])
          : null,
      totalRunTime: Duration(minutes: json['totalRunTimeMinutes'] ?? 0),
      status: json['status'] ?? 'stopped',
      flowRate: (json['flowRate'] ?? 0.0).toDouble(),
      autoMode: json['autoMode'] ?? false,
      scheduledDuration: json['scheduledDuration'] ?? 10,
      pumpId: json['pumpId'] ?? 'main_pump',
      pressure: (json['pressure'] ?? 0.0).toDouble(),
      cyclesCount: json['cyclesCount'] ?? 0,
      nextScheduledRun: json['nextScheduledRun'] != null
          ? DateTime.parse(json['nextScheduledRun'])
          : null,
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
    );
  }

  // Copy with modifications
  PumpStatus copyWith({
    bool? isActive,
    DateTime? lastActivated,
    DateTime? lastDeactivated,
    Duration? totalRunTime,
    String? status,
    double? flowRate,
    bool? autoMode,
    int? scheduledDuration,
    String? pumpId,
    double? pressure,
    int? cyclesCount,
    DateTime? nextScheduledRun,
    Map<String, dynamic>? settings,
  }) {
    return PumpStatus(
      isActive: isActive ?? this.isActive,
      lastActivated: lastActivated ?? this.lastActivated,
      lastDeactivated: lastDeactivated ?? this.lastDeactivated,
      totalRunTime: totalRunTime ?? this.totalRunTime,
      status: status ?? this.status,
      flowRate: flowRate ?? this.flowRate,
      autoMode: autoMode ?? this.autoMode,
      scheduledDuration: scheduledDuration ?? this.scheduledDuration,
      pumpId: pumpId ?? this.pumpId,
      pressure: pressure ?? this.pressure,
      cyclesCount: cyclesCount ?? this.cyclesCount,
      nextScheduledRun: nextScheduledRun ?? this.nextScheduledRun,
      settings: settings ?? this.settings,
    );
  }

  // Check if pump is in error state
  bool get hasError => status == 'error';

  // Check if pump needs maintenance
  bool get needsMaintenance {
    return status == 'maintenance' || 
           cyclesCount > 10000 || 
           totalRunTime.inHours > 500;
  }

  // Get status color for UI
  String get statusColor {
    switch (status) {
      case 'running':
        return 'green';
      case 'stopped':
        return 'gray';
      case 'error':
        return 'red';
      case 'maintenance':
        return 'orange';
      default:
        return 'blue';
    }
  }

  // Get formatted total runtime
  String get formattedTotalRunTime {
    final hours = totalRunTime.inHours;
    final minutes = totalRunTime.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  // Get formatted last activation time
  String get formattedLastActivated {
    if (lastActivated == null) return 'Never';
    
    final now = DateTime.now();
    final difference = now.difference(lastActivated!);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  // Calculate efficiency percentage
  double get efficiency {
    if (cyclesCount == 0) return 100.0;
    
    // Simple efficiency calculation based on runtime vs cycles
    // You can customize this based on your pump specifications
    final expectedRuntime = cyclesCount * scheduledDuration;
    final actualRuntime = totalRunTime.inMinutes;
    
    if (expectedRuntime == 0) return 100.0;
    
    return (actualRuntime / expectedRuntime * 100).clamp(0.0, 100.0);
  }

  // Get next scheduled run formatted
  String get formattedNextRun {
    if (nextScheduledRun == null || !autoMode) return 'Not scheduled';
    
    final now = DateTime.now();
    if (nextScheduledRun!.isBefore(now)) return 'Overdue';
    
    final difference = nextScheduledRun!.difference(now);
    
    if (difference.inDays > 0) {
      return 'In ${difference.inDays} days';
    } else if (difference.inHours > 0) {
      return 'In ${difference.inHours} hours';
    } else if (difference.inMinutes > 0) {
      return 'In ${difference.inMinutes} minutes';
    } else {
      return 'Starting soon';
    }
  }

  @override
  String toString() {
    return 'PumpStatus{active: $isActive, status: $status, flow: ${flowRate}L/min, auto: $autoMode, cycles: $cyclesCount, runtime: $formattedTotalRunTime}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PumpStatus &&
        other.isActive == isActive &&
        other.status == status &&
        other.flowRate == flowRate &&
        other.autoMode == autoMode &&
        other.scheduledDuration == scheduledDuration &&
        other.pumpId == pumpId &&
        other.pressure == pressure &&
        other.cyclesCount == cyclesCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      isActive,
      status,
      flowRate,
      autoMode,
      scheduledDuration,
      pumpId,
      pressure,
      cyclesCount,
    );
  }
}