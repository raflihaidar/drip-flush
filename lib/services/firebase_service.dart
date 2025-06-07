import 'dart:async';
import 'dart:math' as math;
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
        print('📊 Creating initial multi-sensor data...');
        await _createInitialSensorData();
      } else {
        // Check if existing data needs migration to multi-sensor format
        await _migrateToMultiSensorIfNeeded();
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

  Future<void> _migrateToMultiSensorIfNeeded() async {
    try {
      print('🔄 [MIGRATION] Checking if migration to multi-sensor format is needed...');
      
      final sensorSnapshot = await _database.child('greenhouse_data/current_sensor').get();
      if (sensorSnapshot.exists && sensorSnapshot.value != null) {
        final data = Map<String, dynamic>.from(sensorSnapshot.value as Map);
        
        // Check if data is in old single-sensor format
        if (data.containsKey('sensor') && data['sensor'] is Map) {
          final sensorData = data['sensor'] as Map;
          
          // If it has soil_sensor but not soil_sensor_1 and soil_sensor_2, migrate
          if (sensorData.containsKey('soil_sensor') && 
              !sensorData.containsKey('soil_sensor_1') && 
              !sensorData.containsKey('soil_sensor_2')) {
            
            print('🔄 [MIGRATION] Migrating single sensor to multi-sensor format...');
            
            final oldSensorData = sensorData['soil_sensor'] as Map;
            final oldValue = oldSensorData['value'] ?? 50.0;
            
            // Create new multi-sensor structure
            final newSensorData = {
              "sensor": {
                "soil_sensor_1": {
                  "value": oldValue,
                  "sensor_id": "sensor_1",
                  "is_active": true,
                  "last_update": DateTime.now().toIso8601String(),
                },
                "soil_sensor_2": {
                  "value": 0.0, // Default for new sensor
                  "sensor_id": "sensor_2", 
                  "is_active": false,
                  "last_update": DateTime.now().toIso8601String(),
                }
              },
              "timestamp": DateTime.now().millisecondsSinceEpoch,
              "updated_at": DateTime.now().toIso8601String(),
            };
            
            await _database.child('greenhouse_data/current_sensor').set(newSensorData);
            print('✅ [MIGRATION] Migration completed successfully');
          } else {
            print('✅ [MIGRATION] Data already in multi-sensor format or migration not needed');
          }
        }
      }
    } catch (e) {
      print('❌ [MIGRATION] Error during migration: $e');
    }
  }

  Future<void> _createInitialSensorData() async {
    final sensorData = {
      "sensor": {
        "soil_sensor_1": {
          "value": 55.0,
          "sensor_id": "sensor_1",
          "is_active": true,
          "last_update": DateTime.now().toIso8601String(),
        },
        "soil_sensor_2": {
          "value": 62.0,
          "sensor_id": "sensor_2",
          "is_active": true,
          "last_update": DateTime.now().toIso8601String(),
        }
      },
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "updated_at": DateTime.now().toIso8601String(),
    };

    await _database.child('greenhouse_data/current_sensor').set(sensorData);
    
    // Also add to history
    await _addSensorDataToHistory(sensorData);
    
    print('✅ Initial multi-sensor data created: Sensor1=55.0%, Sensor2=62.0%');
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
            print('✅ Multi-sensor parsed:');
            print('   Sensor 1: ${sensorData.sensor.soilSensor1.value}% - ${sensorData.sensor.soilSensor1.condition}');
            print('   Sensor 2: ${sensorData.sensor.soilSensor2.value}% - ${sensorData.sensor.soilSensor2.condition}');
            print('   Average: ${sensorData.sensor.averageHumidity.toStringAsFixed(1)}% - ${sensorData.sensor.overallCondition}');
            
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

  // ENHANCED: Add sensor data to history with multi-sensor support
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
      
      // Also maintain daily summaries for easier querying (enhanced for multi-sensor)
      await _updateDailySensorSummary(now, sensorData);
      
      print('📚 Multi-sensor data added to history: ${historyEntry['id']}');
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

  // ENHANCED: Update daily sensor summary for multi-sensor analytics
  Future<void> _updateDailySensorSummary(DateTime date, Map<String, dynamic> sensorData) async {
    try {
      final dateKey = _getDateKey(date);
      
      // Update summary for each sensor separately
      await _updateSensorSummary(dateKey, date, sensorData, 'sensor_1');
      await _updateSensorSummary(dateKey, date, sensorData, 'sensor_2');
      
      // Also update combined summary
      await _updateCombinedSensorSummary(dateKey, date, sensorData);
      
    } catch (e) {
      print('❌ Error updating daily sensor summary: $e');
    }
  }

  Future<void> _updateSensorSummary(String dateKey, DateTime date, Map<String, dynamic> sensorData, String sensorId) async {
    try {
      final summaryRef = _database.child('greenhouse_data/daily_summaries/$sensorId/$dateKey');
      
      final currentSummary = await summaryRef.get();
      Map<String, dynamic> summary;
      
      if (currentSummary.exists && currentSummary.value != null) {
        summary = Map<String, dynamic>.from(currentSummary.value as Map);
      } else {
        summary = {
          'date': dateKey,
          'sensor_id': sensorId,
          'first_reading': date.toIso8601String(),
          'count': 0,
          'values': <double>[],
          'min_value': double.infinity,
          'max_value': double.negativeInfinity,
          'total_value': 0.0,
        };
      }
      
      // Extract sensor value for specific sensor
      double? sensorValue;
      final sensor = (sensorData['sensor'] as Map?);
      if (sensor != null) {
        final sensorKey = sensorId == 'sensor_1' ? 'soil_sensor_1' : 'soil_sensor_2';
        final specificSensor = (sensor[sensorKey] as Map?);
        if (specificSensor != null) {
          sensorValue = (specificSensor['value'] as num?)?.toDouble();
        }
      }
      
      if (sensorValue != null && sensorValue > 0) {
        // Update summary
        summary['count'] = (summary['count'] ?? 0) + 1;
        summary['last_reading'] = date.toIso8601String();
        summary['total_value'] = (summary['total_value'] ?? 0.0) + sensorValue;
        summary['average_value'] = (summary['total_value'] as double) / (summary['count'] as int);
        
        if (sensorValue < (summary['min_value'] as double)) {
          summary['min_value'] = sensorValue;
        }
        if (sensorValue > (summary['max_value'] as double)) {
          summary['max_value'] = sensorValue;
        }
        
        // Keep recent values (last 10)
        final values = List<double>.from(summary['values'] ?? []);
        values.add(sensorValue);
        if (values.length > 10) {
          values.removeAt(0);
        }
        summary['values'] = values;
        
        await summaryRef.set(summary);
        print('📊 Daily $sensorId summary updated for $dateKey');
      }
    } catch (e) {
      print('❌ Error updating $sensorId summary: $e');
    }
  }

  Future<void> _updateCombinedSensorSummary(String dateKey, DateTime date, Map<String, dynamic> sensorData) async {
    try {
      final summaryRef = _database.child('greenhouse_data/daily_summaries/combined/$dateKey');
      
      final currentSummary = await summaryRef.get();
      Map<String, dynamic> summary;
      
      if (currentSummary.exists && currentSummary.value != null) {
        summary = Map<String, dynamic>.from(currentSummary.value as Map);
      } else {
        summary = {
          'date': dateKey,
          'first_reading': date.toIso8601String(),
          'count': 0,
          'sensor1_values': <double>[],
          'sensor2_values': <double>[],
          'combined_values': <double>[],
          'min_value': double.infinity,
          'max_value': double.negativeInfinity,
          'total_value': 0.0,
        };
      }
      
      // Extract values for both sensors
      final sensor = (sensorData['sensor'] as Map?);
      double? sensor1Value, sensor2Value;
      
      if (sensor != null) {
        final sensor1Data = (sensor['soil_sensor_1'] as Map?);
        final sensor2Data = (sensor['soil_sensor_2'] as Map?);
        
        if (sensor1Data != null) {
          sensor1Value = (sensor1Data['value'] as num?)?.toDouble();
        }
        if (sensor2Data != null) {
          sensor2Value = (sensor2Data['value'] as num?)?.toDouble();
        }
      }
      
      if (sensor1Value != null && sensor2Value != null) {
        final averageValue = (sensor1Value + sensor2Value) / 2;
        
        // Update summary
        summary['count'] = (summary['count'] ?? 0) + 1;
        summary['last_reading'] = date.toIso8601String();
        summary['total_value'] = (summary['total_value'] ?? 0.0) + averageValue;
        summary['average_value'] = (summary['total_value'] as double) / (summary['count'] as int);
        
        if (averageValue < (summary['min_value'] as double)) {
          summary['min_value'] = averageValue;
        }
        if (averageValue > (summary['max_value'] as double)) {
          summary['max_value'] = averageValue;
        }
        
        // Keep recent values for all sensors
        final sensor1Values = List<double>.from(summary['sensor1_values'] ?? []);
        final sensor2Values = List<double>.from(summary['sensor2_values'] ?? []);
        final combinedValues = List<double>.from(summary['combined_values'] ?? []);
        
        sensor1Values.add(sensor1Value);
        sensor2Values.add(sensor2Value);
        combinedValues.add(averageValue);
        
        if (sensor1Values.length > 10) sensor1Values.removeAt(0);
        if (sensor2Values.length > 10) sensor2Values.removeAt(0);
        if (combinedValues.length > 10) combinedValues.removeAt(0);
        
        summary['sensor1_values'] = sensor1Values;
        summary['sensor2_values'] = sensor2Values;
        summary['combined_values'] = combinedValues;
        
        await summaryRef.set(summary);
        print('📊 Daily combined summary updated for $dateKey');
      }
    } catch (e) {
      print('❌ Error updating combined summary: $e');
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

  // ENHANCED: Update sensor data with multi-sensor support
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
      
      print('✅ Multi-sensor data updated and added to history:');
      print('   Sensor 1: ${data.sensor.soilSensor1.value}%');
      print('   Sensor 2: ${data.sensor.soilSensor2.value}%');
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
      await _addPumpDataToHistory(firebaseData);
      
      print('✅ Pump status updated and added to history: ${status.pump.waterPump.isActive ? "ON" : "OFF"}');
    } catch (e) {
      print('❌ Error updating pump status: $e');
      rethrow;
    }
  }

  // ENHANCED: Get sensor history data with multi-sensor support
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

  // ENHANCED: Get daily summaries with sensor selection
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

  // NEW: Get specific sensor summary
  Future<Map<String, dynamic>?> getSensorSummary(String sensorId, String dateKey) async {
    return await getDailySummary(sensorId, dateKey);
  }

  // NEW: Get combined sensor summary
  Future<Map<String, dynamic>?> getCombinedSensorSummary(String dateKey) async {
    return await getDailySummary('combined', dateKey);
  }

  // ENHANCED: Get sensor data with migration support
  Future<SensorData?> getSensorData() async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return null;
    }

    try {
      print('🔍 Fetching multi-sensor data...');
      final snapshot = await _database.child('greenhouse_data/current_sensor').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print('📊 Retrieved sensor data: $data');
        
        final sensorData = SensorData.fromFirebase(data);
        print('✅ Multi-sensor data:');
        print('   Sensor 1: ${sensorData.sensor.soilSensor1.value}%');
        print('   Sensor 2: ${sensorData.sensor.soilSensor2.value}%');
        return sensorData;
      } else {
        print('⚠️ No sensor data found, creating default multi-sensor...');
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

  // Get pump status (unchanged)
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

  // ENHANCED: Quick update methods for testing with multi-sensor
  Future<void> updateSensorValue(double value, {String sensorId = 'sensor_1'}) async {
    if (!_isInitialized) return;

    try {
      // Get current data first
      final currentData = await getSensorData();
      
      SensorData newData;
      if (currentData != null) {
        // Update specific sensor
        if (sensorId == 'sensor_1') {
          newData = SensorData(
            sensor: currentData.sensor.copyWith(
              soilSensor1: currentData.sensor.soilSensor1.copyWith(
                value: value,
                lastUpdate: DateTime.now(),
              ),
            ),
          );
        } else {
          newData = SensorData(
            sensor: currentData.sensor.copyWith(
              soilSensor2: currentData.sensor.soilSensor2.copyWith(
                value: value,
                lastUpdate: DateTime.now(),
              ),
            ),
          );
        }
      } else {
        // Create new data
        newData = SensorData(
          sensor: Sensor(
            soilSensor1: SoilSensor(
              value: sensorId == 'sensor_1' ? value : 0.0,
              sensorId: 'sensor_1',
            ),
            soilSensor2: SoilSensor(
              value: sensorId == 'sensor_2' ? value : 0.0,
              sensorId: 'sensor_2',
            ),
          ),
        );
      }
      
      await updateSensorData(newData);
      print('🧪 Test $sensorId value updated: ${value}%');
    } catch (e) {
      print('❌ Error updating test sensor value: $e');
    }
  }

  Future<void> updateBothSensors(double sensor1Value, double sensor2Value) async {
    if (!_isInitialized) return;

    try {
      final sensorData = SensorData(
        sensor: Sensor(
          soilSensor1: SoilSensor(
            value: sensor1Value,
            sensorId: 'sensor_1',
            lastUpdate: DateTime.now(),
            isActive: true,
          ),
          soilSensor2: SoilSensor(
            value: sensor2Value,
            sensorId: 'sensor_2',
            lastUpdate: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      
      await updateSensorData(sensorData);
      print('🧪 Test both sensors updated: Sensor1=${sensor1Value}%, Sensor2=${sensor2Value}%');
    } catch (e) {
      print('❌ Error updating both test sensors: $e');
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

  // Auto watering settings (enhanced for multi-sensor)
  Future<void> updateAutoWateringSettings(Map<String, dynamic> settings) async {
    if (!_isInitialized) return;

    try {
      settings['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      settings['updated_at'] = DateTime.now().toIso8601String();
      
      // Ensure multi-sensor settings structure
      if (!settings.containsKey('individual_sensor_thresholds')) {
        settings['individual_sensor_thresholds'] = {
          'sensor_1': {
            'min_threshold': settings['min_humidity_threshold'] ?? 35.0,
            'max_threshold': settings['max_humidity_threshold'] ?? 75.0,
            'weight': 0.6,
            'is_enabled': true,
          },
          'sensor_2': {
            'min_threshold': settings['min_humidity_threshold'] ?? 40.0,
            'max_threshold': settings['max_humidity_threshold'] ?? 70.0,
            'weight': 0.4,
            'is_enabled': true,
          },
        };
      }
      
      if (!settings.containsKey('sensor_priority')) {
        settings['sensor_priority'] = 'average'; // 'average', 'sensor_1', 'sensor_2', 'worst_case'
      }
      
      await _database.child('greenhouse_data/auto_watering_settings').set(settings);
      print('✅ Multi-sensor auto watering settings updated');
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
        final settings = Map<String, dynamic>.from(snapshot.value as Map);
        
        // Migrate old settings to multi-sensor format if needed
        if (!settings.containsKey('individual_sensor_thresholds')) {
          print('🔄 [AUTO_WATERING] Migrating to multi-sensor auto watering settings...');
          
          settings['individual_sensor_thresholds'] = {
            'sensor_1': {
              'min_threshold': settings['min_humidity_threshold'] ?? 35.0,
              'max_threshold': settings['max_humidity_threshold'] ?? 75.0,
              'weight': 0.6,
              'is_enabled': true,
            },
            'sensor_2': {
              'min_threshold': settings['min_humidity_threshold'] ?? 40.0,
              'max_threshold': settings['max_humidity_threshold'] ?? 70.0,
              'weight': 0.4,
              'is_enabled': true,
            },
          };
          
          settings['sensor_priority'] = settings['sensor_priority'] ?? 'average';
          
          // Save migrated settings
          await updateAutoWateringSettings(settings);
        }
        
        return settings;
      }
      return null;
    } catch (e) {
      print('❌ Error getting auto watering settings: $e');
      return null;
    }
  }

  // NEW: Multi-sensor analytics methods
  Future<Map<String, dynamic>> getMultiSensorAnalytics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!_isInitialized) return {};

    try {
      final sensor1History = await getSensorHistory(startDate: startDate, endDate: endDate);
      final sensor2History = await getSensorHistory(startDate: startDate, endDate: endDate);
      
      // Extract sensor-specific data
      final sensor1Values = <double>[];
      final sensor2Values = <double>[];
      final timestamps = <DateTime>[];
      
      for (final entry in sensor1History) {
        if (entry['sensor'] != null) {
          final sensor = entry['sensor'] as Map;
          final sensor1Data = sensor['soil_sensor_1'] as Map?;
          final sensor2Data = sensor['soil_sensor_2'] as Map?;
          
          if (sensor1Data != null && sensor1Data['value'] != null) {
            sensor1Values.add((sensor1Data['value'] as num).toDouble());
          }
          
          if (sensor2Data != null && sensor2Data['value'] != null) {
            sensor2Values.add((sensor2Data['value'] as num).toDouble());
          }
          
          if (entry['timestamp'] != null) {
            timestamps.add(DateTime.fromMillisecondsSinceEpoch(entry['timestamp']));
          }
        }
      }
      
      return {
        'sensor_1': {
          'values': sensor1Values,
          'count': sensor1Values.length,
          'average': sensor1Values.isNotEmpty ? sensor1Values.reduce((a, b) => a + b) / sensor1Values.length : 0.0,
          'min': sensor1Values.isNotEmpty ? sensor1Values.reduce((a, b) => a < b ? a : b) : 0.0,
          'max': sensor1Values.isNotEmpty ? sensor1Values.reduce((a, b) => a > b ? a : b) : 0.0,
        },
        'sensor_2': {
          'values': sensor2Values,
          'count': sensor2Values.length,
          'average': sensor2Values.isNotEmpty ? sensor2Values.reduce((a, b) => a + b) / sensor2Values.length : 0.0,
          'min': sensor2Values.isNotEmpty ? sensor2Values.reduce((a, b) => a < b ? a : b) : 0.0,
          'max': sensor2Values.isNotEmpty ? sensor2Values.reduce((a, b) => a > b ? a : b) : 0.0,
        },
        'combined': {
          'correlation': _calculateCorrelation(sensor1Values, sensor2Values),
          'difference_avg': _calculateAverageDifference(sensor1Values, sensor2Values),
          'timestamps': timestamps.map((t) => t.toIso8601String()).toList(),
        },
        'period': {
          'start': startDate.toIso8601String(),
          'end': endDate.toIso8601String(),
          'days': endDate.difference(startDate).inDays,
        },
      };
    } catch (e) {
      print('❌ Error getting multi-sensor analytics: $e');
      return {};
    }
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return 0.0;
    
    final n = x.length;
    final meanX = x.reduce((a, b) => a + b) / n;
    final meanY = y.reduce((a, b) => a + b) / n;
    
    double numerator = 0.0;
    double denomX = 0.0;
    double denomY = 0.0;
    
    for (int i = 0; i < n; i++) {
      final diffX = x[i] - meanX;
      final diffY = y[i] - meanY;
      numerator += diffX * diffY;
      denomX += diffX * diffX;
      denomY += diffY * diffY;
    }
    
    if (denomX == 0 || denomY == 0) return 0.0;
    
    return numerator / (math.sqrt(denomX) * math.sqrt(denomY));
  }

  double _calculateAverageDifference(List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return 0.0;
    
    double totalDiff = 0.0;
    for (int i = 0; i < x.length; i++) {
      totalDiff += (x[i] - y[i]).abs();
    }
    
    return totalDiff / x.length;
  }

  // NEW: Sensor calibration methods
  Future<void> calibrateSensor(String sensorId, double actualValue, double measuredValue) async {
    if (!_isInitialized) return;

    try {
      final calibrationRef = _database.child('greenhouse_data/sensor_calibration/$sensorId');
      
      final calibrationData = {
        'actual_value': actualValue,
        'measured_value': measuredValue,
        'calibration_factor': actualValue / measuredValue,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await calibrationRef.set(calibrationData);
      print('✅ Sensor $sensorId calibrated: factor=${calibrationData['calibration_factor']}');
    } catch (e) {
      print('❌ Error calibrating sensor $sensorId: $e');
    }
  }

  Future<double?> getSensorCalibrationFactor(String sensorId) async {
    if (!_isInitialized) return null;

    try {
      final snapshot = await _database.child('greenhouse_data/sensor_calibration/$sensorId').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return (data['calibration_factor'] as num?)?.toDouble();
      }
      return null;
    } catch (e) {
      print('❌ Error getting calibration factor for $sensorId: $e');
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
    } else if (sensorType == 'pump') {
      return await getPumpHistory(startDate: startDate, endDate: endDate);
    }
    return [];
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
      
      print('🧹 Cleanup check for data older than ${cutoffDate.toIso8601String()}');
      
      // Clean up sensor history
      final sensorHistorySnapshot = await _database.child('greenhouse_data/sensor_history').get();
      if (sensorHistorySnapshot.exists && sensorHistorySnapshot.value != null) {
        final historyData = Map<String, dynamic>.from(sensorHistorySnapshot.value as Map);
        int deletedCount = 0;
        
        for (final entry in historyData.entries) {
          final entryData = entry.value as Map;
          final timestamp = entryData['timestamp'] as int?;
          
          if (timestamp != null) {
            final entryDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            if (entryDate.isBefore(cutoffDate)) {
              await _database.child('greenhouse_data/sensor_history/${entry.key}').remove();
              deletedCount++;
            }
          }
        }
        
        if (deletedCount > 0) {
          print('🧹 Cleaned up $deletedCount old sensor history entries');
        }
      }
      
      // Clean up pump history
      final pumpHistorySnapshot = await _database.child('greenhouse_data/pump_history').get();
      if (pumpHistorySnapshot.exists && pumpHistorySnapshot.value != null) {
        final historyData = Map<String, dynamic>.from(pumpHistorySnapshot.value as Map);
        int deletedCount = 0;
        
        for (final entry in historyData.entries) {
          final entryData = entry.value as Map;
          final timestamp = entryData['timestamp'] as int?;
          
          if (timestamp != null) {
            final entryDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            if (entryDate.isBefore(cutoffDate)) {
              await _database.child('greenhouse_data/pump_history/${entry.key}').remove();
              deletedCount++;
            }
          }
        }
        
        if (deletedCount > 0) {
          print('🧹 Cleaned up $deletedCount old pump history entries');
        }
      }
      
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

  // NEW: Health check methods
  Future<Map<String, dynamic>> getSystemHealth() async {
    if (!_isInitialized) {
      return {'status': 'not_initialized', 'issues': ['Firebase not initialized']};
    }

    try {
      final issues = <String>[];
      final checks = <String, bool>{};
      
      // Check sensor data
      final sensorData = await getSensorData();
      checks['sensor_data_available'] = sensorData != null;
      if (sensorData == null) {
        issues.add('No sensor data available');
      } else {
        checks['sensor_1_active'] = sensorData.sensor.soilSensor1.isActive;
        checks['sensor_2_active'] = sensorData.sensor.soilSensor2.isActive;
        
        if (!sensorData.sensor.soilSensor1.isActive) {
          issues.add('Sensor 1 is inactive');
        }
        if (!sensorData.sensor.soilSensor2.isActive) {
          issues.add('Sensor 2 is inactive');
        }
      }
      
      // Check pump data
      final pumpData = await getPumpStatus();
      checks['pump_data_available'] = pumpData != null;
      if (pumpData == null) {
        issues.add('No pump data available');
      }
      
      // Check recent activity
      final recentHistory = await getSensorHistory(limit: 5);
      checks['recent_activity'] = recentHistory.isNotEmpty;
      if (recentHistory.isEmpty) {
        issues.add('No recent sensor activity');
      }
      
      return {
        'status': issues.isEmpty ? 'healthy' : 'issues_found',
        'checks': checks,
        'issues': issues,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'error',
        'issues': ['Health check failed: $e'],
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}