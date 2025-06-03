import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../widgets/common/custom_card.dart';
import '../../services/mqtt_service.dart';

class ControlScreen extends StatefulWidget {
  @override
  _ControlScreenState createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> with TickerProviderStateMixin {
  bool isPumpActive = false;
  bool isWateringScheduled = false;
  double wateringDuration = 5.0;
  bool isConnected = false;
  bool isSendingCommand = false; // Untuk loading state
  
  final MqttService _mqttService = MqttService();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeMqtt();
    _setupAnimations();
    _listenToMqttMessages();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _initializeMqtt() async {
    try {
      bool connected = await _mqttService.prepareMqttClient();
      if (mounted) {
        setState(() {
          isConnected = connected;
        });
      }
      print(isConnected ? '✅ MQTT Connected for Control' : '❌ MQTT Failed to Connect');
    } catch (e) {
      print('❌ Error initializing MQTT: $e');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    }
  }

  void _listenToMqttMessages() {
    _mqttService.dataStream.listen((data) {
      print('📨 Received MQTT data: $data');
      
      // Handle pump status updates
      if (data['topic'] == 'greenhouse/pump/status' || 
          data['topic'] == 'greenhouse/control/pump') {
        
        if (data.containsKey('action') || data.containsKey('status')) {
          String status = data['action'] ?? data['status'] ?? '';
          bool newPumpState = status.toLowerCase() == 'on' || status.toLowerCase() == 'start';
          
          if (mounted && isPumpActive != newPumpState) {
            setState(() {
              isPumpActive = newPumpState;
            });
            print('🔄 Pump state updated from MQTT: $newPumpState');
          }
        }
      }
    });
  }

  // Method utama untuk mengirim perintah pump
  Future<void> _sendPumpCommand(bool activate) async {
    if (!isConnected) {
      _showStatusMessage('❌ MQTT not connected. Cannot send command.', isSuccess: false);
      return;
    }

    setState(() {
      isSendingCommand = true;
    });

    try {
      // Gunakan method controlPump yang sudah ada di MqttService
      bool success = await _mqttService.controlPump(activate);
      
      if (success) {
        _showStatusMessage(
          activate ? '💧 Pump activated successfully!' : '⏹️ Pump deactivated successfully!',
          isSuccess: true,
        );
        
        // Log untuk debugging
        print('✅ Pump command sent successfully: ${activate ? "ON" : "OFF"}');
        
      } else {
        throw Exception('Publish operation failed');
      }
      
    } catch (e) {
      print('❌ Failed to send pump command: $e');
      
      // Reset pump state jika gagal
      setState(() {
        isPumpActive = !activate;
      });
      
      _showStatusMessage(
        '❌ Failed to send command to pump: ${e.toString()}',
        isSuccess: false,
      );
    } finally {
      setState(() {
        isSendingCommand = false;
      });
    }
  }

  // Method alternatif dengan custom message
  Future<void> _sendCustomPumpCommand(bool activate) async {
    if (!isConnected) {
      _showStatusMessage('❌ MQTT not connected', isSuccess: false);
      return;
    }

    setState(() {
      isSendingCommand = true;
    });

    try {
      final pumpCommand = {
        'device': 'water_pump',
        'action': activate ? 'on' : 'off',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'control_app',
        'user_initiated': true,
        'command_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'duration': wateringDuration.toInt(), // Tambahan: durasi penyiraman
      };

      // Menggunakan publishToTopic method
      bool success = await _mqttService.publishToTopic(
        'greenhouse/control/pump', 
        pumpCommand
      );
      
      if (success) {
        print('📤 Custom pump command sent: $pumpCommand');
        
        _showStatusMessage(
          activate ? '💧 Pump activated successfully!' : '⏹️ Pump deactivated successfully!',
          isSuccess: true,
        );
      } else {
        throw Exception('Custom publish operation failed');
      }
      
    } catch (e) {
      print('❌ Failed to send custom pump command: $e');
      
      setState(() {
        isPumpActive = !activate;
      });
      
      _showStatusMessage(
        '❌ Failed to send command: ${e.toString()}',
        isSuccess: false,
      );
    } finally {
      setState(() {
        isSendingCommand = false;
      });
    }
  }

  // Method dengan retry mechanism
  Future<void> _sendPumpCommandWithRetry(bool activate) async {
    if (!isConnected) {
      _showStatusMessage('❌ MQTT not connected', isSuccess: false);
      return;
    }

    setState(() {
      isSendingCommand = true;
    });

    try {
      final pumpCommand = {
        'device': 'water_pump',
        'action': activate ? 'on' : 'off',
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'control_app',
        'retry_enabled': true,
      };

      final jsonMessage = jsonEncode(pumpCommand);
      
      // Gunakan publishMessageWithRetry untuk reliability
      bool success = await _mqttService.publishMessageWithRetry(
        'greenhouse/control/pump', 
        jsonMessage,
        maxRetries: 3
      );
      
      if (success) {
        _showStatusMessage(
          activate ? '💧 Pump activated (with retry)!' : '⏹️ Pump deactivated (with retry)!',
          isSuccess: true,
        );
      } else {
        throw Exception('Failed after multiple retry attempts');
      }
      
    } catch (e) {
      print('❌ Failed to send pump command with retry: $e');
      
      setState(() {
        isPumpActive = !activate;
      });
      
      _showStatusMessage(
        '❌ Failed to send command after retries',
        isSuccess: false,
      );
    } finally {
      setState(() {
        isSendingCommand = false;
      });
    }
  }

  // Method untuk test connection
  Future<void> _testMqttConnection() async {
    setState(() {
      isSendingCommand = true;
    });

    try {
      bool success = await _mqttService.testPublishWithConfirmation();
      
      _showStatusMessage(
        success ? '✅ MQTT test successful!' : '❌ MQTT test failed!',
        isSuccess: success,
      );
      
    } catch (e) {
      _showStatusMessage('❌ Test failed: $e', isSuccess: false);
    } finally {
      setState(() {
        isSendingCommand = false;
      });
    }
  }

  void _showStatusMessage(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mqttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              SizedBox(height: 24),
              _buildConnectionStatus(),
              SizedBox(height: 24),
              _buildPumpControl(),
              SizedBox(height: 24),
              _buildDeviceStatus(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      'Device Control',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? Colors.green : Colors.orange,
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'MQTT Connected' : 'MQTT Disconnected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? Colors.green : Colors.orange,
                  ),
                ),
                Text(
                  isConnected 
                    ? 'Ready to send commands to devices'
                    : 'Cannot control devices - Check connection',
                  style: TextStyle(
                    fontSize: 12,
                    color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: isSendingCommand ? null : _initializeMqtt,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSendingCommand
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isConnected ? Colors.green : Colors.orange,
                      ),
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    size: 16,
                    color: isConnected ? Colors.green : Colors.orange,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPumpControl() {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.water_drop,
                color: AppColors.primary,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Water Pump Control',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 32),
          
          // Pump Status and Control
          Row(
            children: [
              // Status Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isPumpActive 
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isPumpActive ? Colors.green : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isPumpActive ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            isPumpActive ? 'PUMP ON' : 'PUMP OFF',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isPumpActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPumpActive) ...[
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Running since ${DateTime.now().toString().substring(11, 16)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 24),
              
              // Round On/Off Button
              GestureDetector(
                onTapDown: (_) => _animationController.forward(),
                onTapUp: (_) => _animationController.reverse(),
                onTapCancel: () => _animationController.reverse(),
                onTap: (isConnected && !isSendingCommand) ? () {
                  setState(() {
                    isPumpActive = !isPumpActive;
                  });
                  _sendPumpCommand(isPumpActive);
                } : null,
                child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isPumpActive
                                ? [Colors.red.shade400, Colors.red.shade600]
                                : [Colors.green.shade400, Colors.green.shade600],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isPumpActive ? Colors.red : Colors.green).withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Outer ring
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                            // Inner content
                            Center(
                              child: isSendingCommand
                                ? CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPumpActive ? Icons.stop : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        isPumpActive ? 'STOP' : 'START',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                            // Disabled overlay
                            if (!isConnected)
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withOpacity(0.5),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.wifi_off,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          SizedBox(height: 24),          
        ],
      ),
    );
  }

  Widget _buildTestButtons() {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Functions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (isConnected && !isSendingCommand) 
                    ? _testMqttConnection 
                    : null,
                  icon: Icon(Icons.network_check),
                  label: Text('Test MQTT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (isConnected && !isSendingCommand) 
                    ? () => _sendCustomPumpCommand(!isPumpActive)
                    : null,
                  icon: Icon(Icons.settings),
                  label: Text('Custom CMD'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (isConnected && !isSendingCommand) 
                ? () => _sendPumpCommandWithRetry(!isPumpActive)
                : null,
              icon: Icon(Icons.repeat),
              label: Text('Send with Retry Mechanism'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatus() {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          _buildStatusItem('Water Pump', isPumpActive ? 'Active' : 'Inactive', Icons.water_drop, isPumpActive),
          _buildStatusItem('Soil Sensors', '2 Active', Icons.sensors, true),
          _buildStatusItem('MQTT Connection', isConnected ? 'Connected' : 'Disconnected', Icons.wifi, isConnected),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String title, String status, IconData icon, bool isActive) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? AppColors.success : AppColors.inactive,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? AppColors.success : AppColors.inactive,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}