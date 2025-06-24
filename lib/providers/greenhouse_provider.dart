import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/sensor_data.dart';
import '../models/pump_status.dart';
import '../services/firebase_service.dart';
import '../services/mqtt_service.dart'; // Your existing MQTT service

class GreenhouseProvider with ChangeNotifier {
  // Services (Firebase + MQTT for pump control)
  late FirebaseService _firebaseService;
  late MqttService _mqttService; // Your existing MQTT service

  // State variables
  SensorData? _sensorData;
  PumpStatus? _pumpStatus;
  bool _isFirebaseConnected = false;
  bool _isMqttConnected = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Last update tracking
  DateTime? _lastSensorUpdate;
  DateTime? _lastPumpUpdate;
  
  // Stream subscriptions for cleanup
  StreamSubscription<SensorData>? _firebaseSensorSubscription;
  StreamSubscription<PumpStatus>? _firebasePumpSubscription;
  StreamSubscription<Map<String, dynamic>>? _mqttDataSubscription; // Use your existing MQTT stream

  // Constructor
  GreenhouseProvider() {
    _firebaseService = FirebaseService();
    _mqttService = MqttService(); // Use your existing MQTT service
  }

  // Getters
  SensorData? get sensorData => _sensorData;
  PumpStatus? get pumpStatus => _pumpStatus;
  bool get isConnected => _isFirebaseConnected && _isMqttConnected; // Both must be connected
  bool get isFirebaseConnected => _isFirebaseConnected;
  bool get isMqttConnected => _isMqttConnected;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
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
  double? get currentSoilHumidityLegacy => sensor1Humidity;
  String? get soilCondition => overallCondition;

  Future<void> initialize() async {
    _setLoading(true);
    
    try {
      print('🚀 [INIT] Starting GreenhouseProvider initialization (Firebase + MQTT)...');
      
      // Initialize Firebase
      print('🔥 [INIT] Initializing Firebase...');
      await _firebaseService.initialize();
      _isFirebaseConnected = true;
      print('✅ [INIT] Firebase initialized successfully');
      
      // Initialize MQTT using your existing service
      print('📡 [INIT] Initializing MQTT...');
      await _mqttService.prepareMqttClient();
      _isMqttConnected = _mqttService.isConnected;
      print('✅ [INIT] MQTT initialized successfully');
      
      // Test connections
      print('🧪 [INIT] Testing connections...');
      final testData = await _firebaseService.getSensorData();
      print('📊 [INIT] Firebase test data result: $testData');
      
      // Setup listeners
      await _setupFirebaseListeners();
      await _setupMqttListeners();
      
      // Load initial data from Firebase
      print('📚 [INIT] Loading initial data from Firebase...');
      await _loadInitialData();
      
      _clearError();
      print('🎉 [INIT] Initialization completed successfully (Firebase + MQTT)');
      
    } catch (e) {
      print('💥 [INIT] Initialization error: $e');
      _setError('Initialization failed: $e');
      _isFirebaseConnected = false;
      _isMqttConnected = false;
    } finally {
      _setLoading(false);
    }
  }

