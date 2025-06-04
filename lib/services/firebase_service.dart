import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';
import '../models/pump_status.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  late DatabaseReference _database;
  bool _isInitialized = false;

  // Stream controllers
  final StreamController<SensorData> _sensorController =
      StreamController<SensorData>.broadcast();
  final StreamController<PumpStatus> _pumpController =
      StreamController<PumpStatus>.broadcast();

  Stream<SensorData> get sensorStream => _sensorController.stream;
  Stream<PumpStatus> get pumpStream => _pumpController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;

      print('🔥 Firebase service initialized');
      
      await _debugExistingData();
      await _ensureDataExists();
      _setupListeners();
      _startHistoricalDataSaving();

      print('✅ Firebase service ready');
    } catch (e) {
      print('❌ Firebase service initialization error: $e');
      rethrow;
    }
  }

  Future<void> _debugExistingData() async {
    try {
      print('🔍 === CHECKING EXISTING FIREBASE DATA ===');
      
      final mainSnapshot = await _database.child('greenhouse_data').get();
      print('📂 greenhouse_data exists: ${mainSnapshot.exists}');
      
      if (mainSnapshot.exists) {
        final sensorSnapshot = await _database.child('greenhouse_data/current_sensor').get();
        print('📊 current_sensor exists: ${sensorSnapshot.exists}');
        if (sensorSnapshot.exists) {
          print('📊 current_sensor data: ${sensorSnapshot.value}');
        }
        
        final pumpSnapshot = await _database.child('greenhouse_data/current_pump').get();
        print('🔧 current_pump exists: ${pumpSnapshot.exists}');
        if (pumpSnapshot.exists) {
          print('🔧 current_pump data: ${pumpSnapshot.value}');
        }

        // Check historical data structure
        final historySnapshot = await _database.child('greenhouse_data/sensor_history').get();
        print('📚 sensor_history exists: ${historySnapshot.exists}');
        if (historySnapshot.exists) {
          print('📚 sensor_history count: ${(historySnapshot.value as Map?)?.length ?? 0}');
        }
      }
      
      print('🔍 === END DATA CHECK ===');
    } catch (e) {
      print('❌ Debug error: $e');
    }
  }

  Future<void> _ensureDataExists() async {
    try {
      final sensorSnapshot = await _database.child('greenhouse_data/current_sensor').get();
      if (!sensorSnapshot.exists) {
        print('📊 Creating initial sensor data...');
        await _createInitialSensorData();
      }

      final pumpSnapshot = await _database.child('greenhouse_data/current_pump').get();
      if (!pumpSnapshot.exists) {
        print('🔧 Creating initial pump data...');
        await _createInitialPumpData();
      }
      
    } catch (e) {
      print('❌ Error ensuring data exists: $e');
    }
  }

  Future<void> _createInitialSensorData() async {
    final sensorData = {
      "sensor": {
        "soil_sensor": {
          "value": 55.0
        }
      },
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "updated_at": DateTime.now().toIso8601String(),
    };

    await _database.child('greenhouse_data/current_sensor').set(sensorData);
    
    // Also add to history
    await _addSensorDataToHistory(sensorData);
    
    print('✅ Initial sensor data created: 55.0%');
  }

  Future<void> _createInitialPumpData() async {
    final pumpData = {
      "pump": {
        "water_pump": {
          "is_active": false
        }
      },
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "updated_at": DateTime.now().toIso8601String(),
    };

    await _database.child('greenhouse_data/current_pump').set(pumpData);
    
    // Also add to history
    // await _addPumpDataToHistory(pumpData);
    
    print('✅ Initial pump data created: OFF');
  }

  void _setupListeners() {
    print('👂 Setting up Firebase listeners...');
    
    // Listen to sensor data changes
    _database.child('greenhouse_data/current_sensor').onValue.listen(
      (event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            print('📨 Sensor data received: $data');
            
            final sensorData = SensorData.fromFirebase(data);
            print('✅ Sensor parsed: ${sensorData.sensor.soilSensor.value}% - ${sensorData.sensor.soilSensor.condition}');
            
            _sensorController.add(sensorData);
          } catch (e) {
            print('❌ Error parsing sensor data: $e');
            print('📊 Raw data: ${event.snapshot.value}');
          }
        }
      },
      onError: (error) {
        print('❌ Sensor listener error: $error');
      },
    );

    // Listen to pump status changes
    _database.child('greenhouse_data/current_pump').onValue.listen(
      (event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            print('📨 Pump data received: $data');
            
            final pumpStatus = PumpStatus.fromFirebase(data);
            print('✅ Pump parsed: ${pumpStatus.pump.waterPump.isActive ? "ON" : "OFF"}');
            
            _pumpController.add(pumpStatus);
          } catch (e) {
            print('❌ Error parsing pump data: $e');
            print('📊 Raw data: ${event.snapshot.value}');
          }
        }
      },
      onError: (error) {
        print('❌ Pump listener error: $error');
      },
    );
    
    print('✅ Firebase listeners setup complete');
  }

  // ENHANCED: Add sensor data to history (append, not replace)
  Future<void> _addSensorDataToHistory(Map<String, dynamic> sensorData) async {
    try {
      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;
      
      // Create historical entry with unique key
      final historyEntry = {
        ...sensorData,
        'id': 'sensor_${timestamp}_${now.microsecond}',
        'recorded_at': now.toIso8601String(),
        'date_key': _getDateKey(now),
        'hour': now.hour,
        'minute': now.minute,
      };

      // Add to sensor history with push() to generate unique key
      await _database.child('greenhouse_data/sensor_history').push().set(historyEntry);
      
      // Also maintain daily summaries for easier querying
      await _updateDailySensorSummary(now, sensorData);
      
      print('📚 Sensor data added to history: ${historyEntry['id']}');
    } catch (e) {
      print('❌ Error adding sensor data to history: $e');
    }
  }

  // ENHANCED: Add pump data to history (append, not replace)
  Future<void> _addPumpDataToHistory(Map<String, dynamic> pumpData) async {
    try {
      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;
      
      // Create historical entry with unique key
      final historyEntry = {
        ...pumpData,
        'id': 'pump_${timestamp}_${now.microsecond}',
        'recorded_at': now.toIso8601String(),
        'date_key': _getDateKey(now),
        'hour': now.hour,
        'minute': now.minute,
      };

      // Add to pump history with push() to generate unique key
      await _database.child('greenhouse_data/pump_history').push().set(historyEntry);
      
      // Also maintain daily summaries for easier querying
      await _updateDailyPumpSummary(now, pumpData);
      
      print('📚 Pump data added to history: ${historyEntry['id']}');
    } catch (e) {
      print('❌ Error adding pump data to history: $e');
    }
  }

  // Helper method to get date key (YYYY-MM-DD format)
  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Update daily sensor summary for analytics
  Future<void> _updateDailySensorSummary(DateTime date, Map<String, dynamic> sensorData) async {
    try {
      final dateKey = _getDateKey(date);
      final summaryRef = _database.child('greenhouse_data/daily_summaries/sensor/$dateKey');
      
      final currentSummary = await summaryRef.get();
      Map<String, dynamic> summary;
      
      if (currentSummary.exists && currentSummary.value != null) {
        summary = Map<String, dynamic>.from(currentSummary.value as Map);
      } else {
        summary = {
          'date': dateKey,
          'first_reading': date.toIso8601String(),
          'count': 0,
          'values': <double>[],
          'min_value': double.infinity,
          'max_value': double.negativeInfinity,
          'total_value': 0.0,
        };
      }
      
      // Extract sensor value
      final sensorValue = ((sensorData['sensor'] as Map?)?['soil_sensor'] as Map?)?['value'] as num? ?? 0.0;
      final doubleValue = sensorValue.toDouble();
      
      // Update summary
      summary['count'] = (summary['count'] ?? 0) + 1;
      summary['last_reading'] = date.toIso8601String();
      summary['total_value'] = (summary['total_value'] ?? 0.0) + doubleValue;
      summary['average_value'] = (summary['total_value'] as double) / (summary['count'] as int);
      
      if (doubleValue < (summary['min_value'] as double)) {
        summary['min_value'] = doubleValue;
      }
      if (doubleValue > (summary['max_value'] as double)) {
        summary['max_value'] = doubleValue;
      }
      
      // Keep recent values (last 10)
      final values = List<double>.from(summary['values'] ?? []);
      values.add(doubleValue);
      if (values.length > 10) {
        values.removeAt(0);
      }
      summary['values'] = values;
      
      await summaryRef.set(summary);
      print('📊 Daily sensor summary updated for $dateKey');
    } catch (e) {
      print('❌ Error updating daily sensor summary: $e');
    }
  }

  // Update daily pump summary for analytics
  Future<void> _updateDailyPumpSummary(DateTime date, Map<String, dynamic> pumpData) async {
    try {
      final dateKey = _getDateKey(date);
      final summaryRef = _database.child('greenhouse_data/daily_summaries/pump/$dateKey');
      
      final currentSummary = await summaryRef.get();
      Map<String, dynamic> summary;
      
      if (currentSummary.exists && currentSummary.value != null) {
        summary = Map<String, dynamic>.from(currentSummary.value as Map);
      } else {
        summary = {
          'date': dateKey,
          'first_reading': date.toIso8601String(),
          'activation_count': 0,
          'total_on_time': 0,
          'last_status': false,
          'status_changes': <Map<String, dynamic>>[],
        };
      }
      
      // Extract pump status
      final isActive = ((pumpData['pump'] as Map?)?['water_pump'] as Map?)?['is_active'] as bool? ?? false;
      
      // Track status changes
      if (summary['last_status'] != isActive) {
        summary['status_changes'] = List<Map<String, dynamic>>.from(summary['status_changes'] ?? []);
        (summary['status_changes'] as List).add({
          'timestamp': date.toIso8601String(),
          'status': isActive,
          'previous_status': summary['last_status'],
        });
        
        if (isActive) {
          summary['activation_count'] = (summary['activation_count'] ?? 0) + 1;
        }
        
        summary['last_status'] = isActive;
      }
      
      summary['last_reading'] = date.toIso8601String();
      
      await summaryRef.set(summary);
      print('🔧 Daily pump summary updated for $dateKey');
    } catch (e) {
      print('❌ Error updating daily pump summary: $e');
    }
  }

  // MODIFIED: Update sensor data and add to history
  Future<void> updateSensorData(SensorData data) async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return;
    }

    try {
      final firebaseData = data.toFirebase();
      firebaseData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      firebaseData['updated_at'] = DateTime.now().toIso8601String();
      
      // Update current sensor data
      await _database.child('greenhouse_data/current_sensor').set(firebaseData);
      
      // Add to history
      await _addSensorDataToHistory(firebaseData);
      
      print('✅ Sensor data updated and added to history: ${data.sensor.soilSensor.value}%');
    } catch (e) {
      print('❌ Error updating sensor data: $e');
      rethrow;
    }
  }

  // MODIFIED: Update pump status and add to history
  Future<void> updatePumpStatus(PumpStatus status) async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return;
    }

    try {
      final firebaseData = status.toFirebase();
      firebaseData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      firebaseData['updated_at'] = DateTime.now().toIso8601String();
      
      // Update current pump status
      await _database.child('greenhouse_data/current_pump').set(firebaseData);
      
      // Add to history
      // await _addPumpDataToHistory(firebaseData);
      
      print('✅ Pump status updated and added to history: ${status.pump.waterPump.isActive ? "ON" : "OFF"}');
    } catch (e) {
      print('❌ Error updating pump status: $e');
      rethrow;
    }
  }

  // NEW: Get sensor history data
  Future<List<Map<String, dynamic>>> getSensorHistory({
    String? dateKey,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    if (!_isInitialized) return [];

    try {
      Query query = _database.child('greenhouse_data/sensor_history');
      
      if (dateKey != null) {
        query = query.orderByChild('date_key').equalTo(dateKey);
      } else if (startDate != null && endDate != null) {
        query = query
            .orderByChild('timestamp')
            .startAt(startDate.millisecondsSinceEpoch)
            .endAt(endDate.millisecondsSinceEpoch);
      } else {
        query = query.orderByChild('timestamp');
      }
      
      if (limit != null) {
        query = query.limitToLast(limit);
      }

      final snapshot = await query.get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final result = data.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
            
        result.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
        return result;
      }
      
      return [];
    } catch (e) {
      print('❌ Error getting sensor history: $e');
      return [];
    }
  }

  // NEW: Get pump history data
  Future<List<Map<String, dynamic>>> getPumpHistory({
    String? dateKey,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    if (!_isInitialized) return [];

    try {
      Query query = _database.child('greenhouse_data/pump_history');
      
      if (dateKey != null) {
        query = query.orderByChild('date_key').equalTo(dateKey);
      } else if (startDate != null && endDate != null) {
        query = query
            .orderByChild('timestamp')
            .startAt(startDate.millisecondsSinceEpoch)
            .endAt(endDate.millisecondsSinceEpoch);
      } else {
        query = query.orderByChild('timestamp');
      }
      
      if (limit != null) {
        query = query.limitToLast(limit);
      }

      final snapshot = await query.get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final result = data.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
            
        result.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
        return result;
      }
      
      return [];
    } catch (e) {
      print('❌ Error getting pump history: $e');
      return [];
    }
  }

  // NEW: Get daily summaries
  Future<Map<String, dynamic>?> getDailySummary(String type, String dateKey) async {
    if (!_isInitialized) return null;

    try {
      final snapshot = await _database
          .child('greenhouse_data/daily_summaries/$type/$dateKey')
          .get();
          
      if (snapshot.exists && snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting daily summary: $e');
      return null;
    }
  }

  // EXISTING METHODS (unchanged)
  Future<SensorData?> getSensorData() async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return null;
    }

    try {
      print('🔍 Fetching sensor data...');
      final snapshot = await _database.child('greenhouse_data/current_sensor').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print('📊 Retrieved sensor data: $data');
        
        final sensorData = SensorData.fromFirebase(data);
        print('✅ Sensor data: ${sensorData.sensor.soilSensor.value}%');
        return sensorData;
      } else {
        print('⚠️ No sensor data found, creating default...');
        await _createInitialSensorData();
        
        final retrySnapshot = await _database.child('greenhouse_data/current_sensor').get();
        if (retrySnapshot.exists && retrySnapshot.value != null) {
          final data = Map<String, dynamic>.from(retrySnapshot.value as Map);
          return SensorData.fromFirebase(data);
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting sensor data: $e');
      return null;
    }
  }

  Future<PumpStatus?> getPumpStatus() async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return null;
    }

    try {
      print('🔍 Fetching pump status...');
      final snapshot = await _database.child('greenhouse_data/current_pump').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print('📊 Retrieved pump data: $data');
        
        final pumpStatus = PumpStatus.fromFirebase(data);
        print('✅ Pump status: ${pumpStatus.pump.waterPump.isActive ? "ON" : "OFF"}');
        return pumpStatus;
      } else {
        print('⚠️ No pump data found, creating default...');
        await _createInitialPumpData();
        
        final retrySnapshot = await _database.child('greenhouse_data/current_pump').get();
        if (retrySnapshot.exists && retrySnapshot.value != null) {
          final data = Map<String, dynamic>.from(retrySnapshot.value as Map);
          return PumpStatus.fromFirebase(data);
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting pump status: $e');
      return null;
    }
  }

  // Quick update methods for testing
  Future<void> updateSensorValue(double value) async {
    if (!_isInitialized) return;

    try {
      final sensorData = SensorData(
        sensor: Sensor(
          soilSensor: SoilSensor(value: value),
        ),
      );
      
      await updateSensorData(sensorData);
      print('🧪 Test sensor value updated: ${value}%');
    } catch (e) {
      print('❌ Error updating test sensor value: $e');
    }
  }

  Future<void> updatePumpActive(bool isActive) async {
    if (!_isInitialized) return;

    try {
      final pumpStatus = PumpStatus(
        pump: Pump(
          waterPump: WaterPump(isActive: isActive),
        ),
      );
      
      await updatePumpStatus(pumpStatus);
      print('🧪 Test pump status updated: ${isActive ? "ON" : "OFF"}');
    } catch (e) {
      print('❌ Error updating test pump status: $e');
    }
  }

  // Auto watering settings (unchanged)
  Future<void> updateAutoWateringSettings(Map<String, dynamic> settings) async {
    if (!_isInitialized) return;

    try {
      settings['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      settings['updated_at'] = DateTime.now().toIso8601String();
      
      await _database.child('greenhouse_data/auto_watering_settings').set(settings);
      print('✅ Auto watering settings updated');
    } catch (e) {
      print('❌ Error updating auto watering settings: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getAutoWateringSettings() async {
    if (!_isInitialized) return null;

    try {
      final snapshot = await _database.child('greenhouse_data/auto_watering_settings').get();
      if (snapshot.exists && snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('❌ Error getting auto watering settings: $e');
      return null;
    }
  }

  // LEGACY: Keep for backward compatibility
  Future<List<Map<String, dynamic>>> getHistoricalData({
    required String sensorType,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (sensorType == 'sensor') {
      return await getSensorHistory(startDate: startDate, endDate: endDate);
    } else {
      return await getPumpHistory(startDate: startDate, endDate: endDate);
    }
  }

  Future<void> saveHistoricalSensorData(SensorData data) async {
    // This method is now automatically called in updateSensorData
    print('📚 Historical sensor saving is now automatic');
  }

  Future<void> saveHistoricalPumpData(PumpStatus status) async {
    // This method is now automatically called in updatePumpStatus
    print('📚 Historical pump saving is now automatic');
  }

  // Auto-save historical data timer (modified)
  Timer? _historicalDataTimer;

  void _startHistoricalDataSaving() {
    // Reduced frequency since we now save on every update
    _historicalDataTimer = Timer.periodic(Duration(minutes: 30), (timer) async {
      try {
        // Just log current status for monitoring
        final sensorData = await getSensorData();
        final pumpData = await getPumpStatus();
        
        // print('⏰ Periodic check - Sensor: ${sensorData?.sensor.soilSensor.value}%, Pump: ${pumpData?.pump.waterPump.isActive ? "ON" : "OFF"}');
        
        // Optional: Clean up old data to manage storage
        await _cleanupOldHistoricalData();
        
      } catch (e) {
        print('❌ Error in periodic check: $e');
      }
    });

    print('📚 Periodic monitoring started (every 30 minutes)');
  }

  // NEW: Cleanup old historical data to manage storage
  Future<void> _cleanupOldHistoricalData() async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: 90)); // Keep 90 days
      
      // This is a simplified cleanup - in production, you might want more sophisticated cleanup
      print('🧹 Cleanup check for data older than ${cutoffDate.toIso8601String()}');
      
      // You can implement more specific cleanup logic here based on your needs
      
    } catch (e) {
      print('❌ Error in cleanup: $e');
    }
  }

  void _stopHistoricalDataSaving() {
    _historicalDataTimer?.cancel();
    _historicalDataTimer = null;
    print('📚 Periodic monitoring stopped');
  }

  void dispose() {
    _stopHistoricalDataSaving();
    _sensorController.close();
    _pumpController.close();
    print('🔥 Firebase service disposed');
  }
}