import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// Connection states for easy identification
enum MqttCurrentConnectionState {
  IDLE,
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
  ERROR_WHEN_CONNECTING
}

enum MqttSubscriptionState {
  IDLE,
  SUBSCRIBED
}

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  late MqttServerClient client;
  final StreamController<Map<String, dynamic>> _dataController = 
      StreamController<Map<String, dynamic>>.broadcast();

  MqttCurrentConnectionState connectionState = MqttCurrentConnectionState.IDLE;
  MqttSubscriptionState subscriptionState = MqttSubscriptionState.IDLE;

  // HiveMQ Cloud settings
  static const String _broker = 'e1ba2dc5f46b4b46a15520b16e2bebc2.s1.eu.hivemq.cloud';
  static const int _port = 8883;
  static const String _username = 'drip_flush_app';
  static const String _password = 'TeluJuara1';
  static const String _clientId = 'greenhouse_flutter_client';

  // Topics
  static const String _sensorDataTopic = 'greenhouse/sensors/data';
  static const String _pumpControlTopic = 'greenhouse/control/pump';
  static const String _pumpStatusTopic = 'greenhouse/pump/status';

  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;
  bool get isConnected => connectionState == MqttCurrentConnectionState.CONNECTED;

  // Main method to prepare and connect MQTT client
  Future<bool> prepareMqttClient() async {
    try {
      _setupMqttClient();
      await _connectClient();
      if (isConnected) {
        _subscribeToTopics();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error preparing MQTT client: $e');
      return false;
    }
  }

  // Setup MQTT client - following HiveMQ official method
  void _setupMqttClient() {
    print('🔧 Setting up MQTT client...');
    
    // Create client with unique ID
    final uniqueClientId = '${_clientId}_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient.withPort(_broker, uniqueClientId, _port);
    
    // TLS configuration - essential for HiveMQ Cloud
    client.secure = true;
    client.securityContext = SecurityContext.defaultContext;
    
    // Basic configuration
    client.keepAlivePeriod = 20;
    client.logging(on: true);
    
    // Callbacks
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
  }

  // Connect client - following HiveMQ official method
  Future<void> _connectClient() async {
    try {
      print('🔌 Client connecting....');
      connectionState = MqttCurrentConnectionState.CONNECTING;
      
      // Connect using username and password - HiveMQ official way
      await client.connect(_username, _password);
      
    } on Exception catch (e) {
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      client.disconnect();
      return;
    }

    // Check connection status
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      connectionState = MqttCurrentConnectionState.CONNECTED;
    } else {
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      client.disconnect();
    }
  }

  // Subscribe to topics
  void _subscribeToTopics() {
    print('📡 Subscribing to topics...');
    
    // Subscribe to sensor data
    _subscribeToTopic(_sensorDataTopic);
    
    // Subscribe to pump status - IMPORTANT: Subscribe to status topic
    _subscribeToTopic(_pumpStatusTopic);
    
    // ENHANCED: Also subscribe to control topic to catch our own commands
    _subscribeToTopic(_pumpControlTopic);
    
    // Listen to all messages
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      print('📨 NEW MESSAGE from ${c[0].topic}:');
      print('📝 Content: $message');
      
      try {
        var data = json.decode(message) as Map<String, dynamic>;
        data['topic'] = c[0].topic;
        
        // ENHANCED: If this is a pump control command, convert it to status format
        if (c[0].topic == _pumpControlTopic) {
          data = _convertControlToStatus(data);
        }
        
        _dataController.add(data);
      } catch (e) {
        print('❌ Error parsing message: $e');
        print('Raw message: $message');
      }
    });
  }

  // ENHANCED: Convert pump control command to status format
  Map<String, dynamic> _convertControlToStatus(Map<String, dynamic> controlData) {
    print('🔄 Converting pump control to status format...');
    print('🔄 Original: $controlData');
    
    // Extract the action and convert to is_active
    bool isActive = false;
    if (controlData.containsKey('action')) {
      final action = controlData['action'].toString().toLowerCase();
      isActive = action == 'on' || action == 'start' || action == 'activate';
    }
    
    // Create status format that provider expects
    final statusData = {
      'device': controlData['device'] ?? 'water_pump',
      'is_active': isActive, // Use is_active instead of action
      'timestamp': controlData['timestamp'] ?? DateTime.now().toIso8601String(),
      'source': controlData['source'] ?? 'mqtt_service',
      'command_id': controlData['command_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'topic': _pumpStatusTopic, // Change topic to status topic
    };
    
    print('🔄 Converted: $statusData');
    return statusData;
  }

  void _subscribeToTopic(String topicName) {
    print('📡 Subscribing to $topicName topic');
    client.subscribe(topicName, MqttQos.atMostOnce);
  }

  // ===========================================
  // ENHANCED PUBLISH MESSAGE FUNCTIONS
  // ===========================================

  // Public method untuk publish message generic
  Future<bool> publishMessage(String topic, String message) async {
    try {
      if (!isConnected) {
        print('❌ Cannot publish - MQTT not connected');
        throw Exception('MQTT not connected. Current state: $connectionState');
      }

      print('📤 Publishing message to topic: $topic');
      print('📝 Message content: $message');

      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
      builder.addString(message);

      // Publish dengan QoS level 1 untuk memastikan delivery
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      
      print('✅ Message published successfully to $topic');
      return true;
      
    } catch (e, stackTrace) {
      print('❌ Error publishing message: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  // ENHANCED: Method khusus untuk kontrol pump dengan dual publish
  Future<bool> controlPump(bool activate) async {
    try {
      if (!isConnected) {
        print('❌ Cannot control pump - MQTT not connected');
        throw Exception('MQTT not connected');
      }

      final timestamp = DateTime.now().toIso8601String();
      final commandId = DateTime.now().millisecondsSinceEpoch.toString();

      // 1. Send control command (original format)
      final controlMessage = {
        'device': 'water_pump',
        'action': activate ? 'on' : 'off',
        'timestamp': timestamp,
        'source': 'flutter_app',
        'command_id': commandId,
      };

      final controlJson = json.encode(controlMessage);
      print('🚰 [CONTROL] Sending pump control command...');
      bool controlSuccess = await publishMessage(_pumpControlTopic, controlJson);
      
      // 2. ENHANCED: Also send status message (provider-friendly format)
      final statusMessage = {
        'device': 'water_pump',
        'is_active': activate, // Provider expects this format
        'status': activate ? 'on' : 'off',
        'timestamp': timestamp,
        'source': 'flutter_app',
        'command_id': commandId,
      };

      final statusJson = json.encode(statusMessage);
      print('🚰 [STATUS] Sending pump status update...');
      bool statusSuccess = await publishMessage(_pumpStatusTopic, statusJson);
      
      if (controlSuccess && statusSuccess) {
        print('🚰 Pump control sent successfully: ${activate ? "ON" : "OFF"}');
        print('✅ Both control and status messages published');
        return true;
      } else {
        print('⚠️ Partial success - Control: $controlSuccess, Status: $statusSuccess');
        return controlSuccess || statusSuccess; // At least one succeeded
      }
      
    } catch (e) {
      print('❌ Error controlling pump: $e');
      return false;
    }
  }

  // ENHANCED: Method untuk publish sensor data dengan format konsisten
  Future<bool> publishSensorData(Map<String, dynamic> sensorData) async {
    try {
      if (!isConnected) {
        print('❌ Cannot publish sensor data - MQTT not connected');
        return false;
      }

      // Ensure consistent format
      final formattedData = {
        'soil_humidity': sensorData['soil_humidity'] ?? sensorData['value'] ?? sensorData['soil_moisture'] ?? 0.0,
        'sensor_id': sensorData['sensor_id'] ?? 'greenhouse_sensor',
        'location': sensorData['location'] ?? 'greenhouse',
        'timestamp': sensorData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'source': 'flutter_app',
      };

      return await publishToTopic(_sensorDataTopic, formattedData);
    } catch (e) {
      print('❌ Error publishing sensor data: $e');
      return false;
    }
  }

  // ENHANCED: Method untuk publish pump status dengan format konsisten
  Future<bool> publishPumpStatus(bool isActive) async {
    try {
      if (!isConnected) {
        print('❌ Cannot publish pump status - MQTT not connected');
        return false;
      }

      final statusData = {
        'device': 'water_pump',
        'is_active': isActive,
        'status': isActive ? 'on' : 'off',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'flutter_app',
        'command_id': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      return await publishMessage(_pumpStatusTopic, json.encode(statusData));
    } catch (e) {
      print('❌ Error publishing pump status: $e');
      return false;
    }
  }

  // Method untuk publish dengan topik custom
  Future<bool> publishToTopic(String topic, Map<String, dynamic> data) async {
    try {
      if (!isConnected) {
        print('❌ Cannot publish - MQTT not connected');
        return false;
      }

      // Tambahkan metadata default
      data['timestamp'] ??= DateTime.now().toIso8601String();
      data['source'] ??= 'flutter_app';
      
      final jsonMessage = json.encode(data);
      return await publishMessage(topic, jsonMessage);
      
    } catch (e) {
      print('❌ Error publishing to topic $topic: $e');
      return false;
    }
  }

  // Method untuk publish status
  Future<bool> publishStatus(String deviceType, String status, {Map<String, dynamic>? additionalData}) async {
    final statusMessage = {
      'device_type': deviceType,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
      'source': 'flutter_app',
    };
    
    // if (additionalData != null) {
    //   statusMessage.addAll(additionalData);
    // }
    
    return await publishToTopic('greenhouse/status/$deviceType', statusMessage);
  }

  // Method untuk publish ke multiple topics
  Future<Map<String, bool>> publishToMultipleTopics(Map<String, String> topicsAndMessages) async {
    Map<String, bool> results = {};
    
    for (String topic in topicsAndMessages.keys) {
      String message = topicsAndMessages[topic]!;
      bool success = await publishMessage(topic, message);
      results[topic] = success;
    }
    
    return results;
  }

  // Method dengan retry mechanism
  Future<bool> publishMessageWithRetry(String topic, String message, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('📤 Attempt $attempt/$maxRetries: Publishing to $topic');
        
        bool success = await publishMessage(topic, message);
        if (success) {
          print('✅ Message published successfully on attempt $attempt');
          return true;
        }
        
        if (attempt < maxRetries) {
          print('⏳ Retrying in 1 second...');
          await Future.delayed(Duration(seconds: 1));
        }
        
      } catch (e) {
        print('❌ Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }
    
    print('❌ All publish attempts failed');
    return false;
  }

  // Method untuk check connection dan auto-reconnect sebelum publish
  Future<bool> ensureConnectionAndPublish(String topic, String message) async {
    // Check if connected
    if (!isConnected) {
      print('🔄 Not connected, attempting to reconnect...');
      bool reconnected = await prepareMqttClient();
      if (!reconnected) {
        print('❌ Failed to reconnect');
        return false;
      }
    }
    
    return await publishMessage(topic, message);
  }

  // ENHANCED: Method untuk test publish dengan konfirmasi
  Future<bool> testPublishWithConfirmation() async {
    try {
      if (!isConnected) {
        print('❌ Cannot test publish - not connected');
        return false;
      }

      final testMessage = {
        'test': true,
        'message': 'Test from Flutter app',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'flutter_app_test',
        'test_id': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      bool success = await publishMessage('test/flutter/confirmation', json.encode(testMessage));
      
      if (success) {
        print('✅ Test publish successful');
      } else {
        print('❌ Test publish failed');
      }
      
      return success;
      
    } catch (e) {
      print('❌ Error in test publish: $e');
      return false;
    }
  }

  // ENHANCED: Test method untuk pump dengan format baru
  Future<bool> testPumpControl() async {
    try {
      if (!isConnected) {
        print('❌ Cannot test pump control - not connected');
        return false;
      }

      print('🧪 Testing pump control with dual publish...');
      
      // Test ON
      bool onResult = await controlPump(true);
      await Future.delayed(Duration(seconds: 2));
      
      // Test OFF
      bool offResult = await controlPump(false);
      
      print('🧪 Test results - ON: $onResult, OFF: $offResult');
      return onResult && offResult;
      
    } catch (e) {
      print('❌ Error in pump test: $e');
      return false;
    }
  }

  // ENHANCED: Test method untuk sensor data
  Future<bool> testSensorData() async {
    try {
      if (!isConnected) {
        print('❌ Cannot test sensor data - not connected');
        return false;
      }

      final testSensorData = {
        'soil_humidity': 65.5,
        'sensor_id': 'test_sensor',
        'location': 'greenhouse_test',
      };

      return await publishSensorData(testSensorData);
      
    } catch (e) {
      print('❌ Error testing sensor data: $e');
      return false;
    }
  }

  // ===========================================
  // EXISTING METHODS (KEPT FOR COMPATIBILITY)
  // ===========================================

  // Generic publish message method (private - untuk internal use)
  void _publishMessage(String topic, String message) {
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(message);

    print('📤 Publishing message "$message" to topic $topic');
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }

  // Test publish method (original)
  Future<void> testPublish() async {
    if (!isConnected) {
      print('❌ Cannot test publish - not connected');
      return;
    }

    final testMessage = {
      'test': true,
      'timestamp': DateTime.now().toIso8601String(),
      'source': 'flutter_app_test'
    };

    _publishMessage('test/flutter', json.encode(testMessage));
  }

  // Callback methods
  void _onSubscribed(String topic) {
    print('✅ Subscription confirmed for topic $topic');
    subscriptionState = MqttSubscriptionState.SUBSCRIBED;
  }

  void _onDisconnected() {
    print('🔌 OnDisconnected client callback - Client disconnection');
    connectionState = MqttCurrentConnectionState.DISCONNECTED;
  }

  void _onConnected() {
    connectionState = MqttCurrentConnectionState.CONNECTED;
    print('✅ OnConnected client callback - Client connection was successful');
  }

  // Disconnect method
  Future<void> disconnect() async {
    if (connectionState == MqttCurrentConnectionState.CONNECTED) {
      print('🔌 Disconnecting from MQTT broker...');
      client.disconnect();
      connectionState = MqttCurrentConnectionState.DISCONNECTED;
    }
  }

  void dispose() {
    _dataController.close();
    disconnect();
  }

  // Simple connection test method
  static Future<bool> testConnection() async {
    try {
      print('\n🧪 === TESTING HIVEMQ CONNECTION (OFFICIAL METHOD) ===');
      
      final testClientId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testClient = MqttServerClient.withPort(_broker, testClientId, _port);
      
      // Setup exactly like HiveMQ documentation
      testClient.secure = true;
      testClient.securityContext = SecurityContext.defaultContext;
      testClient.keepAlivePeriod = 20;
      testClient.logging(on: true);
      
      bool connected = false;
      testClient.onConnected = () {
        print('✅ Test connection successful');
        connected = true;
      };
      
      testClient.onDisconnected = () {
        print('🔌 Test client disconnected');
      };

      print('📡 Testing connection to $_broker:$_port');
      print('👤 Using credentials: $_username / $_password');
      print('🆔 Test Client ID: $testClientId');
      
      // Connect using the official HiveMQ method
      await testClient.connect(_username, _password);
      
      if (testClient.connectionStatus!.state == MqttConnectionState.connected) {
        print('✅ OFFICIAL METHOD TEST: SUCCESS');
        
        // Test publish
        final builder = MqttClientPayloadBuilder();
        builder.addString('Test message from official method');
        testClient.publishMessage('test/official', MqttQos.exactlyOnce, builder.payload!);
        print('📤 Test message published');
        
        await Future.delayed(Duration(seconds: 2));
        testClient.disconnect();
        return true;
      } else {
        print('❌ OFFICIAL METHOD TEST: FAILED');
        print('Status: ${testClient.connectionStatus}');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ OFFICIAL METHOD ERROR: $e');
      print('Stack: $stackTrace');
      return false;
    }
  }
}