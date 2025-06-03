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
    
    print('✅ MQTT client setup completed');
    print('📡 Broker: $_broker:$_port');
    print('🆔 Client ID: $uniqueClientId');
  }

  // Connect client - following HiveMQ official method
  Future<void> _connectClient() async {
    try {
      print('🔌 Client connecting....');
      connectionState = MqttCurrentConnectionState.CONNECTING;
      
      // Connect using username and password - HiveMQ official way
      await client.connect(_username, _password);
      
    } on Exception catch (e) {
      print('❌ Client exception - $e');
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      client.disconnect();
      return;
    }

    // Check connection status
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      connectionState = MqttCurrentConnectionState.CONNECTED;
      print('✅ Client connected successfully');
    } else {
      print('❌ ERROR: Client connection failed - disconnecting');
      print('Status: ${client.connectionStatus}');
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      client.disconnect();
    }
  }

  // Subscribe to topics
  void _subscribeToTopics() {
    print('📡 Subscribing to topics...');
    
    // Subscribe to sensor data
    _subscribeToTopic(_sensorDataTopic);
    
    // Subscribe to pump status
    _subscribeToTopic(_pumpStatusTopic);
    
    // Listen to all messages
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      print('📨 NEW MESSAGE from ${c[0].topic}:');
      print('📝 Content: $message');
      
      try {
        final data = json.decode(message) as Map<String, dynamic>;
        data['topic'] = c[0].topic;
        _dataController.add(data);
      } catch (e) {
        print('❌ Error parsing message: $e');
        print('Raw message: $message');
      }
    });
  }

  void _subscribeToTopic(String topicName) {
    print('📡 Subscribing to $topicName topic');
    client.subscribe(topicName, MqttQos.atMostOnce);
  }

  // ===========================================
  // PUBLISH MESSAGE FUNCTIONS
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

  // Method khusus untuk kontrol pump
  Future<bool> controlPump(bool activate) async {
    try {
      if (!isConnected) {
        print('❌ Cannot control pump - MQTT not connected');
        throw Exception('MQTT not connected');
      }

      final message = {
        'device': 'water_pump',
        'action': activate ? 'on' : 'off',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'flutter_app',
        'command_id': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      final jsonMessage = json.encode(message);
      bool success = await publishMessage(_pumpControlTopic, jsonMessage);
      
      if (success) {
        print('🚰 Pump control sent successfully: ${activate ? "ON" : "OFF"}');
      }
      
      return success;
      
    } catch (e) {
      print('❌ Error controlling pump: $e');
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
      data['timestamp'] = DateTime.now().toIso8601String();
      data['source'] = 'flutter_app';
      
      final jsonMessage = json.encode(data);
      return await publishMessage(topic, jsonMessage);
      
    } catch (e) {
      print('❌ Error publishing to topic $topic: $e');
      return false;
    }
  }

  // Method untuk publish sensor data
  Future<bool> publishSensorData(Map<String, dynamic> sensorData) async {
    return await publishToTopic(_sensorDataTopic, sensorData);
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

  // Method untuk test publish dengan konfirmasi
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

  // ===========================================
  // EXISTING METHODS (UNCHANGED)
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