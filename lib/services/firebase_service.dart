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
      // Firebase sudah diinisialisasi di main.dart, jadi skip initializeApp
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;

      print('🔥 Firebase service initialized');
      
      // Debug existing data
      await _debugExistingData();
      
      // Ensure required data exists
      await _ensureDataExists();

      // Setup real-time listeners
      _setupListeners();

      // Start auto-saving historical data
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
      
      // Check greenhouse_data
      final mainSnapshot = await _database.child('greenhouse_data').get();
      print('📂 greenhouse_data exists: ${mainSnapshot.exists}');
      
      if (mainSnapshot.exists) {
        // Check current_sensor
        final sensorSnapshot = await _database.child('greenhouse_data/current_sensor').get();
        print('📊 current_sensor exists: ${sensorSnapshot.exists}');
        if (sensorSnapshot.exists) {
          print('📊 current_sensor data: ${sensorSnapshot.value}');
        }
        
        // Check current_pump
        final pumpSnapshot = await _database.child('greenhouse_data/current_pump').get();
        print('🔧 current_pump exists: ${pumpSnapshot.exists}');
        if (pumpSnapshot.exists) {
          print('🔧 current_pump data: ${pumpSnapshot.value}');
        }
      }
      
      print('🔍 === END DATA CHECK ===');
    } catch (e) {
      print('❌ Debug error: $e');
    }
  }

  Future<void> _ensureDataExists() async {
    try {
      // Check and create sensor data if needed
      final sensorSnapshot = await _database.child('greenhouse_data/current_sensor').get();
      if (!sensorSnapshot.exists) {
        print('📊 Creating initial sensor data...');
        await _createInitialSensorData();
      }

      // Check and create pump data if needed  
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
        
        // Try again after creating data
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
        
        // Try again after creating data
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

  Future<void> updateSensorData(SensorData data) async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return;
    }

    try {
      final firebaseData = data.toFirebase();
      firebaseData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      firebaseData['updated_at'] = DateTime.now().toIso8601String();
      
      await _database.child('greenhouse_data/current_sensor').set(firebaseData);
      print('✅ Sensor data updated: ${data.sensor.soilSensor.value}%');
    } catch (e) {
      print('❌ Error updating sensor data: $e');
      rethrow;
    }
  }

  Future<void> updatePumpStatus(PumpStatus status) async {
    if (!_isInitialized) {
      print('❌ Firebase not initialized');
      return;
    }

    try {
      final firebaseData = status.toFirebase();
      firebaseData['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      firebaseData['updated_at'] = DateTime.now().toIso8601String();
      
      await _database.child('greenhouse_data/current_pump').set(firebaseData);
      print('✅ Pump status updated: ${status.pump.waterPump.isActive ? "ON" : "OFF"}');
    } catch (e) {
      print('❌ Error updating pump status: $e');
      rethrow;
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

  // Auto watering settings
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

  // Historical data
  Future<List<Map<String, dynamic>>> getHistoricalData({
    required String sensorType,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!_isInitialized) return [];

    try {
      String path = sensorType == 'sensor' ? 'history/sensor_data' : 'history/pump_data';

      final snapshot = await _database
          .child(path)
          .orderByChild('timestamp')
          .startAt(startDate.millisecondsSinceEpoch)
          .endAt(endDate.millisecondsSinceEpoch)
          .get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      }
      return [];
    } catch (e) {
      print('❌ Error getting historical data: $e');
      return [];
    }
  }

  Future<void> saveHistoricalSensorData(SensorData data) async {
    if (!_isInitialized) return;

    try {
      final now = DateTime.now();
      final key = '${now.millisecondsSinceEpoch}';

      final historicalData = data.toFirebase();
      historicalData['timestamp'] = now.millisecondsSinceEpoch;
      historicalData['date'] = now.toIso8601String();
      historicalData['hour'] = now.hour;
      historicalData['day'] = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      await _database.child('history/sensor_data/$key').set(historicalData);
      print('📚 Historical sensor data saved');
    } catch (e) {
      print('❌ Error saving historical sensor data: $e');
    }
  }

  Future<void> saveHistoricalPumpData(PumpStatus status) async {
    if (!_isInitialized) return;

    try {
      final now = DateTime.now();
      final key = '${now.millisecondsSinceEpoch}';

      final historicalData = status.toFirebase();
      historicalData['timestamp'] = now.millisecondsSinceEpoch;
      historicalData['date'] = now.toIso8601String();
      historicalData['hour'] = now.hour;
      historicalData['day'] = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      await _database.child('history/pump_data/$key').set(historicalData);
      print('📚 Historical pump data saved');
    } catch (e) {
      print('❌ Error saving historical pump data: $e');
    }
  }

  // Auto-save historical data timer
  Timer? _historicalDataTimer;

  void _startHistoricalDataSaving() {
    // Save every 10 minutes for testing, change to 30 minutes for production
    _historicalDataTimer = Timer.periodic(Duration(minutes: 10), (timer) async {
      try {
        final sensorData = await getSensorData();
        if (sensorData != null) {
          await saveHistoricalSensorData(sensorData);
        }

        final pumpData = await getPumpStatus();
        if (pumpData != null) {
          await saveHistoricalPumpData(pumpData);
        }
      } catch (e) {
        print('❌ Error in historical data saving: $e');
      }
    });

    print('📚 Historical data auto-saving started (every 10 minutes)');
  }

  void _stopHistoricalDataSaving() {
    _historicalDataTimer?.cancel();
    _historicalDataTimer = null;
    print('📚 Historical data auto-saving stopped');
  }

  // Test methods
  // Future<void> runTests() async {
  //   print('🧪 === RUNNING FIREBASE TESTS ===');
    
  //   try {
  //     // Test sensor update
  //     await updateSensorValue(75.0);
  //     await Future.delayed(Duration(seconds: 1));
      
  //     // Test pump update
  //     await updatePumpActive(true);
  //     await Future.delayed(Duration(seconds: 1));
      
  //     // Test getting data
  //     final sensorData = await getSensorData();
  //     final pumpData = await getPumpStatus();
      
  //     print('🧪 Test sensor result: ${sensorData?.sensor.soilSensor.value}%');
  //     print('🧪 Test pump result: ${pumpData?.pump.waterPump.isActive}');
      
  //     print('✅ All tests completed');
  //   } catch (e) {
  //     print('❌ Test failed: $e');
  //   }
    
  //   print('🧪 === END TESTS ===');
  // }

  void dispose() {
    _stopHistoricalDataSaving();
    _sensorController.close();
    _pumpController.close();
    print('🔥 Firebase service disposed');
  }
}