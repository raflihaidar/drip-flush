import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/custom_card.dart';
import '../../services/mqtt_service.dart';
import '../../providers/greenhouse_provider.dart';

class ControlScreen extends StatefulWidget {
  @override
  _ControlScreenState createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> with TickerProviderStateMixin {
  double wateringDuration = 5.0;
  bool isSendingCommand = false;
  String _lastPumpAction = 'Never';
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  
  MqttService? _mqttService;
  bool _mqttConnected = false;
  bool _isConnecting = false;
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeMqtt();
    _listenToMqttMessages();
    
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
    // Setup auto refresh HANYA setelah initial load selesai
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _mqttConnected) {
        print('🔄 Auto refresh - syncing with Firebase');
        _syncWithProvider();
      }
    });
  }

  Future<void> _loadInitialDataFromProvider() async {
    try {
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      
      print('🔄 Loading initial data from Firebase...');
      
      // Force refresh dari Firebase untuk memastikan data terbaru
      await provider.refreshData();
      
      // Wait sebentar untuk memastikan data loaded
      await Future.delayed(Duration(milliseconds: 500));
      
      if (mounted) {
        // Update UI berdasarkan data Firebase yang fresh
        _syncWithProvider();
        
        // Setup auto refresh setelah initial load selesai
        _setupAutoRefresh();
        
        print('✅ Initial data loaded successfully');
        print('📊 Current pump status from Firebase: ${provider.isPumpActive}');
      }
      
    } catch (e) {
      print('❌ Error loading initial data: $e');
      if (mounted) {
        _showStatusMessage('⚠️ Failed to load latest status from server', isSuccess: false);
      }
    }
  }

  void _syncWithProvider() {
    try {
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      
      if (provider.lastPumpUpdate != null) {
        setState(() {
          _lastPumpAction = provider.lastPumpUpdate!.toString().substring(11, 16);
        });
      }
    } catch (e) {
      print('❌ Error syncing with provider: $e');
    }
  }

  Future<void> _initializeMqtt() async {
    try {
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

  void _listenToMqttMessages() {
    if (_mqttService != null) {
      _mqttService!.dataStream.listen(
        (data) {
          print('📨 Control received MQTT data: $data');
          _processIncomingMqttData(data);
        },
        onError: (error) {
          print('❌ Control MQTT stream error: $error');
        },
      );
    }
  }

  void _processIncomingMqttData(Map<String, dynamic> data) {
    try {
      bool pumpStatusChanged = false;
      
      if (data.containsKey('device') && data['device'] == 'water_pump') {
        if (data.containsKey('action')) {
          final action = data['action'].toString().toLowerCase();
          final isActive = action == 'on' || action == 'start' || action == 'activate';
          
          print('💧 Processing pump action: $action -> ${isActive ? "ON" : "OFF"}');
          pumpStatusChanged = true;
        }
      }
      
      if (data.containsKey('is_active')) {
        final isActive = data['is_active'];
        if (isActive is bool) {
          print('💧 Processing pump status: ${isActive ? "ON" : "OFF"}');
          pumpStatusChanged = true;
        }
      }
      
      if (data.containsKey('topic')) {
        final topic = data['topic'].toString();
        
        if (topic.contains('pump/control') || topic.contains('control/pump')) {
          if (data.containsKey('action')) {
            pumpStatusChanged = true;
          }
        }
        
        if (topic.contains('pump/status')) {
          if (data.containsKey('is_active')) {
            pumpStatusChanged = true;
          }
        }
      }
      
      // PERBAIKAN: Jika ada perubahan dari MQTT, sync dengan Firebase
      if (pumpStatusChanged && mounted) {
        setState(() {
          _lastPumpAction = DateTime.now().toString().substring(11, 16);
        });
        
        // Force refresh provider untuk sync dengan Firebase
        final provider = Provider.of<GreenhouseProvider>(context, listen: false);
        provider.refreshData();
      }
      
      if (data.containsKey('error') && data['error'] == true) {
        final errorMsg = data['error_message'] ?? 'Unknown MQTT error';
        print('❌ MQTT Error received in Control: $errorMsg');
        _showStatusMessage('MQTT Error: $errorMsg', isSuccess: false);
      }
      
    } catch (e) {
      print('❌ Error processing MQTT data in Control: $e');
    }
  }

  Future<void> _reconnectMqtt() async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
    });
    
    try {
      _mqttService?.dispose();
      _mqttService = MqttService();
      
      bool connected = await _mqttService!.prepareMqttClient();
      if (mounted) {
        setState(() {
          _mqttConnected = connected;
        });
        
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

  // PERBAIKAN: Method untuk send pump command dengan Firebase sync yang lebih robust
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
      print('💧 Sending pump control command: ${activate ? "ON" : "OFF"}');
      
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      
      // PERBAIKAN: Kirim command dan tunggu konfirmasi
      await provider.controlPump(activate);
      
      // PERBAIKAN: Tunggu sebentar untuk memastikan data tersimpan di Firebase
      await Future.delayed(Duration(milliseconds: 1000));
      
      // PERBAIKAN: Force refresh untuk memastikan status terbaru
      await provider.refreshData();
      
      print('✅ Pump control command completed successfully');
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
      print('❌ Failed to send pump command: $e');
      
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

  // PERBAIKAN: Manual refresh yang lebih comprehensive
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      print('🔄 Manual refresh started...');
      
      // Jika MQTT tidak connected, coba reconnect dulu
      if (!_mqttConnected) {
        await _reconnectMqtt();
      }
      
      // PERBAIKAN: Force refresh Firebase data
      final provider = Provider.of<GreenhouseProvider>(context, listen: false);
      await provider.refreshData();
      
      // Wait sebentar untuk memastikan data loaded
      await Future.delayed(Duration(milliseconds: 500));
      
      // Sync local state dengan provider
      _syncWithProvider();
      
      print('✅ Manual refresh completed');
      _showStatusMessage('🔄 System refreshed successfully', isSuccess: true);
      
    } catch (e) {
      print('❌ Manual refresh failed: $e');
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
    _mqttService?.dispose();
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
                  // PERBAIKAN: Tampilkan status sync Firebase
                  if (provider.isLoading)
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Syncing...',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_done,
                          color: Colors.green,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Synced',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              SizedBox(height: 32),
              
              Row(
                children: [
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
                                color: Colors.green,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Synced with Firebase',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 24),
                  
                  // Control Button
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

  Widget _buildDeviceStatus() {
    return Consumer<GreenhouseProvider>(
      builder: (context, provider, child) {
        final isPumpActive = provider.isPumpActive ?? false;
        
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
                'Firebase Sync', 
                provider.isLoading ? 'Syncing...' : 'Connected', 
                Icons.cloud, 
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