import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  bool _isConnected = false;
  StreamController<Map<String, dynamic>>? _dataController;
  StreamSubscription? _messageSubscription;

  // MQTT Broker settings - Multiple configurations to try
  static const String _broker = 'mqtt.binatra.id';
  static const String _username = 'drip_flush_app';
  static const String _password = 'TeluJuara1';
  static const String _clientId = 'greenhouse_flutter_client';

  // Topics
  static const String _sensorDataTopic = 'greenhouse/sensors/data';
  static const String _pumpControlTopic = 'greenhouse/control/pump';
  static const String _pumpStatusTopic = 'greenhouse/pump/status';

  // Connection configurations to try
  final List<Map<String, dynamic>> _connectionConfigs = [
    {
      'port': 1883,
      'secure': false,
      'description': 'Standard MQTT (non-secure)',
    },
  ];

  // Getter untuk data stream dengan null check
  Stream<Map<String, dynamic>> get dataStream {
    _ensureStreamController();
    return _dataController!.stream;
  }

  // Ensure StreamController exists and is not closed
  void _ensureStreamController() {
    if (_dataController == null || _dataController!.isClosed) {
      _dataController = StreamController<Map<String, dynamic>>.broadcast();
      print('✅ StreamController created/recreated');
    }
  }

  // Safe method untuk add data ke stream
  void _safeAddToStream(Map<String, dynamic> data) {
    try {
      _ensureStreamController();
      if (_dataController != null && !_dataController!.isClosed) {
        _dataController!.add(data);
        print('📨 Data added to stream successfully');
      } else {
        print('⚠️ StreamController is closed, cannot add data');
      }
    } catch (e) {
      print('❌ Error adding to stream: $e');
    }
  }

  Future<bool> prepareMqttClient() async {
    print('🔄 Starting MQTT connection process...');
    
    // Try each configuration until one works
    for (int i = 0; i < _connectionConfigs.length; i++) {
      final config = _connectionConfigs[i];
      print('🔧 Trying configuration ${i + 1}/${_connectionConfigs.length}: ${config['description']}');
      
      bool success = await _tryConnection(
        port: config['port'],
        secure: config['secure'],
        configDescription: config['description'],
      );
      
      if (success) {
        print('✅ Successfully connected with configuration: ${config['description']}');
        return true;
      }
      
      // Wait before trying next configuration
      if (i < _connectionConfigs.length - 1) {
        print('⏳ Waiting 2 seconds before trying next configuration...');
        await Future.delayed(Duration(seconds: 2));
      }
    }
    
    print('❌ All connection configurations failed');
    return false;
  }

  Future<bool> _tryConnection({
    required int port,
    required bool secure,
    required String configDescription,
  }) async {
    try {
      print('🔌 Attempting connection to $_broker:$port (secure: $secure)');
      
      // Ensure fresh StreamController
      _ensureStreamController();

      // Dispose previous client if exists
      if (_client != null) {
        try {
          _client!.disconnect();
        } catch (e) {
          print('⚠️ Error disconnecting previous client: $e');
        }
      }

      final String clientId = '${_clientId}_${DateTime.now().millisecondsSinceEpoch}';
      _client = MqttServerClient.withPort(_broker, clientId, port);
      
      // Basic configuration
      _client!.logging(on: false); // Disable verbose logging to reduce noise
      _client!.setProtocolV311();
      _client!.keepAlivePeriod = 60; // Longer keep alive
      _client!.connectTimeoutPeriod = 15000; // 15 second timeout
      _client!.autoReconnect = true;
      _client!.resubscribeOnAutoReconnect = true;
      
      // Security configuration
      _client!.secure = secure;
      if (secure) {
        _client!.securityContext = SecurityContext.defaultContext;
        _client!.onBadCertificate = (X509Certificate cert) => true; // Accept all certificates for testing
      }

      // Setup callbacks
      _client!.onConnected = () {
        print('✅ MQTT: Connected successfully to $_broker:$port');
        _isConnected = true;
        _subscribeToTopics();
      };

      _client!.onDisconnected = () {
        print('🔌 MQTT: Disconnected from $_broker:$port');
        _isConnected = false;
      };

      _client!.onAutoReconnect = () {
        print('🔄 MQTT: Auto-reconnect triggered for $_broker:$port');
      };

      _client!.onAutoReconnected = () {
        print('✅ MQTT: Auto-reconnected successfully to $_broker:$port');
        _isConnected = true;
        _subscribeToTopics();
      };

      // Connection message with authentication
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(_username, _password)
          .withWillTopic('greenhouse/status/app')
          .withWillMessage('Flutter App Disconnected')
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      // Attempt connection with timeout
      try {
        print('⏳ Connecting to $_broker:$port...');
        final connectFuture = _client!.connect();
        await connectFuture.timeout(Duration(seconds: 15));

        if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
          print('✅ MQTT: Connection established to $_broker:$port');
          _isConnected = true;
          _setupMessageListener();
          await _subscribeToTopics();
          
          // Test connection with a ping
          bool pingSuccess = await _testConnection();
          if (pingSuccess) {
            print('✅ MQTT: Connection test successful');
            return true;
          } else {
            print('⚠️ MQTT: Connection test failed, but connection seems stable');
            return true; // Still return true as basic connection works
          }
        } else {
          print('❌ MQTT: Connection failed - ${_client!.connectionStatus}');
          return false;
        }
      } on TimeoutException catch (e) {
        print('❌ MQTT: Connection timeout - $e');
        _client!.disconnect();
        return false;
      } on NoConnectionException catch (e) {
        print('❌ MQTT: No connection exception - $e');
        _client!.disconnect();
        return false;
      } on SocketException catch (e) {
        print('❌ MQTT: Socket exception - $e');
        _client!.disconnect();
        return false;
      }
    } catch (e) {
      print('❌ MQTT: Connection attempt failed with $configDescription - $e');
      if (_client != null) {
        try {
          _client!.disconnect();
        } catch (disconnectError) {
          print('⚠️ Error during cleanup disconnect: $disconnectError');
        }
      }
      return false;
    }
  }

  Future<bool> _testConnection() async {
    try {
      // Test connection with a simple publish
      final testData = {
        'test': true,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'connection_test',
        'client_id': _client?.clientIdentifier ?? 'unknown',
      };

      return await publishToTopic('greenhouse/test/connection', testData);
    } catch (e) {
      print('❌ Connection test failed: $e');
      return false;
    }
  }

  void _setupMessageListener() {
    try {
      // Cancel previous subscription if exists
      _messageSubscription?.cancel();

      if (_client?.updates != null) {
        _messageSubscription = _client!.updates!.listen(
          (List<MqttReceivedMessage<MqttMessage?>>? c) {
            _handleMqttMessage(c);
          },
          onError: (error) {
            print('❌ MQTT message listener error: $error');
          },
          onDone: () {
            print('📝 MQTT message listener done');
          },
        );
      }
    } catch (e) {
      print('❌ Error setting up message listener: $e');
    }
  }

  void _handleMqttMessage(List<MqttReceivedMessage<MqttMessage?>>? c) {
    try {
      if (c != null && c.isNotEmpty) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String topic = c[0].topic;
        final String message = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        print('📨 MQTT: Received from $topic: $message');

        // Handle empty or invalid messages
        if (message.trim().isEmpty) {
          print('⚠️ MQTT: Empty message received from $topic');
          return;
        }

        try {
          // Try to parse as JSON
          var jsonData = jsonDecode(message) as Map<String, dynamic>;

          // Add topic and timestamp info
          jsonData['topic'] = topic;
          jsonData['received_at'] = DateTime.now().toIso8601String();

          // If this is a pump control command, convert it to status format
          if (topic == _pumpControlTopic) {
            jsonData = _convertControlToStatus(jsonData);
          }

          // Safe add to stream
          _safeAddToStream(jsonData);

          print('✅ MQTT: Successfully parsed JSON from $topic');
        } catch (jsonError) {
          print('⚠️ MQTT: Message is not valid JSON, treating as raw text');
          print('Raw message: $message');

          // Handle non-JSON messages
          final rawData = <String, dynamic>{
            'topic': topic,
            'raw_message': message,
            'message_type': 'text',
            'received_at': DateTime.now().toIso8601String(),
          };

          // Try to extract simple key-value pairs if it looks like them
          if (message.contains('=') || message.contains(':')) {
            rawData['parsed_attempt'] = _tryParseSimpleFormat(message);
          }

          _safeAddToStream(rawData);
        }
      }
    } catch (e) {
      print('❌ Error handling MQTT message: $e');

      // Add error info to stream for debugging
      final errorData = <String, dynamic>{
        'error': true,
        'error_message': e.toString(),
        'error_type': 'message_handling_error',
        'timestamp': DateTime.now().toIso8601String(),
      };

      _safeAddToStream(errorData);
    }
  }

  Map<String, dynamic> _convertControlToStatus(Map<String, dynamic> controlData) {
    // Extract the action and convert to is_active
    bool isActive = false;
    if (controlData.containsKey('action')) {
      final action = controlData['action'].toString().toLowerCase();
      isActive = action == 'on' || action == 'start' || action == 'activate';
    }

    // Create status format that provider expects
    final statusData = {
      'device': controlData['device'] ?? 'water_pump',
      'is_active': isActive,
      'timestamp': controlData['timestamp'] ?? DateTime.now().toIso8601String(),
      'source': controlData['source'] ?? 'mqtt_service',
      'command_id': controlData['command_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'topic': _pumpStatusTopic,
    };

    return statusData;
  }

  Map<String, dynamic> _tryParseSimpleFormat(String message) {
    final Map<String, dynamic> result = {};

    try {
      // Handle key=value format
      if (message.contains('=')) {
        final pairs = message.split(',');
        for (String pair in pairs) {
          final keyValue = pair.trim().split('=');
          if (keyValue.length == 2) {
            String key = keyValue[0].trim();
            String value = keyValue[1].trim();

            // Try to convert to appropriate type
            if (double.tryParse(value) != null) {
              result[key] = double.parse(value);
            } else if (value.toLowerCase() == 'true' || value.toLowerCase() == 'false') {
              result[key] = value.toLowerCase() == 'true';
            } else {
              result[key] = value;
            }
          }
        }
      }
      // Handle key:value format
      else if (message.contains(':')) {
        final pairs = message.split(',');
        for (String pair in pairs) {
          final keyValue = pair.trim().split(':');
          if (keyValue.length == 2) {
            String key = keyValue[0].trim().replaceAll('"', '');
            String value = keyValue[1].trim().replaceAll('"', '');

            // Try to convert to appropriate type
            if (double.tryParse(value) != null) {
              result[key] = double.parse(value);
            } else if (value.toLowerCase() == 'true' || value.toLowerCase() == 'false') {
              result[key] = value.toLowerCase() == 'true';
            } else {
              result[key] = value;
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing simple format: $e');
      result['parse_error'] = e.toString();
    }

    return result;
  }

  Future<void> _subscribeToTopics() async {
    try {
      if (_client != null && isConnected) {
        // Subscribe to topics with retry mechanism
        final topics = [
          'greenhouse/sensors/soil',
          'greenhouse/sensors/+',
          'greenhouse/status/+',
          _pumpStatusTopic,
          _pumpControlTopic,
        ];

        for (String topic in topics) {
          try {
            _client!.subscribe(topic, MqttQos.atMostOnce);
            print('✅ Subscribed to: $topic');
            await Future.delayed(Duration(milliseconds: 100)); // Small delay between subscriptions
          } catch (e) {
            print('❌ Failed to subscribe to $topic: $e');
          }
        }

        print('✅ MQTT: Topic subscription completed');
      }
    } catch (e) {
      print('❌ MQTT subscription error: $e');
    }
  }

  Future<bool> controlPump(bool activate) async {
    try {
      if (!isConnected) {
        print('❌ Cannot control pump - MQTT not connected');
        throw Exception('MQTT not connected');
      }

      final timestamp = DateTime.now().toIso8601String();
      final commandId = DateTime.now().millisecondsSinceEpoch.toString();

      print('🔧 Controlling pump: ${activate ? 'ON' : 'OFF'}');

      // 1. Send control command (original format)
      final controlMessage = {
        'device': 'water_pump',
        'action': activate ? 'on' : 'off',
        'timestamp': timestamp,
        'source': 'flutter_app',
        'command_id': commandId,
      };

      final controlJson = jsonEncode(controlMessage);
      bool controlSuccess = await publishMessage(_pumpControlTopic, controlJson);

      // 2. Also send status message (provider-friendly format)
      final statusMessage = {
        'device': 'water_pump',
        'is_active': activate,
        'status': activate ? 'on' : 'off',
        'timestamp': timestamp,
        'source': 'flutter_app',
        'command_id': commandId,
      };

      final statusJson = jsonEncode(statusMessage);
      bool statusSuccess = await publishMessage(_pumpStatusTopic, statusJson);

      if (controlSuccess && statusSuccess) {
        print('✅ Both control and status messages published');
        return true;
      } else {
        print('⚠️ Partial success - Control: $controlSuccess, Status: $statusSuccess');
        return controlSuccess || statusSuccess;
      }
    } catch (e) {
      print('❌ Error controlling pump: $e');
      return false;
    }
  }

  Future<bool> publishMessage(String topic, String message) async {
    try {
      if (!isConnected) {
        throw Exception('MQTT not connected. Current state: $_isConnected');
      }

      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
      builder.addString(message);

      // Publish dengan QoS level 1 untuk memastikan delivery
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

      print('✅ Message published successfully to $topic');
      return true;
    } catch (e) {
      print('❌ Error publishing message: $e');
      return false;
    }
  }

  Future<bool> publishToTopic(String topic, Map<String, dynamic> data) async {
    try {
      if (!isConnected || _client == null) {
        print('⚠️ MQTT: Cannot publish - not connected');
        return false;
      }

      final String jsonMessage = jsonEncode(data);
      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
      builder.addString(jsonMessage);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('📤 MQTT: Published to $topic: $jsonMessage');
      return true;
    } catch (e) {
      print('❌ MQTT publish error: $e');
      return false;
    }
  }

  Future<bool> publishMessageWithRetry(String topic, String message, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (!isConnected) {
          print('⚠️ MQTT: Attempt $attempt - not connected, trying to reconnect...');
          bool reconnected = await prepareMqttClient();
          if (!reconnected) {
            if (attempt < maxRetries) {
              await Future.delayed(Duration(seconds: attempt * 2));
              continue;
            }
            return false;
          }
        }

        final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
        builder.addString(message);

        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        print('📤 MQTT: Published with retry (attempt $attempt) to $topic: $message');
        return true;
      } catch (e) {
        print('❌ MQTT publish retry attempt $attempt failed: $e');
        if (attempt == maxRetries) {
          return false;
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return false;
  }

  Future<bool> testPublishWithConfirmation() async {
    try {
      final testData = {
        'test': true,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'test_function',
        'connection_info': getConnectionInfo(),
      };

      return await publishToTopic('greenhouse/test/connection', testData);
    } catch (e) {
      print('❌ MQTT test publish error: $e');
      return false;
    }
  }

  Future<bool> requestLatestData() async {
    try {
      final requestData = {
        'action': 'request_data',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'mobile_app',
      };

      return await publishToTopic('greenhouse/request/data', requestData);
    } catch (e) {
      print('❌ MQTT request data error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      print('🔌 MQTT: Disconnecting...');

      _isConnected = false;

      // Cancel message subscription first
      _messageSubscription?.cancel();
      _messageSubscription = null;

      // Disconnect client
      if (_client != null) {
        _client!.disconnect();
      }

      print('✅ MQTT: Disconnected successfully');
    } catch (e) {
      print('❌ MQTT disconnect error: $e');
    }
  }

  bool get isConnected {
    return _client?.connectionStatus?.state == MqttConnectionState.connected && _isConnected;
  }

  // Method untuk publish sensor data
  Future<bool> publishSensorData(Map<String, dynamic> sensorData) async {
    try {
      if (!isConnected) {
        print('⚠️ MQTT: Cannot publish sensor data - not connected');
        return false;
      }

      // Add timestamp dan source info
      final dataToSend = Map<String, dynamic>.from(sensorData);
      dataToSend['timestamp'] = DateTime.now().toIso8601String();
      dataToSend['source'] = 'mobile_app';

      return await publishToTopic(_sensorDataTopic, dataToSend);
    } catch (e) {
      print('❌ MQTT publish sensor data error: $e');
      return false;
    }
  }

  // Method untuk publish soil humidity data
  Future<bool> publishSoilHumidity(double humidity) async {
    try {
      final soilData = {
        'sensor_type': 'soil_humidity',
        'value': humidity,
        'unit': 'percentage',
        'device_id': 'mobile_sensor',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'mobile_app',
      };

      return await publishSensorData(soilData);
    } catch (e) {
      print('❌ MQTT publish soil humidity error: $e');
      return false;
    }
  }

  // Method untuk publish multiple sensor readings
  Future<bool> publishMultipleSensorData(Map<String, double> sensors) async {
    try {
      final sensorData = {
        'sensors': sensors,
        'reading_time': DateTime.now().toIso8601String(),
        'device_id': 'mobile_multi_sensor',
        'source': 'mobile_app',
      };

      return await publishSensorData(sensorData);
    } catch (e) {
      print('❌ MQTT publish multiple sensor data error: $e');
      return false;
    }
  }

  // Method untuk publish status update
  Future<bool> publishStatusUpdate(String status, {Map<String, dynamic>? additionalData}) async {
    try {
      final statusData = {
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'mobile_app',
        ...?additionalData,
      };

      return await publishToTopic('greenhouse/status/app', statusData);
    } catch (e) {
      print('❌ MQTT publish status error: $e');
      return false;
    }
  }

  // Method untuk send command to device
  Future<bool> sendDeviceCommand(String deviceId, String command, {Map<String, dynamic>? params}) async {
    try {
      final commandData = {
        'device_id': deviceId,
        'command': command,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'mobile_app',
        ...?params,
      };

      return await publishToTopic('greenhouse/commands/$deviceId', commandData);
    } catch (e) {
      print('❌ MQTT send device command error: $e');
      return false;
    }
  }

  // Method untuk publish environment data
  Future<bool> publishEnvironmentData({
    double? temperature,
    double? humidity,
    double? soilMoisture,
    double? lightLevel,
  }) async {
    try {
      final envData = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'mobile_app',
      };

      if (temperature != null) envData['temperature'] = temperature;
      if (humidity != null) envData['humidity'] = humidity;
      if (soilMoisture != null) envData['soil_moisture'] = soilMoisture;
      if (lightLevel != null) envData['light_level'] = lightLevel;

      return await publishToTopic('greenhouse/environment/data', envData);
    } catch (e) {
      print('❌ MQTT publish environment data error: $e');
      return false;
    }
  }

  // Method untuk get connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'connected': isConnected,
      'client_id': _client?.clientIdentifier ?? 'unknown',
      'server_host': _client?.server ?? 'unknown',
      'server_port': _client?.port ?? 0,
      'connection_state': _client?.connectionStatus?.state.toString() ?? 'unknown',
      'last_ping': DateTime.now().toIso8601String(),
      'auto_reconnect': _client?.autoReconnect ?? false,
    };
  }

  // Method untuk force reconnect
  Future<bool> forceReconnect() async {
    print('🔄 Force reconnecting MQTT...');
    
    try {
      // Disconnect first
      await disconnect();
      await Future.delayed(Duration(seconds: 2));
      
      // Try to reconnect
      return await prepareMqttClient();
    } catch (e) {
      print('❌ Force reconnect failed: $e');
      return false;
    }
  }

  void dispose() {
    try {
      print('🗑️ MQTT: Disposing service...');

      // Cancel subscription
      _messageSubscription?.cancel();
      _messageSubscription = null;

      // Disconnect client
      disconnect();

      // Close and nullify StreamController
      if (_dataController != null && !_dataController!.isClosed) {
        _dataController!.close();
      }
      _dataController = null;

      print('✅ MQTT: Service disposed successfully');
    } catch (e) {
      print('❌ MQTT dispose error: $e');
    }
  }
}