  // FIREBASE LISTENER SETUP
  Future<void> _setupFirebaseListeners() async {
    try {
      // Cancel existing subscriptions
      await _firebaseSensorSubscription?.cancel();
      await _firebasePumpSubscription?.cancel();
      
      // Setup sensor data listener (Firebase only)
      _firebaseSensorSubscription = _firebaseService.sensorStream.listen(
        _handleFirebaseSensorData,
        onError: (error) {
          print('❌ [FIREBASE] Sensor stream error: $error');
          _setError('Firebase sensor error: $error');
        },
      );
      
      // Setup pump data listener from Firebase (backup)
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

  // MQTT LISTENER SETUP
  Future<void> _setupMqttListeners() async {
    try {
      // Cancel existing MQTT subscriptions
      await _mqttDataSubscription?.cancel();
      
      // Setup MQTT data listener using your existing service
      _mqttDataSubscription = _mqttService.dataStream.listen(
        _handleMqttData,
        onError: (error) {
          print('❌ [MQTT] Data stream error: $error');
          _setError('MQTT data error: $error');
        },
      );
      
      print('👂 [INIT] MQTT stream listeners setup complete');
    } catch (e) {
      print('❌ [MQTT] Error setting up listeners: $e');
      throw e;
    }
  }

  // FIREBASE DATA HANDLERS
  void _handleFirebaseSensorData(SensorData data) {
    try {
      print('📨 [FIREBASE→SENSOR] Handling sensor data from Firebase');
      print('📊 [FIREBASE→SENSOR] Multi-sensor data:');
      print('   Sensor 1: ${data.sensor.soilSensor1.value}% (${data.sensor.soilSensor1.condition})');
      print('   Sensor 2: ${data.sensor.soilSensor2.value}% (${data.sensor.soilSensor2.condition})');
      print('   Average: ${data.sensor.averageHumidity.toStringAsFixed(1)}% (${data.sensor.overallCondition})');
      
      // Update local state
      _sensorData = data;
      _lastSensorUpdate = DateTime.now();
      notifyListeners();
      
      print('✅ [FIREBASE→SENSOR] Local state updated successfully');
    } catch (e) {
      print('❌ [FIREBASE→SENSOR] Error handling sensor data: $e');
      _setError('Error processing sensor data: $e');
    }
  }

  void _handleFirebasePumpData(PumpStatus data) {
    try {
      print('📨 [FIREBASE→PUMP] Handling pump data from Firebase (backup)');
      print('🔧 [FIREBASE→PUMP] Pump status: ${data.pump.waterPump.isActive ? "ON" : "OFF"}');
      
      // Only update if we don't have fresher MQTT data
      if (_lastPumpUpdate == null || 
          DateTime.now().difference(_lastPumpUpdate!).inSeconds > 10) {
        _pumpStatus = data;
        _lastPumpUpdate = DateTime.now();
        notifyListeners();
        print('✅ [FIREBASE→PUMP] Local state updated from Firebase backup');
      } else {
        print('ℹ️ [FIREBASE→PUMP] Skipped update - MQTT data is fresher');
      }
    } catch (e) {
      print('❌ [FIREBASE→PUMP] Error handling pump data: $e');
      _setError('Error processing pump data: $e');
    }
  }

  // MQTT DATA HANDLERS
  void _handleMqttData(Map<String, dynamic> data) {
    try {
      print('📨 [MQTT→DATA] Handling data from MQTT: $data');
      
      // Check topic to determine data type
      final topic = data['topic'] as String?;
      
      if (topic != null) {
        // Handle pump status/control messages
        if (topic.contains('pump') || topic.contains('control')) {
          _handleMqttPumpData(data);
        }
        // Handle sensor data messages
        else if (topic.contains('sensor')) {
          _handleMqttSensorData(data);
        }
        else {
          print('ℹ️ [MQTT→DATA] Unhandled topic: $topic');
        }
      } else {
        print('⚠️ [MQTT→DATA] No topic found in data');
      }
      
      // Update MQTT connection status
      _isMqttConnected = _mqttService.isConnected;
      notifyListeners();
      
    } catch (e) {
      print('❌ [MQTT→DATA] Error handling MQTT data: $e');
      _setError('Error processing MQTT data: $e');
    }
  }

  void _handleMqttPumpData(Map<String, dynamic> data) {
    try {
      print('📨 [MQTT→PUMP] Handling pump data from MQTT');
      
      // Extract pump status from MQTT data
      bool isActive = false;
      
      // Check various possible fields for pump status
      if (data.containsKey('is_active')) {
        isActive = data['is_active'] == true;
      } else if (data.containsKey('action')) {
        final action = data['action'].toString().toLowerCase();
        isActive = action == 'on' || action == 'start' || action == 'activate';
      } else if (data.containsKey('status')) {
        final status = data['status'].toString().toLowerCase();
        isActive = status == 'on' || status == 'active' || status == 'running';
      }
      
      print('🔧 [MQTT→PUMP] Pump status: ${isActive ? "ON" : "OFF"}');
      
      // Create PumpStatus object
      final pumpStatus = PumpStatus(
        pump: Pump(
          waterPump: WaterPump(isActive: isActive),
        ),
      );
      
      // Update local state (MQTT has priority over Firebase for pump data)
      _pumpStatus = pumpStatus;
      _lastPumpUpdate = DateTime.now();
      notifyListeners();
      
      // Also update Firebase for historical data
      _firebaseService.updatePumpStatus(pumpStatus).catchError((error) {
        print('⚠️ [MQTT→PUMP] Failed to sync to Firebase: $error');
      });
      
      print('✅ [MQTT→PUMP] Local state updated successfully');
    } catch (e) {
      print('❌ [MQTT→PUMP] Error handling pump data: $e');
      _setError('Error processing MQTT pump data: $e');
    }
  }

  void _handleMqttSensorData(Map<String, dynamic> data) {
    try {
      print('📨 [MQTT→SENSOR] Handling sensor data from MQTT (for reference)');
      print('📊 [MQTT→SENSOR] Sensor data: $data');
      
      // Note: We primarily use Firebase for sensor data, but this can be used for real-time updates
      // You can add logic here if you want to handle sensor data from MQTT too
      
    } catch (e) {
      print('❌ [MQTT→SENSOR] Error handling sensor data: $e');
    }
  }

  // LOAD INITIAL DATA FROM FIREBASE
  Future<void> _loadInitialData() async {
    try {
      print('📚 [LOAD] Loading initial data from Firebase...');
      
      final sensorData = await _firebaseService.getSensorData();
      if (sensorData != null) {
        _sensorData = sensorData;
        _lastSensorUpdate = DateTime.now();
        print('✅ [LOAD] Loaded sensor data: Sensor1=${sensorData.sensor.soilSensor1.value}%, Sensor2=${sensorData.sensor.soilSensor2.value}%');
        notifyListeners();
      }

      final pumpData = await _firebaseService.getPumpStatus();
      if (pumpData != null) {
        _pumpStatus = pumpData;
        _lastPumpUpdate = DateTime.now();
        print('✅ [LOAD] Loaded pump data: ${pumpData.pump.waterPump.isActive ? "ON" : "OFF"}');
        notifyListeners();
      }
    } catch (e) {
      print('❌ [LOAD] Error loading initial data: $e');
      _setError('Failed to load initial data: $e');
    }
  }

  // PUMP CONTROL VIA MQTT (Primary method)
  Future<void> controlPump(bool activate) async {
    if (!_isMqttConnected) {
      print('⚠️ [CONTROL] MQTT not connected, falling back to Firebase...');
      return await _controlPumpViaFirebase(activate);
    }

    _setLoading(true);
    
    try {
      print('🔧 [CONTROL] Controlling pump via MQTT: ${activate ? 'START' : 'STOP'}');
      
      // Use your existing MQTT service's controlPump method
      bool success = await _mqttService.controlPump(activate);
      
      if (success) {
        print('✅ [CONTROL] MQTT command sent successfully');
        
        // Update local state immediately for better UX
        final pumpStatus = PumpStatus(
          pump: Pump(
            waterPump: WaterPump(isActive: activate),
          ),
        );
        
        _pumpStatus = pumpStatus;
        _lastPumpUpdate = DateTime.now();
        notifyListeners();
        
        // Also update Firebase for backup/historical data
        _firebaseService.updatePumpStatus(pumpStatus).catchError((error) {
          print('⚠️ [CONTROL] Failed to backup to Firebase: $error');
        });
        
        _clearError();
        print('🎉 [CONTROL] Pump control completed successfully via MQTT');
      } else {
        throw Exception('MQTT publish failed');
      }
      
    } catch (e) {
      print('❌ [CONTROL] Error controlling pump via MQTT: $e');
      print('🔄 [CONTROL] Falling back to Firebase...');
      
      // Fallback to Firebase if MQTT fails
      await _controlPumpViaFirebase(activate);
    } finally {
      _setLoading(false);
    }
  }

  // PUMP CONTROL VIA FIREBASE (Fallback method)
  Future<void> _controlPumpViaFirebase(bool activate) async {
    try {
      print('🔧 [CONTROL] Controlling pump via Firebase (fallback): ${activate ? 'START' : 'STOP'}');
      
      // Create pump status object
      final pumpStatus = PumpStatus(
        pump: Pump(
          waterPump: WaterPump(isActive: activate),
        ),
      );
      
      // Update Firebase directly
      await _firebaseService.updatePumpStatus(pumpStatus);
      print('✅ [CONTROL] Firebase updated successfully');
      
      // Update local state immediately for better UX
      _pumpStatus = pumpStatus;
      _lastPumpUpdate = DateTime.now();
      notifyListeners();
      
      _clearError();
      print('🎉 [CONTROL] Pump control completed successfully via Firebase');
      
    } catch (e) {
      print('❌ [CONTROL] Error controlling pump via Firebase: $e');
      _setError('Failed to control pump: $e');
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
  SoilSensor? get driestSensor {
    final activeSensors = getActiveSensors();
    if (activeSensors.isEmpty) return null;
    
    return activeSensors.reduce((a, b) => a.value < b.value ? a : b);
  }
  
  SoilSensor? get wettestSensor {
    final activeSensors = getActiveSensors();
    if (activeSensors.isEmpty) return null;
    
    return activeSensors.reduce((a, b) => a.value > b.value ? a : b);
  }

  // DATA REFRESH AND CONNECTION MANAGEMENT
  Future<void> refreshData() async {
    if (!_isLoading) {
      print('🔄 [REFRESH] Refreshing data from Firebase...');
      await _loadInitialData();
    }
  }

  Future<void> retryConnection() async {
    print('🔄 [RETRY] Retrying connections...');
    _clearError();
    await initialize();
  }

  Future<void> retryMqttConnection() async {
    print('🔄 [RETRY] Retrying MQTT connection...');
    try {
      await _mqttService.prepareMqttClient();
      _isMqttConnected = _mqttService.isConnected;
      if (_isMqttConnected) {
        await _setupMqttListeners();
      }
      notifyListeners();
    } catch (e) {
      print('❌ [RETRY] MQTT reconnection failed: $e');
      _isMqttConnected = false;
      notifyListeners();
    }
  }

  // TEST METHODS
  Future<bool> testFirebaseConnection() async {
    try {
      print('🧪 [TEST] Testing Firebase connection...');
      final testData = await _firebaseService.getSensorData();
      if (testData != null) {
        print('✅ [TEST] Firebase connection test successful');
        return true;
      } else {
        print('⚠️ [TEST] Firebase connection test returned null data');
        return false;
      }
    } catch (e) {
      print('❌ [TEST] Firebase connection test failed: $e');
      return false;
    }
  }

  Future<bool> testMqttConnection() async {
    try {
      print('🧪 [TEST] Testing MQTT connection...');
      // Use your existing MQTT service's test method
      final isConnected = await _mqttService.testPublishWithConfirmation();
      print('${isConnected ? "✅" : "❌"} [TEST] MQTT connection test result: $isConnected');
      return isConnected;
    } catch (e) {
      print('❌ [TEST] MQTT connection test failed: $e');
      return false;
    }
  }

  Future<bool> testPumpControl() async {
    try {
      print('🧪 [TEST] Testing pump control...');
      
      // Toggle pump state
      final currentState = _pumpStatus?.pump.waterPump.isActive ?? false;
      await controlPump(!currentState);
      
      // Wait a bit then toggle back
      await Future.delayed(Duration(seconds: 2));
      await controlPump(currentState);
      
      print('✅ [TEST] Pump control test completed');
      return true;
    } catch (e) {
      print('❌ [TEST] Pump control test failed: $e');
      return false;
    }
  }

  // CONNECTION STATUS METHODS
  bool get hasDataConnection => (_isFirebaseConnected || _isMqttConnected) && 
                                (_sensorData != null || _pumpStatus != null);
  
  String get connectionStatusText {
    if (!_isFirebaseConnected && !_isMqttConnected) return 'Disconnected';
    if (_isLoading) return 'Loading...';
    if (_errorMessage != null) return 'Error';
    if (_isFirebaseConnected && _isMqttConnected) return 'Fully Connected';
    if (_isFirebaseConnected) return 'Firebase Only';
    if (_isMqttConnected) return 'MQTT Only';
    return 'Connecting...';
  }

  String get mqttStatusText {
    return _isMqttConnected ? 'Connected' : 'Disconnected';
  }

  String get firebaseStatusText {
    return _isFirebaseConnected ? 'Connected' : 'Disconnected';
  }

  // DATA FRESHNESS CHECK
  bool get isSensorDataFresh {
    if (_lastSensorUpdate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(_lastSensorUpdate!);
    return difference.inMinutes < 5; // Consider fresh if updated within 5 minutes
  }

  bool get isPumpDataFresh {
    if (_lastPumpUpdate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(_lastPumpUpdate!);
    return difference.inMinutes < 5; // Consider fresh if updated within 5 minutes
  }

  // UTILITY METHODS
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
    
    // Cancel subscriptions
    _firebaseSensorSubscription?.cancel();
    _firebasePumpSubscription?.cancel();
    _mqttDataSubscription?.cancel();
    
    // Dispose services
    try {
      _firebaseService.dispose();
      _mqttService.dispose();
    } catch (e) {
      print('❌ [DISPOSE] Error during disposal: $e');
    }
    
    super.dispose();
  }
}