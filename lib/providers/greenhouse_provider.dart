import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/sensor_data.dart';
import '../models/pump_status.dart';
import '../services/mqtt_service.dart';
import '../services/firebase_service.dart';

class GreenhouseProvider with ChangeNotifier {
  // Services
  late MqttService _mqttService;
  late FirebaseService _firebaseService;

  // State variables
  SensorData? _sensorData;
  PumpStatus? _pumpStatus;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Enhanced auto-save settings
  bool _autoSaveToFirebase = true;
  DateTime? _lastSensorUpdate;
  DateTime? _lastPumpUpdate;
  
  // Batching and throttling for Firebase saves
  Timer? _sensorSaveTimer;
  Timer? _pumpSaveTimer;
  SensorData? _pendingSensorData;
  PumpStatus? _pendingPumpData;
  
  // Configuration
  static const Duration _saveThrottleDuration = Duration(seconds: 2);
  static const Duration _reconnectDelay = Duration(seconds: 5);
  
  // Stream subscriptions for cleanup
  StreamSubscription<Map<String, dynamic>>? _mqttDataSubscription;
  StreamSubscription<SensorData>? _firebaseSensorSubscription;
  StreamSubscription<PumpStatus>? _firebasePumpSubscription;

  // Constructor
  GreenhouseProvider() {
    _mqttService = MqttService();
    _firebaseService = FirebaseService();
  }

  // Getters
  SensorData? get sensorData => _sensorData;
  PumpStatus? get pumpStatus => _pumpStatus;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get autoSaveToFirebase => _autoSaveToFirebase;
  DateTime? get lastSensorUpdate => _lastSensorUpdate;
  DateTime? get lastPumpUpdate => _lastPumpUpdate;
  
  // Enhanced getters for multi-sensor support
  double? get currentSoilHumidity => _sensorData?.sensor.averageHumidity;
  double? get sensor1Humidity => _sensorData?.sensor.soilSensor1.value;
  double? get sensor2Humidity => _sensorData?.sensor.soilSensor2.value;
  
  String? get sensor1Condition => _sensorData?.sensor.soilSensor1.condition;
  String? get sensor2Condition => _sensorData?.sensor.soilSensor2.condition;
  String? get overallCondition => _sensorData?.sensor.overallCondition;
  
  bool? get sensor1Active => _sensorData?.sensor.soilSensor1.isActive;
  bool? get sensor2Active => _sensorData?.sensor.soilSensor2.isActive;
  
  bool? get isPumpActive => _pumpStatus?.pump.waterPump.isActive;
  String? get currentPumpStatus => _pumpStatus?.pump.waterPump.isActive == true ? 'ON' : 'OFF';

  // Backward compatibility
  double? get currentSoilHumidityLegacy => sensor1Humidity; // For backward compatibility
  String? get soilCondition => overallCondition;

