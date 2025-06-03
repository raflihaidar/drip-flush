import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../widgets/common/custom_card.dart';
import '../../widgets/common/sensor_card.dart';
import '../../services/mqtt_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MqttService _mqttService = MqttService();
  late StreamSubscription _mqttSubscription;
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  
  // Soil sensor data variables - DEFAULT TO 0
  double _soilTemperature = 0.0; // Changed from 0 to 0.0 for clarity
  bool _isConnected = false;
  String _lastUpdate = 'Never';
  
  // Weather data (static)
  double _weatherTemperature = 40.0;
  String _weatherCondition = 'Sunny';
  int _weatherHumidity = 45; // Weather humidity (not soil)
  
  // Temperature limits and alarms
  // double _upperLimit = 24.0;
  // double _upperAlarm = 30.0;
  // double _lowerLimit = 4.0;
  // double _lowerAlarm = 1.0;
  
  // 24-hour min/max tracking - Start with 0 when no data
  double _maxTemp24h = 0.0;
  double _minTemp24h = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeMqtt();
    // _setupAutoRefresh();
  }

  void _setupAutoRefresh() {
    // Auto refresh every 30 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isRefreshing) {
        _autoRefreshMqtt();
      }
    });
  }

  Future<void> _autoRefreshMqtt() async {    
    // Check if connection is still active
    if (!_isConnected) {
      await _initializeMqtt();
    }
    
    // Update last check time
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _lastUpdate = '${_formatHour(now.hour)}:${_formatMinute(now.minute)}';
      });
    }
  }

  Future<void> _initializeMqtt() async {
    try {
      // Connect to MQTT
      bool connected = await _mqttService.prepareMqttClient();
      
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
      
      if (connected) {
        // Cancel existing subscription if any
        try {
          await _mqttSubscription.cancel();
        } catch (e) {
          // Ignore error if subscription doesn't exist
        }
        
        // Listen to MQTT data stream
        _mqttSubscription = _mqttService.dataStream.listen(
          _handleMqttData,
          onError: (error) {
            print('❌ MQTT Stream Error: $error');
            if (mounted) {
              setState(() {
                _isConnected = false;
              });
            }
          },
        );
        
        print('✅ MQTT initialized successfully');
      } else {
        print('❌ Failed to connect to MQTT');
      }
    } catch (e) {
      print('❌ Error initializing MQTT: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      }
    }
  }

  void _handleMqttData(Map<String, dynamic> data) {
    print('📨 Received MQTT data: $data');
    
    if (!mounted) return;
    
    final topic = data['topic'] as String?;
    final now = DateTime.now();
    
    setState(() {
      _lastUpdate = '${_formatHour(now.hour)}:${_formatMinute(now.minute)}';
    });
    
    // Handle ONLY soil sensor data
    if (topic == 'greenhouse/sensors/soil' || 
        topic == 'greenhouse/sensors/data' ||
        topic == 'greenhouse/control/pump') {
      setState(() {
        // Update ONLY soil temperature from MQTT
        if (data['soil_temperature'] != null) {
          _soilTemperature = (data['soil_temperature'] as num).toDouble();
          _updateMinMaxTemperature(_soilTemperature);
          print('🌡️ Soil temperature updated: $_soilTemperature°C');
        }
        // Also check for temperature field (alternative naming)
        else if (data['temperature'] != null) {
          _soilTemperature = (data['temperature'] as num).toDouble();
          _updateMinMaxTemperature(_soilTemperature);
          print('🌡️ Soil temperature updated: $_soilTemperature°C');
        }
      });
    }
  }

  void _updateMinMaxTemperature(double temperature) {
    // Only update min/max if we have real data (not 0)
    if (temperature > 0) {
      if (_maxTemp24h == 0.0 || temperature > _maxTemp24h) {
        _maxTemp24h = temperature;
      }
      if (_minTemp24h == 0.0 || temperature < _minTemp24h) {
        _minTemp24h = temperature;
      }
    }
  }

  // Manual refresh function
  Future<void> _refreshData() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      await _initializeMqtt();
      
      // Test publish to trigger sensor response
      if (_isConnected) {
        await _mqttService.testPublishWithConfirmation();
      }
      
      _showSnackBar('🔄 Data refreshed manually');
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
    _mqttSubscription.cancel();
    _mqttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Get current date and time
    final now = DateTime.now();
    final formattedDate = '${_getDayName(now.weekday)}, ${now.day} ${_getMonthName(now.month)} ${now.year}';
    final formattedTime = '${_formatHour(now.hour)}:${_formatMinute(now.minute)} ${now.hour >= 12 ? 'PM' : 'AM'}';
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top navigation bar with connection status
              Container(
                height: 50,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // Connection status indicator with auto-refresh info
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isConnected ? Colors.green.shade100 : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              _isConnected ? Icons.wifi : Icons.sensors,
                              color: _isConnected ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                          ),
                          // Auto-refresh indicator
                          if (_isConnected)
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.brown.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.grass,
                        color: Colors.brown.shade600,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Manual refresh button
                    GestureDetector(
                      onTap: _isRefreshing ? null : _refreshData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _isRefreshing ? Colors.grey.shade200 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isRefreshing
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
              
              // Title with sensor status and auto-refresh info
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
                          color: _isConnected ? Colors.green : Colors.orange,
                          size: 8,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isConnected 
                            ? 'Soil Sensor Active • Last: $_lastUpdate'
                            : 'Soil Sensor Disconnected',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isConnected ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
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
                      child: Row(
                        children: [
                          const Text(
                            'Weather Data - Jambangan Area',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          // Static indicator
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // White gap
              const SizedBox(height: 10),
              
              // Current soil conditions card
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
                            'Soil Temperature Monitoring',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.grass,
                            color: Colors.brown.shade600,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    
                    // Soil temperature display
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                      child: Row(
                        children: [
                          // Soil condition icon and status
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _getSoilConditionIcon(),
                                color: _getSoilConditionColor(),
                                size: 32,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getSoilConditionText(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Current soil temperature with special handling for 0
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _soilTemperature == 0.0 ? '--' : _soilTemperature.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w500,
                                  color: _soilTemperature == 0.0 ? Colors.grey : Colors.black,
                                ),
                              ),
                              Text(
                                '°C',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                  color: _soilTemperature == 0.0 ? Colors.grey : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Soil sensor info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.brown.shade50,
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
                            'Soil Sensor - Green House Satu Padu',
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
                              color: _isConnected 
                                ? Colors.green.shade100 
                                : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: _isConnected ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isConnected ? 'MQTT' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _isConnected ? Colors.green : Colors.orange,
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
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Get soil condition based on temperature - with special handling for 0
  IconData _getSoilConditionIcon() {
    if (_soilTemperature == 0.0) {
      return Icons.help_outline; // No data
    } else if (_soilTemperature < 16) {
      return Icons.ac_unit; // Cold
    } else if (_soilTemperature > 22) {
      return Icons.wb_sunny; // Hot
    } else {
      return Icons.eco; // Optimal
    }
  }

  Color _getSoilConditionColor() {
    if (_soilTemperature == 0.0) {
      return Colors.grey; // No data
    } else if (_soilTemperature < 16) {
      return Colors.blue; // Cold
    } else if (_soilTemperature > 22) {
      return Colors.orange; // Hot
    } else {
      return Colors.green; // Optimal
    }
  }

  String _getSoilConditionText() {
    if (_soilTemperature == 0.0) {
      return 'No Data';
    } else if (_soilTemperature < 16) {
      return 'Cold';
    } else if (_soilTemperature > 22) {
      return 'Hot';
    } else {
      return 'Optimal';
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

  // Temperature status helpers - with special handling for 0
  // Color _getTemperatureStatusColor() {
  //   if (_soilTemperature == 0.0) return Colors.grey;
  //   if (_soilTemperature < _lowerAlarm) return Colors.red;
  //   if (_soilTemperature < _lowerLimit) return Colors.orange;
  //   if (_soilTemperature > _upperAlarm) return Colors.red;
  //   if (_soilTemperature > _upperLimit) return Colors.orange;
  //   return Colors.green;
  // }

  // IconData _getTemperatureStatusIcon() {
  //   if (_soilTemperature == 0.0) return Icons.help_outline;
  //   if (_soilTemperature < _lowerAlarm || _soilTemperature > _upperAlarm) {
  //     return Icons.warning;
  //   }
  //   if (_soilTemperature < _lowerLimit || _soilTemperature > _upperLimit) {
  //     return Icons.info;
  //   }
  //   return Icons.check_circle;
  // }

  // String _getTemperatureStatusText() {
  //   if (_soilTemperature == 0.0) return 'No temperature data available';
  //   if (_soilTemperature < _lowerAlarm) return 'Temperature too low - Critical!';
  //   if (_soilTemperature < _lowerLimit) return 'Temperature below optimal range';
  //   if (_soilTemperature > _upperAlarm) return 'Temperature too high - Critical!';
  //   if (_soilTemperature > _upperLimit) return 'Temperature above optimal range';
  //   return 'Temperature is optimal for plant growth';
  // }
}