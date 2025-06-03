import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/pump_status.dart';
import '../services/mqtt_service.dart';
import '../services/firebase_service.dart';

class GreenhouseProvider with ChangeNotifier {
  // Services - initialize as instances
  late MqttService _mqttService;
  late FirebaseService _firebaseService;

  // State variables
  SensorData? _soilTemperatureData;
  PumpStatus? _pumpStatus;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Constructor
  GreenhouseProvider() {
    _mqttService = MqttService();
    _firebaseService = FirebaseService();
  }

  // Getters
  SensorData? get soilTemperatureData => _soilTemperatureData;
  PumpStatus? get pumpStatus => _pumpStatus;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _setLoading(true);
    
    try {
      print('Starting initialization...');
      
      // Initialize Firebase first
      print('Initializing Firebase...');
      await _firebaseService.initialize();
      print('Firebase initialized successfully');
      
      // Connect to MQTT using prepareMqttClient method
      print('Connecting to MQTT...');
      final mqttConnected = await _mqttService.prepareMqttClient();
      _isConnected = mqttConnected;
      print('MQTT connection status: $mqttConnected');
      
      if (mqttConnected) {
        // Listen to MQTT data
        _mqttService.dataStream.listen(
          _handleMqttData,
          onError: (error) {
            print('MQTT data stream error: $error');
            _setError('MQTT data error: $error');
          },
        );
      }
      
      // Listen to Firebase data
      _firebaseService.sensorStream.listen(
        _handleSensorData,
        onError: (error) {
          print('Firebase sensor stream error: $error');
        },
      );
      
      _firebaseService.pumpStream.listen(
        _handlePumpData,
        onError: (error) {
          print('Firebase pump stream error: $error');
        },
      );
      
      // Load initial data from Firebase
      await _loadInitialData();
      
      _clearError();
      print('Initialization completed successfully');
    } catch (e) {
      print('Initialization error: $e');
      _setError('Initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadInitialData() async {
    try {
      print('Loading initial data...');
      
      final sensorData = await _firebaseService.getSensorData();
      if (sensorData != null) {
        _soilTemperatureData = sensorData;
        print('Loaded sensor data: $sensorData');
        notifyListeners();
      }

      final pumpData = await _firebaseService.getPumpStatus();
      if (pumpData != null) {
        _pumpStatus = pumpData;
        print('Loaded pump data: $pumpData');
        notifyListeners();
      }
    } catch (e) {
      print('Error loading initial data: $e');
    }
  }

  void _handleMqttData(Map<String, dynamic> data) {
    try {
      final topic = data['topic'] as String;
      print('Handling MQTT data from topic: $topic');
      
      if (topic.contains('sensors/data') || topic.contains('sensor')) {
        // Convert MQTT data to SensorData
        final sensorData = SensorData(
          soilTemperature: (data['soil_temperature'] ?? data['soil_temp'] ?? 0.0).toDouble(),
          soilMoisture: (data['soil_moisture'] ?? 0.0).toDouble(),
          airTemperature: (data['air_temperature'] ?? data['air_temp'] ?? 0.0).toDouble(),
          airHumidity: (data['air_humidity'] ?? 0.0).toDouble(),
          lightIntensity: (data['light_intensity'] ?? data['light'] ?? 0.0).toDouble(),
          ph: (data['ph'] ?? 7.0).toDouble(),
          timestamp: DateTime.now(),
          sensorId: data['sensor_id'] ?? 'greenhouse_sensor',
          batteryLevel: data['battery_level'] ?? 100,
          location: data['location'] ?? 'greenhouse',
        );
        
        _soilTemperatureData = sensorData;
        print('Updated sensor data from MQTT: $sensorData');
        
        // Update Firebase with new data
        _firebaseService.updateSensorData(sensorData).catchError((error) {
          print('Error updating sensor data in Firebase: $error');
        });
        
        notifyListeners();
      } else if (topic.contains('pump/status') || topic.contains('pump')) {
        // Convert MQTT data to PumpStatus
        final pumpData = PumpStatus(
          isActive: data['active'] ?? data['is_active'] ?? false,
          lastActivated: data['last_activated'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(data['last_activated']) 
              : null,
          lastDeactivated: data['last_deactivated'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(data['last_deactivated']) 
              : null,
          totalRunTime: Duration(minutes: data['total_runtime'] ?? 0),
          status: data['status'] ?? 'stopped',
          flowRate: (data['flow_rate'] ?? 0.0).toDouble(),
          autoMode: data['auto_mode'] ?? false,
          scheduledDuration: data['scheduled_duration'] ?? 10,
          pumpId: data['pump_id'] ?? 'main_pump',
          pressure: (data['pressure'] ?? 0.0).toDouble(),
          cyclesCount: data['cycles_count'] ?? 0,
        );
        
        _pumpStatus = pumpData;
        print('Updated pump data from MQTT: $pumpData');
        
        // Update Firebase with new status
        _firebaseService.updatePumpStatus(pumpData).catchError((error) {
          print('Error updating pump status in Firebase: $error');
        });
        
        notifyListeners();
      }
    } catch (e) {
      print('Error handling MQTT data: $e');
    }
  }

  void _handleSensorData(SensorData data) {
    print('Handling sensor data from Firebase: $data');
    _soilTemperatureData = data;
    notifyListeners();
  }

  void _handlePumpData(PumpStatus data) {
    print('Handling pump data from Firebase: $data');
    _pumpStatus = data;
    notifyListeners();
  }

  Future<void> controlPump(bool activate) async {
    if (!_isConnected) {
      _setError('MQTT not connected');
      return;
    }

    _setLoading(true);
    
    try {
      print('Controlling pump: ${activate ? 'start' : 'stop'}');
      await _mqttService.controlPump(activate);
      
      // Update local state immediately for better UX
      if (_pumpStatus != null) {
        _pumpStatus = _pumpStatus!.copyWith(
          isActive: activate,
          lastActivated: activate ? DateTime.now() : _pumpStatus!.lastActivated,
          lastDeactivated: !activate ? DateTime.now() : _pumpStatus!.lastDeactivated,
          status: activate ? 'running' : 'stopped',
        );
        
        // Update Firebase
        await _firebaseService.updatePumpStatus(_pumpStatus!);
        
        notifyListeners();
        print('Pump control completed successfully');
      }
      
      _clearError();
    } catch (e) {
      print('Error controlling pump: $e');
      _setError('Failed to control pump: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> setAutoWatering(bool enabled, int duration) async {
    try {
      print('Setting auto watering: enabled=$enabled, duration=$duration');
      
      if (_pumpStatus != null) {
        final updatedStatus = _pumpStatus!.copyWith(
          autoMode: enabled,
          scheduledDuration: duration,
        );
        
        await _firebaseService.updatePumpStatus(updatedStatus);
        _pumpStatus = updatedStatus;
        notifyListeners();
        print('Auto watering settings updated');
      }

      // Also send to MQTT if connected
      if (_isConnected) {
        final autoConfig = {
          'auto_enabled': enabled,
          'duration_minutes': duration,
          'interval_hours': 6, // Default interval
          'soil_moisture_threshold': 30.0,
        };
        
        await _mqttService.publishToTopic('greenhouse/config/auto_watering', autoConfig);
      }
    } catch (e) {
      print('Error setting auto watering: $e');
      _setError('Failed to set auto watering: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistoricalData({
    required String sensorType,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('Getting historical data for $sensorType from $startDate to $endDate');
      return await _firebaseService.getHistoricalData(
        sensorType: sensorType,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      print('Error getting historical data: $e');
      _setError('Failed to load historical data: $e');
      return [];
    }
  }

  // Retry connection
  Future<void> retryConnection() async {
    _clearError();
    await initialize();
  }

  // Manual refresh data
  Future<void> refreshData() async {
    if (!_isLoading) {
      _setLoading(true);
      try {
        await _loadInitialData();
        _clearError();
      } catch (e) {
        _setError('Failed to refresh data: $e');
      } finally {
        _setLoading(false);
      }
    }
  }

  // Test connection
  Future<bool> testConnection() async {
    try {
      // Test Firebase connection
      final sensorData = await _firebaseService.getSensorData();
      
      // Test MQTT connection
      final mqttConnected = _mqttService.isConnected;
      
      return sensorData != null || mqttConnected;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  // Test MQTT publish
  Future<bool> testMqttPublish() async {
    try {
      if (!_isConnected) {
        print('MQTT not connected for test');
        return false;
      }

      return await _mqttService.testPublishWithConfirmation();
    } catch (e) {
      print('MQTT test failed: $e');
      return false;
    }
  }

  // Publish sensor data manually (for testing)
  Future<bool> publishTestSensorData() async {
    try {
      if (!_isConnected) {
        return false;
      }

      final testData = {
        'soil_temperature': 22.5,
        'soil_moisture': 45.0,
        'air_temperature': 25.0,
        'air_humidity': 60.0,
        'light_intensity': 500.0,
        'ph': 6.8,
        'sensor_id': 'test_sensor',
        'battery_level': 95,
        'location': 'greenhouse',
      };

      return await _mqttService.publishSensorData(testData);
    } catch (e) {
      print('Error publishing test sensor data: $e');
      return false;
    }
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    print('Setting error: $error');
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
    print('Disposing GreenhouseProvider...');
    try {
      _mqttService.dispose();
      _firebaseService.dispose();
    } catch (e) {
      print('Error during disposal: $e');
    }
    super.dispose();
  }
}