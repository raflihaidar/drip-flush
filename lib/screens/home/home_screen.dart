import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/greenhouse_provider.dart';
import '../../services/mqtt_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  
  // MQTT Service untuk reconnect (sama seperti control screen)
  MqttService? _mqttService;
  bool _mqttConnected = false;
  bool _isConnecting = false;
  
  // Weather data (static)
  final double _weatherTemperature = 40.0;
  final String _weatherCondition = 'Sunny';
  final int _weatherHumidity = 45;
  
  // 24-hour min/max tracking
  double _maxHumidity24h = 0.0;
  double _minHumidity24h = 100.0;

  @override
  void initState() {
    super.initState();
    _setupAutoRefresh();
    _initializeMqtt(); // Sama seperti control screen
    _listenToMqttMessages(); // Sama seperti control screen
  }

  void _setupAutoRefresh() {
    // Auto refresh every 30 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        context.read<GreenhouseProvider>().refreshData();
      }
    });
  }

  // Method MQTT initialization sama seperti control screen
  Future<void> _initializeMqtt() async {
    try {
      // Create fresh instance setiap kali
      _mqttService = MqttService();
      
      bool connected = await _mqttService!.prepareMqttClient();
      if (mounted) {
        setState(() {
          _mqttConnected = connected;
        });
      }
      print(_mqttConnected ? '✅ MQTT Connected for Home' : '❌ MQTT Failed to Connect for Home');
    } catch (e) {
      print('❌ Error initializing MQTT in Home: $e');
      if (mounted) {
        setState(() {
          _mqttConnected = false;
        });
      }
    }
  }

  // Method listen MQTT messages sama seperti control screen
  void _listenToMqttMessages() {
    if (_mqttService != null) {
      _mqttService!.dataStream.listen(
        (data) {
          print('📨 Home received MQTT data: $data');
          
          // Handle different data formats
          _processIncomingMqttData(data);
        },
        onError: (error) {
          print('❌ Home MQTT stream error: $error');
        },
      );
    }
  }

  // Method untuk process incoming MQTT data
  void _processIncomingMqttData(Map<String, dynamic> data) {
    try {
      // Handle sensor data
      if (data.containsKey('value') && data.containsKey('device_id')) {
        final deviceId = data['device_id'] as String?;
        final value = data['value'];
        
        if (deviceId != null && deviceId.contains('esp32')) {
          // This looks like sensor data
          double? sensorValue;
          
          if (value is num) {
            sensorValue = value.toDouble();
          } else if (value is String) {
            sensorValue = double.tryParse(value);
          }
          
          if (sensorValue != null) {
            print('🌱 Processing sensor value: $sensorValue from $deviceId');
            
            // Update local state atau provider
            // context.read<GreenhouseProvider>().updateSoilHumidity(sensorValue);
            
            // Atau update state lokal jika tidak menggunakan provider
            if (mounted) {
              setState(() {
                // Update local sensor data if needed
              });
            }
          }
        }
      }
      
      // Handle other data formats
      if (data.containsKey('soil_humidity')) {
        final humidity = data['soil_humidity'];
        if (humidity is num) {
          print('🌱 Processing soil humidity: ${humidity.toDouble()}%');
        }
      }
      
      if (data.containsKey('humidity')) {
        final humidity = data['humidity'];
        if (humidity is num) {
          print('🌱 Processing humidity: ${humidity.toDouble()}%');
        }
      }
      
      // Handle pump status
      if (data.containsKey('pump_status') || data.containsKey('is_active')) {
        final isActive = data['pump_status'] ?? data['is_active'];
        if (isActive is bool) {
          print('💧 Processing pump status: ${isActive ? "ON" : "OFF"}');
        }
      }
      
      // Handle error messages
      if (data.containsKey('error') && data['error'] == true) {
        final errorMsg = data['error_message'] ?? 'Unknown MQTT error';
        print('❌ MQTT Error received: $errorMsg');
        _showSnackBar('MQTT Error: $errorMsg');
      }
      
      // Handle raw messages
      if (data.containsKey('raw_message') && data.containsKey('message_type')) {
        final rawMsg = data['raw_message'];
        print('📝 Raw MQTT message: $rawMsg');
        
        // Try to extract useful info from raw message
        if (rawMsg.toString().contains('humidity') || rawMsg.toString().contains('moisture')) {
          print('🌱 Raw message might contain sensor data');
        }
      }
      
    } catch (e) {
      print('❌ Error processing MQTT data: $e');
    }
  }

  // Method reconnect MQTT sama seperti control screen
  Future<void> _reconnectMqtt() async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
    });
    
    try {
      // Dispose old instance first
      _mqttService?.dispose();
      
      // Create fresh instance
      _mqttService = MqttService();
      
      bool connected = await _mqttService!.prepareMqttClient();
      if (mounted) {
        setState(() {
          _mqttConnected = connected;
        });
        
        // Setup listener lagi setelah reconnect
        if (connected) {
          _listenToMqttMessages();
        }
        
        _showSnackBar(connected 
          ? '✅ MQTT Reconnected successfully!' 
          : '❌ MQTT Reconnection failed');
      }
    } catch (e) {
      print('❌ MQTT Reconnect error in Home: $e');
      if (mounted) {
        _showSnackBar('❌ MQTT Reconnection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _updateMinMaxHumidity(double humidity) {
    if (humidity > 0) {
      if (_maxHumidity24h == 0.0 || humidity > _maxHumidity24h) {
        _maxHumidity24h = humidity;
      }
      if (_minHumidity24h == 100.0 || humidity < _minHumidity24h) {
        _minHumidity24h = humidity;
      }
    }
  }

  // Manual refresh function
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      // Jika MQTT tidak connected, coba reconnect dulu
      if (!_mqttConnected) {
        await _reconnectMqtt();
      }
      
      await context.read<GreenhouseProvider>().refreshData();
      _showSnackBar('🔄 Data refreshed successfully');
    } catch (e) {
      _showSnackBar('❌ Refresh failed: $e');
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _mqttService?.dispose(); // Dispose MQTT service sama seperti control screen
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<GreenhouseProvider>(
          builder: (context, provider, child) {
            // Get sensor data
            final soilHumidity = provider.currentSoilHumidity ?? 0.0;
            final soilCondition = provider.soilCondition ?? 'No Data';
            final isConnected = provider.isConnected || _mqttConnected; // Kombinasi provider dan MQTT
            final lastUpdate = provider.sensorData != null ? 'Active' : 'Never';
            
            // Update min/max tracking
            if (soilHumidity > 0) {
              _updateMinMaxHumidity(soilHumidity);
            }
            
            // Get current date and time
            final now = DateTime.now();
            final formattedDate = '${_getDayName(now.weekday)}, ${now.day} ${_getMonthName(now.month)} ${now.year}';
            final formattedTime = '${_formatHour(now.hour)}:${_formatMinute(now.minute)} ${now.hour >= 12 ? 'PM' : 'AM'}';
            
            return SingleChildScrollView(
              child: Column(
                children: [
                  // Top navigation bar with connection status
                  Container(
                    height: 50,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        // Connection status indicator dengan tap untuk reconnect
                        GestureDetector(
                          onTap: !isConnected && !_isConnecting ? _reconnectMqtt : null,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isConnected ? Colors.green.shade100 : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: _isConnecting
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                        ),
                                      )
                                    : Icon(
                                        isConnected ? Icons.wifi : Icons.wifi_off,
                                        color: isConnected ? Colors.green : Colors.orange,
                                        size: 20,
                                      ),
                                ),
                                // Auto-refresh indicator
                                if (isConnected && !_isConnecting)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Weather indicator
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.wb_sunny,
                            color: Colors.orange.shade600,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Soil sensor indicator
                        // Container(
                        //   width: 40,
                        //   height: 40,
                        //   decoration: BoxDecoration(
                        //     color: Colors.brown.shade100,
                        //     borderRadius: BorderRadius.circular(8),
                        //   ),
                        //   child: Icon(
                        //     Icons.water_drop,
                        //     color: Colors.brown.shade600,
                        //     size: 20,
                        //   ),
                        // ),
                        const SizedBox(width: 10),
                        // Manual refresh button dengan reconnect capability
                        GestureDetector(
                          onTap: (_isRefreshing || _isConnecting) ? null : _refreshData,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: (_isRefreshing || _isConnecting) ? Colors.grey.shade200 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: (_isRefreshing || _isConnecting)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh,
                                  size: 20,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // White gap
                  const SizedBox(height: 10),
                  
                  // Title with sensor status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    color: Colors.white,
                    child: Column(
                      children: [
                        const Text(
                          'Smart Tani Telkom University',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.circle,
                              color: isConnected ? Colors.green : Colors.orange,
                              size: 8,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConnected 
                                ? 'Soil Sensor Active • Last: $lastUpdate'
                                : (_isConnecting 
                                    ? 'Reconnecting to Soil Sensor...'
                                    : 'Soil Sensor Disconnected • Tap WiFi to reconnect'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isConnected 
                                  ? Colors.green 
                                  : (_isConnecting ? Colors.blue : Colors.orange),
                              ),
                            ),
                          ],
                        ),
                        // Show loading indicator if provider is loading
                        if (provider.isLoading || _isConnecting)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        // Show error message if any
                        if (provider.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              provider.errorMessage!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // White gap
                  const SizedBox(height: 10),
                  
                  // Weather card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Location and date row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                          child: Row(
                            children: [
                              // Location with icon
                              Row(
                                children: const [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Jambangan, Indonesia',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Date and time
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formattedDate,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    formattedTime,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Weather conditions
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                          child: Row(
                            children: [
                              // Weather condition icon and status
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.wb_sunny,
                                    color: Colors.orange,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _weatherCondition,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Weather humidity
                                  Text(
                                    'Humidity: ${_weatherHumidity}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Current weather temperature
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _weatherTemperature.toStringAsFixed(0),
                                    style: const TextStyle(
                                      fontSize: 64,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Text(
                                    '°C',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Weather info
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                'Weather Data - Jambangan Area',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // White gap
                  const SizedBox(height: 10),
                  
                  // Current soil conditions card - Updated for humidity
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Soil conditions header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                          child: Row(
                            children: [
                              const Text(
                                'Soil Humidity Monitoring',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.water_drop,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                        
                        // Soil humidity display
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                          child: Row(
                            children: [
                              // Soil condition icon and status
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _getSoilConditionIcon(soilHumidity),
                                    color: _getSoilConditionColor(soilHumidity),
                                    size: 32,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    soilCondition,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Current soil humidity
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    soilHumidity == 0.0 ? '0.0' : soilHumidity.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: 64,
                                      fontWeight: FontWeight.w500,
                                      color: soilHumidity == 0.0 ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '%',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                      color: soilHumidity == 0.0 ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // 24h min/max display
                        if (_maxHumidity24h > 0.0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                            child: Row(
                              children: [
                                Text(
                                  '24h Range: ${_minHumidity24h.toStringAsFixed(1)}% - ${_maxHumidity24h.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        // Soil sensor info
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Soil Sensor - Firebase Connected',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              // Connection status indicator
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isConnected 
                                    ? Colors.green.shade100 
                                    : (_isConnecting 
                                        ? Colors.blue.shade100
                                        : Colors.orange.shade100),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: isConnected 
                                        ? Colors.green 
                                        : (_isConnecting ? Colors.blue : Colors.orange),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isConnected 
                                        ? 'ONLINE' 
                                        : (_isConnecting ? 'CONNECTING' : 'OFFLINE'),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isConnected 
                                          ? Colors.green 
                                          : (_isConnecting ? Colors.blue : Colors.orange),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // White gap
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Get soil condition based on humidity
  IconData _getSoilConditionIcon(double humidity) {
    if (humidity == 0.0) {
      return Icons.help_outline; // No data
    } else if (humidity < 40) {
      return Icons.warning; // Dry
    } else if (humidity > 70) {
      return Icons.water_drop; // Too wet
    } else {
      return Icons.eco; // Optimal
    }
  }

  Color _getSoilConditionColor(double humidity) {
    if (humidity == 0.0) {
      return Colors.grey; // No data
    } else if (humidity < 40) {
      return Colors.orange; // Dry
    } else if (humidity > 70) {
      return Colors.blue; // Too wet
    } else {
      return Colors.green; // Optimal
    }
  }
  
  // Helper methods for date formatting
  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                   'July', 'August', 'September', 'October', 'November', 'December'];
    return months[month - 1];
  }

  String _formatHour(int hour) {
    int h = hour > 12 ? hour - 12 : hour;
    h = h == 0 ? 12 : h;
    return h.toString().padLeft(2, '0');
  }

  String _formatMinute(int minute) {
    return minute.toString().padLeft(2, '0');
  }
}