  Future<void> initialize() async {
    _setLoading(true);
    
    try {
      print('🚀 [INIT] Starting GreenhouseProvider initialization...');
      
      // Initialize Firebase first
      print('🔥 [INIT] Initializing Firebase...');
      await _firebaseService.initialize();
      print('✅ [INIT] Firebase initialized successfully');
      
      // Test Firebase connection
      print('🧪 [INIT] Testing Firebase connection...');
      final testData = await _firebaseService.getSensorData();
      print('📊 [INIT] Test data result: $testData');
      
      // Connect to MQTT
      print('📡 [INIT] Connecting to MQTT...');
      final mqttConnected = await _mqttService.prepareMqttClient();
      _isConnected = mqttConnected;
      print('📡 [INIT] MQTT connection status: $mqttConnected');
      
      if (mqttConnected) {
        await _setupMqttListener();
      } else {
        print('⚠️ [INIT] MQTT connection failed, will retry later');
        _scheduleReconnection();
      }
      
      // Setup Firebase listeners
      await _setupFirebaseListeners();
      
      // Load initial data from Firebase
      print('📚 [INIT] Loading initial data from Firebase...');
      await _loadInitialData();
      
      _clearError();
      print('🎉 [INIT] Initialization completed successfully');
      
    } catch (e) {
      print('💥 [INIT] Initialization error: $e');
      _setError('Initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ENHANCED MQTT LISTENER SETUP
  Future<void> _setupMqttListener() async {
    try {
      // Cancel existing subscription if any
      await _mqttDataSubscription?.cancel();
      
      // Setup new subscription with better error handling
      _mqttDataSubscription = _mqttService.dataStream.listen(
        (data) async {
          try {
            await _handleMqttDataEnhanced(data);
          } catch (e) {
            print('❌ [MQTT] Stream handler error: $e');
            _setError('MQTT data processing error: $e');
          }
        },
        onError: (error) {
          print('❌ [MQTT] Data stream error: $error');
          _setError('MQTT connection error: $error');
          _scheduleReconnection();
        },
        onDone: () {
          print('🔌 [MQTT] Data stream closed');
          _isConnected = false;
          notifyListeners();
          _scheduleReconnection();
        },
      );
      
      print('👂 [INIT] MQTT data stream listener setup complete');
    } catch (e) {
      print('❌ [MQTT] Error setting up listener: $e');
      throw e;
    }
  }

  // ENHANCED FIREBASE LISTENER SETUP
  Future<void> _setupFirebaseListeners() async {
    try {
      // Cancel existing subscriptions
      await _firebaseSensorSubscription?.cancel();
      await _firebasePumpSubscription?.cancel();
      
      // Setup sensor data listener
      _firebaseSensorSubscription = _firebaseService.sensorStream.listen(
        _handleFirebaseSensorData,
        onError: (error) {
          print('❌ [FIREBASE] Sensor stream error: $error');
          _setError('Firebase sensor error: $error');
        },
      );
      
      // Setup pump data listener
      _firebasePumpSubscription = _firebaseService.pumpStream.listen(
        _handleFirebasePumpData,
        onError: (error) {
          print('❌ [FIREBASE] Pump stream error: $error');
          _setError('Firebase pump error: $error');
        },
      );
      
      print('👂 [INIT] Firebase stream listeners setup complete');
    } catch (e) {
      print('❌ [FIREBASE] Error setting up listeners: $e');
      throw e;
    }
  }

  // ENHANCED MQTT DATA HANDLER WITH MULTI-SENSOR SUPPORT
  Future<void> _handleMqttDataEnhanced(Map<String, dynamic> data) async {
    try {
      final topic = data['topic'] as String;
      print('📨 [MQTT] Handling data from topic: $topic');
      print('📝 [MQTT] Raw data: $data');
      
      if (_isDataValid(data)) {
        if (topic.contains('sensors/data') || topic.contains('sensor')) {
          await _processSensorDataFromMqtt(data);
        } else if (topic.contains('pump/status') || topic.contains('pump')) {
          await _processPumpDataFromMqtt(data);
        } else {
          print('⚠️ [MQTT] Unknown topic: $topic');
        }
      } else {
        print('⚠️ [MQTT] Invalid data received: $data');
      }
    } catch (e) {
      print('❌ [MQTT] Error handling MQTT data: $e');
      _setError('MQTT data processing error: $e');
    }
  }

  // ENHANCED SENSOR DATA PROCESSING WITH MULTI-SENSOR SUPPORT
  Future<void> _processSensorDataFromMqtt(Map<String, dynamic> data) async {
    try {
      print('🌱 [MQTT→SENSOR] Processing sensor data...');
      
      // Extract sensor values for both sensors
      final sensor1Value = _extractSensorValue(data, 'sensor_1');
      final sensor2Value = _extractSensorValue(data, 'sensor_2');
      
      if (sensor1Value == null && sensor2Value == null) {
        print('⚠️ [MQTT→SENSOR] No valid sensor values found in data');
        return;
      }
      
      print('📊 [MQTT→SENSOR] Extracted values - Sensor1: ${sensor1Value ?? "N/A"}%, Sensor2: ${sensor2Value ?? "N/A"}%');
      
      // Get current sensor data or create new one
      SensorData currentData = _sensorData ?? SensorData(sensor: Sensor.getDefault());
      
      // Update only the sensors that have new data
      SoilSensor newSensor1 = sensor1Value != null 
          ? currentData.sensor.soilSensor1.copyWith(
              value: sensor1Value,
              lastUpdate: DateTime.now(),
              isActive: true,
            )
          : currentData.sensor.soilSensor1;
          
      SoilSensor newSensor2 = sensor2Value != null 
          ? currentData.sensor.soilSensor2.copyWith(
              value: sensor2Value,
              lastUpdate: DateTime.now(),
              isActive: true,
            )
          : currentData.sensor.soilSensor2;
      
      // Create updated SensorData object
      final sensorData = SensorData(
        sensor: Sensor(
          soilSensor1: newSensor1,
          soilSensor2: newSensor2,
        ),
      );
      
      // Update local state immediately for responsive UI
      _sensorData = sensorData;
      _lastSensorUpdate = DateTime.now();
      print('✅ [MQTT→SENSOR] Local state updated:');
      print('   Sensor 1: ${newSensor1.value}% (${newSensor1.condition})');
      print('   Sensor 2: ${newSensor2.value}% (${newSensor2.condition})');
      print('   Average: ${sensorData.sensor.averageHumidity.toStringAsFixed(1)}% (${sensorData.sensor.overallCondition})');
      notifyListeners();
      
      // Queue for throttled Firebase save if auto-save is enabled
      if (_autoSaveToFirebase) {
        _queueSensorDataForFirebaseSave(sensorData);
      }
      
    } catch (e) {
      print('❌ [MQTT→SENSOR] Error processing sensor data: $e');
      throw e;
    }
  }

  // ENHANCED PUMP DATA PROCESSING WITH THROTTLED FIREBASE SAVE
  Future<void> _processPumpDataFromMqtt(Map<String, dynamic> data) async {
    try {
      print('🔧 [MQTT→PUMP] Processing pump data...');
      
      // Extract pump status with validation
      final isActive = _extractPumpStatus(data);
      if (isActive == null) {
        print('⚠️ [MQTT→PUMP] No valid pump status found in data');
        return;
      }
      
      print('🔧 [MQTT→PUMP] Extracted status: ${isActive ? "ON" : "OFF"}');
      
      // Create PumpStatus object
      final pumpStatus = PumpStatus(
        pump: Pump(
          waterPump: WaterPump(isActive: isActive),
        ),
      );
      
      // Update local state immediately for responsive UI
      _pumpStatus = pumpStatus;
      _lastPumpUpdate = DateTime.now();
      print('✅ [MQTT→PUMP] Local state updated: ${pumpStatus.pump.waterPump.isActive ? "ON" : "OFF"}');
      notifyListeners();
      
      // Queue for throttled Firebase save if auto-save is enabled
      if (_autoSaveToFirebase) {
        _queuePumpDataForFirebaseSave(pumpStatus);
      }
      
    } catch (e) {
      print('❌ [MQTT→PUMP] Error processing pump data: $e');
      throw e;
    }
  }

  // THROTTLED FIREBASE SAVE FOR SENSOR DATA
  void _queueSensorDataForFirebaseSave(SensorData sensorData) {
    _pendingSensorData = sensorData;
    
    // Cancel existing timer if any
    _sensorSaveTimer?.cancel();
    
    // Start new timer for throttled save
    _sensorSaveTimer = Timer(_saveThrottleDuration, () async {
      if (_pendingSensorData != null) {
        try {
          print('💾 [MQTT→FIREBASE] Throttled save: Saving sensor data to Firebase...');
          await _firebaseService.updateSensorData(_pendingSensorData!);
          print('✅ [MQTT→FIREBASE] Sensor data saved successfully');
          _pendingSensorData = null;
        } catch (e) {
          print('❌ [MQTT→FIREBASE] Error saving sensor data: $e');
          // Don't throw error - local state is preserved
        }
      }
    });
  }

  // THROTTLED FIREBASE SAVE FOR PUMP DATA
  void _queuePumpDataForFirebaseSave(PumpStatus pumpStatus) {
    _pendingPumpData = pumpStatus;
    
    // Cancel existing timer if any
    _pumpSaveTimer?.cancel();
    
    // Start new timer for throttled save
    _pumpSaveTimer = Timer(_saveThrottleDuration, () async {
      if (_pendingPumpData != null) {
        try {
          print('💾 [MQTT→FIREBASE] Throttled save: Saving pump data to Firebase...');
          await _firebaseService.updatePumpStatus(_pendingPumpData!);
          print('✅ [MQTT→FIREBASE] Pump data saved successfully');
          _pendingPumpData = null;
        } catch (e) {
          print('❌ [MQTT→FIREBASE] Error saving pump data: $e');
          // Don't throw error - local state is preserved
        }
      }
    });
  }

  // FORCE IMMEDIATE FIREBASE SAVE (bypasses throttling)
  Future<void> forceImmediateFirebaseSave() async {
    try {
      print('🚀 [FORCE] Force saving all pending data to Firebase...');
      
      // Cancel timers and save immediately
      _sensorSaveTimer?.cancel();
      _pumpSaveTimer?.cancel();
      
      if (_pendingSensorData != null) {
        await _firebaseService.updateSensorData(_pendingSensorData!);
        print('✅ [FORCE] Pending sensor data saved');
        _pendingSensorData = null;
      }
      
      if (_pendingPumpData != null) {
        await _firebaseService.updatePumpStatus(_pendingPumpData!);
        print('✅ [FORCE] Pending pump data saved');
        _pendingPumpData = null;
      }
      
      // Also save current data if available
      if (_sensorData != null) {
        await _firebaseService.updateSensorData(_sensorData!);
        print('✅ [FORCE] Current sensor data saved');
      }
      
      if (_pumpStatus != null) {
        await _firebaseService.updatePumpStatus(_pumpStatus!);
        print('✅ [FORCE] Current pump data saved');
      }
      
      print('🎉 [FORCE] Force save completed');
    } catch (e) {
      print('❌ [FORCE] Force save error: $e');
      _setError('Force save failed: $e');
    }
  }

  // ENHANCED DATA VALIDATION HELPERS
  bool _isDataValid(Map<String, dynamic> data) {
    return data.isNotEmpty && data.containsKey('topic');
  }

  double? _extractSensorValue(Map<String, dynamic> data, String sensorId) {
    // Try different possible keys for sensor value with sensor ID
    final possibleKeys = [
      '${sensorId}_value',
      '${sensorId}_humidity', 
      '${sensorId}_moisture',
      'soil_humidity_$sensorId',
      'soil_moisture_$sensorId',
      'humidity_$sensorId',
      'value_$sensorId',
    ];
    
    // Also try generic keys if sensor_id is specified in data
    if (data.containsKey('sensor_id') && data['sensor_id'] == sensorId) {
      possibleKeys.addAll(['soil_humidity', 'soil_moisture', 'humidity', 'value']);
    }
    
    // If no sensor ID specified in topic, try to determine from data structure
    if (data.containsKey('sensors') && data['sensors'] is Map) {
      final sensors = data['sensors'] as Map;
      if (sensors.containsKey(sensorId)) {
        final sensorData = sensors[sensorId];
        if (sensorData is Map && sensorData.containsKey('value')) {
          final value = sensorData['value'];
          if (value is num) {
            final doubleValue = value.toDouble();
            if (doubleValue >= 0 && doubleValue <= 100) {
              return doubleValue;
            }
          }
        }
      }
    }
    
    for (final key in possibleKeys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (value is num) {
          final doubleValue = value.toDouble();
          // Validate range (0-100 for percentage)
          if (doubleValue >= 0 && doubleValue <= 100) {
            return doubleValue;
          }
        }
      }
    }
    
    // Fallback: if this is a generic sensor update, use for sensor_1
    if (sensorId == 'sensor_1') {
      final genericKeys = ['soil_humidity', 'soil_moisture', 'humidity', 'value'];
      for (final key in genericKeys) {
        if (data.containsKey(key)) {
          final value = data[key];
          if (value is num) {
            final doubleValue = value.toDouble();
            if (doubleValue >= 0 && doubleValue <= 100) {
              return doubleValue;
            }
          }
        }
      }
    }
    
    return null;
  }

  bool? _extractPumpStatus(Map<String, dynamic> data) {
    // Try different possible keys for pump status
    final boolKeys = ['active', 'is_active', 'isActive', 'pump_active'];
    final stringKeys = ['status', 'state', 'pump_status', 'pump_state'];
    
    // Check boolean keys first
    for (final key in boolKeys) {
      if (data.containsKey(key) && data[key] is bool) {
        return data[key] as bool;
      }
    }
    
    // Check string keys
    for (final key in stringKeys) {
      if (data.containsKey(key)) {
        final value = data[key].toString().toLowerCase();
        if (['on', 'true', 'active', '1'].contains(value)) {
          return true;
        } else if (['off', 'false', 'inactive', '0'].contains(value)) {
          return false;
        }
      }
    }
    
    return null;
  }

  // FIREBASE DATA HANDLERS
  void _handleFirebaseSensorData(SensorData data) {
    print('📨 [FIREBASE→SENSOR] Handling sensor data from Firebase: $data');
    // Only update if it's newer than our current data
    if (_lastSensorUpdate == null || 
        _lastSensorUpdate!.isBefore(DateTime.now().subtract(Duration(seconds: 1)))) {
      _sensorData = data;
      _lastSensorUpdate = DateTime.now();
      notifyListeners();
    }
  }

  void _handleFirebasePumpData(PumpStatus data) {
    print('📨 [FIREBASE→PUMP] Handling pump data from Firebase: $data');
    // Only update if it's newer than our current data
    if (_lastPumpUpdate == null || 
        _lastPumpUpdate!.isBefore(DateTime.now().subtract(Duration(seconds: 1)))) {
      _pumpStatus = data;
      _lastPumpUpdate = DateTime.now();
      notifyListeners();
    }
  }

  // RECONNECTION LOGIC
  void _scheduleReconnection() {
    Timer(_reconnectDelay, () async {
      if (!_isConnected) {
        print('🔄 [RECONNECT] Attempting MQTT reconnection...');
        try {
          final connected = await _mqttService.prepareMqttClient();
          if (connected) {
            _isConnected = true;
            await _setupMqttListener();
            _clearError();
            notifyListeners();
            print('✅ [RECONNECT] Reconnection successful');
          } else {
            print('❌ [RECONNECT] Reconnection failed, will retry...');
            _scheduleReconnection();
          }
        } catch (e) {
          print('❌ [RECONNECT] Reconnection error: $e');
          _scheduleReconnection();
        }
      }
    });
  }

  // ORIGINAL METHODS (Enhanced where needed)
  Future<void> _loadInitialData() async {
    try {
      print('📚 [LOAD] Loading initial data...');
      
      final sensorData = await _firebaseService.getSensorData();
      if (sensorData != null) {
        _sensorData = sensorData;
        _lastSensorUpdate = DateTime.now();
        print('✅ [LOAD] Loaded sensor data: $sensorData');
        notifyListeners();
      }

      final pumpData = await _firebaseService.getPumpStatus();
      if (pumpData != null) {
        _pumpStatus = pumpData;
        _lastPumpUpdate = DateTime.now();
        print('✅ [LOAD] Loaded pump data: $pumpData');
        notifyListeners();
      }
    } catch (e) {
      print('❌ [LOAD] Error loading initial data: $e');
    }
  }

  // ENHANCED PUMP CONTROL
  Future<void> controlPump(bool activate) async {
    if (!_isConnected) {
      _setError('MQTT not connected');
      return;
    }

    _setLoading(true);
    
    try {
      print('🔧 [CONTROL] Controlling pump: ${activate ? 'START' : 'STOP'}');
      
      // Send command via MQTT
      await _mqttService.controlPump(activate);
      print('✅ [CONTROL] MQTT command sent successfully');
      
      // Update local state immediately for better UX
      if (_pumpStatus != null) {
        _pumpStatus = PumpStatus(
          pump: Pump(
            waterPump: WaterPump(isActive: activate),
          ),
        );
        _lastPumpUpdate = DateTime.now();
        notifyListeners();
        
        // Force immediate Firebase save for pump control
        if (_autoSaveToFirebase) {
          await _firebaseService.updatePumpStatus(_pumpStatus!);
          print('✅ [CONTROL] Firebase updated immediately');
        }
      }
      
      _clearError();
      print('🎉 [CONTROL] Pump control completed successfully');
      
    } catch (e) {
      print('❌ [CONTROL] Error controlling pump: $e');
      _setError('Failed to control pump: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ENHANCED UTILITY METHODS FOR MULTI-SENSOR
  
  // Get sensor by ID
  SoilSensor? getSensorById(String sensorId) {
    if (_sensorData == null) return null;
    
    switch (sensorId) {
      case 'sensor_1':
        return _sensorData!.sensor.soilSensor1;
      case 'sensor_2':
        return _sensorData!.sensor.soilSensor2;
      default:
        return null;
    }
  }
  
  // Get all active sensors
  List<SoilSensor> getActiveSensors() {
    if (_sensorData == null) return [];
    
    return _sensorData!.sensor.allSensors
        .where((sensor) => sensor.isActive && sensor.value > 0)
        .toList();
  }
  
  // Check if any sensor needs attention
  bool get hasAnyAlerts {
    if (_sensorData == null) return false;
    
    return _sensorData!.sensor.allSensors.any((sensor) => 
        sensor.isActive && 
        (sensor.value < 30 || sensor.value > 80)
    );
  }
  
  // Get sensor with highest/lowest values
  SoilSensor? get driestsensor {
    final activeSensors = getActiveSensors();
    if (activeSensors.isEmpty) return null;
    
    return activeSensors.reduce((a, b) => a.value < b.value ? a : b);
  }
  
  SoilSensor? get wettestSensor {
    final activeSensors = getActiveSensors();
    if (activeSensors.isEmpty) return null;
    
    return activeSensors.reduce((a, b) => a.value > b.value ? a : b);
  }

  // SETTINGS AND UTILITY METHODS
  void toggleAutoSave() {
    _autoSaveToFirebase = !_autoSaveToFirebase;
    print('⚙️ [SETTING] Auto-save to Firebase: ${_autoSaveToFirebase ? "ENABLED" : "DISABLED"}');
    
    // If auto-save is enabled and we have pending data, save immediately
    if (_autoSaveToFirebase) {
      if (_sensorData != null) {
        _queueSensorDataForFirebaseSave(_sensorData!);
      }
      if (_pumpStatus != null) {
        _queuePumpDataForFirebaseSave(_pumpStatus!);
      }
    } else {
      // Cancel pending saves if auto-save is disabled
      _sensorSaveTimer?.cancel();
      _pumpSaveTimer?.cancel();
    }
    
    notifyListeners();
  }

  Future<void> retryConnection() async {
    _clearError();
    await initialize();
  }

  Future<void> refreshData() async {
    if (!_isLoading) {
      await _loadInitialData();
    }
  }

  // ENHANCED TEST METHODS
  Future<bool> testMqttPublish() async {
    try {
      if (!_isConnected) {
        print('❌ [TEST] MQTT not connected for test');
        return false;
      }
      return await _mqttService.testPublishWithConfirmation();
    } catch (e) {
      print('❌ [TEST] MQTT test failed: $e');
      return false;
    }
  }

  Future<bool> publishTestSensorData({String sensorId = 'sensor_1'}) async {
    try {
      if (!_isConnected) return false;
      
      final testData = {
        'sensor_id': sensorId,
        '${sensorId}_value': sensorId == 'sensor_1' ? 55.0 : 62.0,
        'location': 'greenhouse',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      return await _mqttService.publishSensorData(testData);
    } catch (e) {
      print('❌ [TEST] Error publishing test sensor data: $e');
      return false;
    }
  }

  Future<bool> publishTestMultiSensorData() async {
    try {
      if (!_isConnected) return false;
      
      final testData = {
        'sensors': {
          'sensor_1': {'value': 45.5, 'is_active': true},
          'sensor_2': {'value': 67.3, 'is_active': true},
        },
        'location': 'greenhouse',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      return await _mqttService.publishSensorData(testData);
    } catch (e) {
      print('❌ [TEST] Error publishing multi-sensor test data: $e');
      return false;
    }
  }

  // HELPER METHODS
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    print('❌ [ERROR] Setting error: $error');
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    print('🧹 [DISPOSE] Disposing GreenhouseProvider...');
    
    // Cancel timers
    _sensorSaveTimer?.cancel();
    _pumpSaveTimer?.cancel();
    
    // Cancel subscriptions
    _mqttDataSubscription?.cancel();
    _firebaseSensorSubscription?.cancel();
    _firebasePumpSubscription?.cancel();
    
    // Dispose services
    try {
      _mqttService.dispose();
      _firebaseService.dispose();
    } catch (e) {
      print('❌ [DISPOSE] Error during disposal: $e');
    }
    
    super.dispose();
  }
}