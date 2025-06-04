import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../widgets/common/custom_card.dart';
import '../../services/mqtt_service.dart';
import '../../providers/greenhouse_provider.dart';  // Import provider

class ControlScreen extends StatefulWidget {
  @override
  _ControlScreenState createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> with TickerProviderStateMixin {
  // Remove local pump status - akan ambil dari provider
  double wateringDuration = 5.0;
  bool isSendingCommand = false;
  String _lastPumpAction = 'Never';
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  
  // MQTT Service - SAMA PERSIS SEPERTI HOME SCREEN
  MqttService? _mqttService;
  bool _mqttConnected = false;
  bool _isConnecting = false;
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupAutoRefresh();
    _initializeMqtt(); // SAMA SEPERTI HOME SCREEN
    _listenToMqttMessages(); // SAMA SEPERTI HOME SCREEN
    
    // Load initial pump status from Firebase via provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialDataFromProvider();
    });
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

  void _setupAutoRefresh() {
    // Auto refresh every 30 seconds - SAMA SEPERTI HOME
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _mqttConnected) {
        // Optional: refresh pump status periodically dari provider
        print('🔄 Auto refresh - checking pump status from provider');
        _syncWithProvider();
      }
    });
  }

  // Method untuk load initial data dari provider
  void _loadInitialDataFromProvider() {
    final provider = Provider.of<GreenhouseProvider>(context, listen: false);
    
    // Update UI berdasarkan data dari provider
    if (provider.pumpStatus != null) {
      print('📊 Loading initial pump status from provider: ${provider.currentPumpStatus}');
      
      // Update last action time jika ada data
      if (provider.lastPumpUpdate != null) {
        setState(() {
          _lastPumpAction = provider.lastPumpUpdate!.toString().substring(11, 16);
        });
      }
    }
    
    // Force refresh provider data
    provider.refreshData();
  }

  // Method untuk sync dengan provider
  void _syncWithProvider() {
    final provider = Provider.of<GreenhouseProvider>(context, listen: false);
    
    if (provider.pumpStatus != null && provider.lastPumpUpdate != null) {
      setState(() {
        _lastPumpAction = provider.lastPumpUpdate!.toString().substring(11, 16);
      });
    }
  }

  // Method MQTT initialization SAMA PERSIS SEPERTI HOME SCREEN
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
      print(_mqttConnected ? '✅ MQTT Connected for Control' : '❌ MQTT Failed to Connect for Control');
    } catch (e) {
      print('❌ Error initializing MQTT in Control: $e');
      if (mounted) {
        setState(() {
          _mqttConnected = false;
        });
      }
    }
  }

  // Method listen MQTT messages SAMA PERSIS SEPERTI HOME SCREEN
  void _listenToMqttMessages() {
    if (_mqttService != null) {
      _mqttService!.dataStream.listen(
        (data) {
          print('📨 Control received MQTT data: $data');
          
          // Handle different data formats
          _processIncomingMqttData(data);
        },
        onError: (error) {
          print('❌ Control MQTT stream error: $error');
        },
      );
    }
  }

  // Method untuk process incoming MQTT data - FOKUS PADA PUMP STATUS
  void _processIncomingMqttData(Map<String, dynamic> data) {
    try {
      // Handle pump status - UPDATE LAST ACTION TIME SAJA
      bool pumpStatusChanged = false;
      
      if (data.containsKey('device') && data['device'] == 'water_pump') {
        // Handle pump control response
        if (data.containsKey('action')) {
          final action = data['action'].toString().toLowerCase();
          final isActive = action == 'on' || action == 'start' || action == 'activate';
          
          print('💧 Processing pump action: $action -> ${isActive ? "ON" : "OFF"}');
          pumpStatusChanged = true;
        }
      }
      
      // Handle pump status dari topic pump/status
      if (data.containsKey('is_active')) {
        final isActive = data['is_active'];
        if (isActive is bool) {
          print('💧 Processing pump status: ${isActive ? "ON" : "OFF"}');
          pumpStatusChanged = true;
        }
      }
      
      // Handle topic-based pump status
      if (data.containsKey('topic')) {
        final topic = data['topic'].toString();
        
        // Jika dari pump control topic
        if (topic.contains('pump/control') || topic.contains('control/pump')) {
          if (data.containsKey('action')) {
            pumpStatusChanged = true;
          }
        }
        
        // Jika dari pump status topic
        if (topic.contains('pump/status')) {
          if (data.containsKey('is_active')) {
            pumpStatusChanged = true;
          }
        }
      }
      
      // Update last action time jika ada perubahan status pump
      if (pumpStatusChanged && mounted) {
        setState(() {
          _lastPumpAction = DateTime.now().toString().substring(11, 16);
        });
      }
      
      // Handle error messages
      if (data.containsKey('error') && data['error'] == true) {
        final errorMsg = data['error_message'] ?? 'Unknown MQTT error';
        print('❌ MQTT Error received in Control: $errorMsg');
        _showStatusMessage('MQTT Error: $errorMsg', isSuccess: false);
      }
      
    } catch (e) {
      print('❌ Error processing MQTT data in Control: $e');
    }
  }

  // Method reconnect MQTT SAMA PERSIS SEPERTI HOME SCREEN
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
        
        _showStatusMessage(connected 
          ? '✅ MQTT Reconnected successfully!' 
          : '❌ MQTT Reconnection failed', isSuccess: connected);
      }
    } catch (e) {
      print('❌ MQTT Reconnect error in Control: $e');
      if (mounted) {
        _showStatusMessage('❌ MQTT Reconnection failed: $e', isSuccess: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  // IMPROVED: Method utama untuk mengirim perintah pump - GUNAKAN PROVIDER
  Future<void> _sendPumpCommand(bool activate) async {
    if (!_mqttConnected) {
      _showStatusMessage('❌ MQTT not connected. Tap refresh to reconnect.', isSuccess: false);
      return;
    }

    if (isSendingCommand) {
      print('⚠️ Command already in progress, ignoring new request');
      return;
    }

    setState(() {
      isSendingCommand = true;
    });

    try {
      print('💧 Attempting to control pump via provider: ${activate ? "ON" : "OFF"}');
      
      // GUNAKAN PROVIDER untuk control pump (ini akan sync dengan Firebase)
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      await provider.controlPump(activate);
      
      print('✅ Pump control command sent via provider successfully');
      _showStatusMessage(
        activate ? '💧 Pump activated successfully!' : '⏹️ Pump deactivated successfully!',
        isSuccess: true,
      );
      
      // Update last action time
      if (mounted) {
        setState(() {
          _lastPumpAction = DateTime.now().toString().substring(11, 16);
        });
      }
      
    } catch (e) {
      print('❌ Failed to send pump command via provider: $e');
      
      _showStatusMessage(
        '❌ Failed to send command to pump: ${e.toString()}',
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSendingCommand = false;
        });
      }
    }
  }

  // Method alternatif dengan custom message - UNTUK TESTING
  Future<void> _sendCustomPumpCommand(bool activate) async {
    if (!_mqttConnected) {
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
        'duration': wateringDuration.toInt(),
      };

      // Menggunakan publishToTopic method
      bool success = await _mqttService!.publishToTopic(
        'greenhouse/control/pump', 
        pumpCommand
      );
      
      if (success) {
        print('📤 Custom pump command sent: $pumpCommand');
        
        _showStatusMessage(
          activate ? '💧 Custom pump command sent!' : '⏹️ Custom stop command sent!',
          isSuccess: true,
        );
        
        // Update last action time
        if (mounted) {
          setState(() {
            _lastPumpAction = DateTime.now().toString().substring(11, 16);
          });
        }
      } else {
        throw Exception('Custom publish operation failed');
      }
      
    } catch (e) {
      print('❌ Failed to send custom pump command: $e');
      
      _showStatusMessage(
        '❌ Failed to send custom command: ${e.toString()}',
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSendingCommand = false;
        });
      }
    }
  }

  // Method dengan retry mechanism - UNTUK TESTING
  Future<void> _sendPumpCommandWithRetry(bool activate) async {
    if (!_mqttConnected) {
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
        'command_id': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      final jsonMessage = jsonEncode(pumpCommand);
      
      // Gunakan publishMessageWithRetry untuk reliability
      bool success = await _mqttService!.publishMessageWithRetry(
        'greenhouse/control/pump', 
        jsonMessage,
        maxRetries: 3
      );
      
      if (success) {
        _showStatusMessage(
          activate ? '💧 Pump activated (with retry)!' : '⏹️ Pump deactivated (with retry)!',
          isSuccess: true,
        );
        
        // Update last action time
        if (mounted) {
          setState(() {
            _lastPumpAction = DateTime.now().toString().substring(11, 16);
          });
        }
      } else {
        throw Exception('Failed after multiple retry attempts');
      }
      
    } catch (e) {
      print('❌ Failed to send pump command with retry: $e');
      
      _showStatusMessage(
        '❌ Failed to send command after retries',
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSendingCommand = false;
        });
      }
    }
  }

  // Method untuk test connection
  Future<void> _testMqttConnection() async {
    setState(() {
      isSendingCommand = true;
    });

    try {
      bool success = await _mqttService!.testPublishWithConfirmation();
      
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

  // Manual refresh function SAMA SEPERTI HOME SCREEN
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
      
      // Refresh provider data
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      await provider.refreshData();
      
      // Sync local state dengan provider
      _syncWithProvider();
      
      _showStatusMessage('🔄 Control system refreshed successfully', isSuccess: true);
    } catch (e) {
      _showStatusMessage('❌ Refresh failed: $e', isSuccess: false);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showStatusMessage(String message, {required bool isSuccess}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: Duration(seconds: 2),
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
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _animationController.dispose();
    _mqttService?.dispose(); // Dispose MQTT service SAMA SEPERTI HOME SCREEN
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
              _buildTestButtons(),
              SizedBox(height: 24),
              _buildDeviceStatus(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Device Control',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // Manual refresh button dengan reconnect capability SAMA SEPERTI HOME
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
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _mqttConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _mqttConnected ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _mqttConnected ? Icons.wifi : Icons.wifi_off,
            color: _mqttConnected ? Colors.green : Colors.orange,
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mqttConnected ? 'MQTT Connected' : 'MQTT Disconnected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _mqttConnected ? Colors.green : Colors.orange,
                  ),
                ),
                Text(
                  _mqttConnected 
                    ? 'Ready to send commands to devices'
                    : (_isConnecting 
                        ? 'Reconnecting to control system...'
                        : 'Cannot control devices - Tap refresh to reconnect'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _mqttConnected 
                      ? Colors.green.shade700 
                      : (_isConnecting ? Colors.blue.shade700 : Colors.orange.shade700),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: (_isConnecting || isSendingCommand) ? null : _reconnectMqtt,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: (_isConnecting || isSendingCommand)
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _mqttConnected ? Colors.green : Colors.orange,
                      ),
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    size: 16,
                    color: _mqttConnected ? Colors.green : Colors.orange,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPumpControl() {
    return Consumer<GreenhouseProvider>(
      builder: (context, provider, child) {
        // Ambil status pump dari provider (dari Firebase)
        final isPumpActive = provider.isPumpActive ?? false;
        
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
                  Spacer(),
                  // Firebase sync indicator
                  if (provider.isLoading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.cloud_done,
                      color: Colors.green,
                      size: 16,
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
                        if (provider.lastPumpUpdate != null) ...[
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
                                'Last update: ${provider.lastPumpUpdate!.toString().substring(11, 16)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.cloud,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Synced with Firebase',
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
                    onTap: (_mqttConnected && !isSendingCommand && !provider.isLoading) ? () {
                      _sendPumpCommand(!isPumpActive);
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
                                  child: (isSendingCommand || provider.isLoading)
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
                                if (!_mqttConnected)
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
      },
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
                  onPressed: (_mqttConnected && !isSendingCommand) 
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
                child: Consumer<GreenhouseProvider>(
                  builder: (context, provider, child) {
                    return ElevatedButton.icon(
                      onPressed: (_mqttConnected && !isSendingCommand) 
                        ? () => _sendCustomPumpCommand(!(provider.isPumpActive ?? false))
                        : null,
                      icon: Icon(Icons.settings),
                      label: Text('Custom CMD'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          
          Consumer<GreenhouseProvider>(
            builder: (context, provider, child) {
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_mqttConnected && !isSendingCommand) 
                    ? () => _sendPumpCommandWithRetry(!(provider.isPumpActive ?? false))
                    : null,
                  icon: Icon(Icons.repeat),
                  label: Text('Send with Retry Mechanism'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatus() {
    return Consumer<GreenhouseProvider>(
      builder: (context, provider, child) {
        final isPumpActive = provider.isPumpActive ?? false;
        final isConnectedToFirebase = provider.isConnected;
        
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
              _buildStatusItem(
                'Water Pump', 
                isPumpActive ? 'Active' : 'Inactive', 
                Icons.water_drop, 
                isPumpActive
              ),
              _buildStatusItem(
                'Soil Sensors', 
                provider.sensorData != null ? 'Active' : 'No Data', 
                Icons.sensors, 
                provider.sensorData != null
              ),
              _buildStatusItem(
                'MQTT Connection', 
                _mqttConnected ? 'Connected' : 'Disconnected', 
                Icons.wifi, 
                _mqttConnected
              ),
              _buildStatusItem(
                'Firebase Sync', 
                isConnectedToFirebase ? 'Connected' : 'Disconnected', 
                Icons.cloud, 
                isConnectedToFirebase
              ),
              _buildStatusItem(
                'Provider Status', 
                provider.isLoading ? 'Loading...' : 'Ready', 
                Icons.settings, 
                !provider.isLoading
              ),
              if (provider.errorMessage != null) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Error: ${provider.errorMessage}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
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