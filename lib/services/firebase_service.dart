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
      await Firebase.initializeApp();
      _database = FirebaseDatabase.instance.ref();
      _isInitialized = true;

      _setupListeners();
      
      // Start auto-saving historical data
      startHistoricalDataSaving();
      
      print('Firebase initialized successfully');
    } catch (e) {
      print('Firebase initialization error: $e');
      rethrow;
    }
  }

  void _setupListeners() {
    // Listen to sensor data changes
    _database.child('sensors/soil_temperature').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final sensorData = SensorData.fromFirebase(data);
          _sensorController.add(sensorData);
        } catch (e) {
          print('Error parsing sensor data: $e');
        }
      }
    });

    // Listen to pump status changes
    _database.child('pump/status').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final pumpStatus = PumpStatus.fromFirebase(data);
          _pumpController.add(pumpStatus);
        } catch (e) {
          print('Error parsing pump status: $e');
        }
      }
    });
  }

  Future<SensorData?> getSensorData() async {
    if (!_isInitialized) {
      print('Firebase not initialized');
      return null;
    }

    try {
      final snapshot = await _database.child('sensors/soil_temperature').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return SensorData.fromFirebase(data);
      }
      return null;
    } catch (e) {
      print('Error getting sensor data: $e');
      return null;
    }
  }

  Future<PumpStatus?> getPumpStatus() async {
    if (!_isInitialized) {
      print('Firebase not initialized');
      return null;
    }

    try {
      final snapshot = await _database.child('pump/status').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return PumpStatus.fromFirebase(data);
      }
      return null;
    } catch (e) {
      print('Error getting pump status: $e');
      return null;
    }
  }

  Future<void> updateSensorData(SensorData data) async {
    if (!_isInitialized) {
      print('Firebase not initialized');
      return;
    }

    try {
      await _database.child('sensors/soil_temperature').set(data.toFirebase());
      print('Sensor data updated in Firebase');
    } catch (e) {
      print('Error updating sensor data: $e');
      rethrow;
    }
  }

  Future<void> updatePumpStatus(PumpStatus status) async {
    if (!_isInitialized) {
      print('Firebase not initialized');
      return;
    }

    try {
      await _database.child('pump/status').set(status.toFirebase());
      print('Pump status updated in Firebase');
    } catch (e) {
      print('Error updating pump status: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getHistoricalData({
    required String sensorType,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!_isInitialized) {
      print('Firebase not initialized');
      return [];
    }

    try {
      final snapshot = await _database
          .child('history/$sensorType')
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
      print('Error getting historical data: $e');
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

      await _database
          .child('history/soil_temperature/$key')
          .set(historicalData);

      print('Historical sensor data saved');
    } catch (e) {
      print('Error saving historical sensor data: $e');
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

      await _database
          .child('history/pump_status/$key')
          .set(historicalData);

      print('Historical pump data saved');
    } catch (e) {
      print('Error saving historical pump data: $e');
    }
  }

  // Auto-save historical data timer
  Timer? _historicalDataTimer;

  void startHistoricalDataSaving() {
    // Save every 5 minutes
    _historicalDataTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      try {
        // Save current sensor data to history
        final sensorData = await getSensorData();
        if (sensorData != null) {
          await saveHistoricalSensorData(sensorData);
        }

        // Save current pump status to history
        final pumpData = await getPumpStatus();
        if (pumpData != null) {
          await saveHistoricalPumpData(pumpData);
        }
      } catch (e) {
        print('Error in historical data saving: $e');
      }
    });

    print('Historical data auto-saving started');
  }

  void stopHistoricalDataSaving() {
    _historicalDataTimer?.cancel();
    _historicalDataTimer = null;
    print('Historical data auto-saving stopped');
  }

  // Clean old historical data (older than 30 days)
  Future<void> cleanOldHistoricalData() async {
    if (!_isInitialized) return;

    try {
      final thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30));
      final cutoffTimestamp = thirtyDaysAgo.millisecondsSinceEpoch;

      // Clean old sensor data
      final sensorSnapshot = await _database
          .child('history/soil_temperature')
          .orderByChild('timestamp')
          .endAt(cutoffTimestamp)
          .get();

      if (sensorSnapshot.exists && sensorSnapshot.value != null) {
        final data = Map<String, dynamic>.from(sensorSnapshot.value as Map);
        for (String key in data.keys) {
          await _database.child('history/soil_temperature/$key').remove();
        }
      }

      // Clean old pump data
      final pumpSnapshot = await _database
          .child('history/pump_status')
          .orderByChild('timestamp')
          .endAt(cutoffTimestamp)
          .get();

      if (pumpSnapshot.exists && pumpSnapshot.value != null) {
        final data = Map<String, dynamic>.from(pumpSnapshot.value as Map);
        for (String key in data.keys) {
          await _database.child('history/pump_status/$key').remove();
        }
      }

      print('Old historical data cleaned');
    } catch (e) {
      print('Error cleaning old historical data: $e');
    }
  }

  // Get device status
  Future<Map<String, dynamic>> getDeviceStatus() async {
    if (!_isInitialized) return {};

    try {
      final snapshot = await _database.child('device/status').get();
      if (snapshot.exists && snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return {};
    } catch (e) {
      print('Error getting device status: $e');
      return {};
    }
  }

  // Update device status
  Future<void> updateDeviceStatus(Map<String, dynamic> status) async {
    if (!_isInitialized) return;

    try {
      status['last_updated'] = DateTime.now().millisecondsSinceEpoch;
      await _database.child('device/status').set(status);
      print('Device status updated');
    } catch (e) {
      print('Error updating device status: $e');
    }
  }

  void dispose() {
    stopHistoricalDataSaving();
    _sensorController.close();
    _pumpController.close();
  }
}