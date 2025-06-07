import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/greenhouse_provider.dart';
import '../../services/mqtt_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  
  // MQTT Service untuk reconnect
  MqttService? _mqttService;
  bool _mqttConnected = false;
  bool _isConnecting = false;
  
  // Data cuaca (statis)
  final double _weatherTemperature = 40.0;
  final String _weatherCondition = 'Cerah';
  final int _weatherHumidity = 45;
  
  // Pelacakan min/max 24 jam untuk kedua sensor
  double _maxHumidity24h_sensor1 = 0.0;
  double _minHumidity24h_sensor1 = 100.0;
  double _maxHumidity24h_sensor2 = 0.0;
  double _minHumidity24h_sensor2 = 100.0;

  @override
  void initState() {
    super.initState();
    _setupAutoRefresh();
    _initializeMqtt();
    _listenToMqttMessages();
  }

  void _setupAutoRefresh() {
    // Auto refresh setiap 30 detik
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        context.read<GreenhouseProvider>().refreshData();
      }
    });
  }

  // Method MQTT initialization
  Future<void> _initializeMqtt() async {
    try {
      // Buat instance baru setiap kali
      _mqttService = MqttService();
      
      bool connected = await _mqttService!.prepareMqttClient();
      if (mounted) {
        setState(() {
          _mqttConnected = connected;
        });
      }
      print(_mqttConnected ? '✅ MQTT Terhubung untuk Home' : '❌ MQTT Gagal Terhubung untuk Home');
    } catch (e) {
      print('❌ Error inisialisasi MQTT di Home: $e');
      if (mounted) {
        setState(() {
          _mqttConnected = false;
        });
      }
    }
  }

  // Method listen MQTT messages dengan support multi-sensor
  void _listenToMqttMessages() {
    if (_mqttService != null) {
      _mqttService!.dataStream.listen(
        (data) {
          print('📨 Home menerima data MQTT: $data');
          
          // Handle format data yang berbeda
          _processIncomingMqttData(data);
        },
        onError: (error) {
          print('❌ Home MQTT stream error: $error');
        },
      );
    }
  }

  // Method untuk memproses data MQTT yang masuk - Enhanced untuk multi-sensor
  void _processIncomingMqttData(Map<String, dynamic> data) {
    try {
      // Handle struktur data multi-sensor
      if (data.containsKey('sensors') && data['sensors'] is Map) {
        final sensors = data['sensors'] as Map;
        
        sensors.forEach((sensorId, sensorData) {
          if (sensorData is Map && sensorData.containsKey('value')) {
            final value = sensorData['value'];
            if (value is num) {
              print('🌱 Memproses sensor $sensorId nilai: ${value.toDouble()}%');
              
              if (mounted) {
                setState(() {
                  // Update min/max untuk sensor yang sesuai
                  if (sensorId == 'sensor_1') {
                    _updateMinMaxHumidity(value.toDouble(), true);
                  } else if (sensorId == 'sensor_2') {
                    _updateMinMaxHumidity(value.toDouble(), false);
                  }
                });
              }
            }
          }
        });
      }
      
      // Handle data sensor tunggal dengan sensor ID
      if (data.containsKey('value') && data.containsKey('sensor_id')) {
        final sensorId = data['sensor_id'] as String?;
        final value = data['value'];
        
        if (sensorId != null && value is num) {
          print('🌱 Memproses $sensorId nilai: ${value.toDouble()}%');
          
          if (mounted) {
            setState(() {
              if (sensorId == 'sensor_1') {
                _updateMinMaxHumidity(value.toDouble(), true);
              } else if (sensorId == 'sensor_2') {
                _updateMinMaxHumidity(value.toDouble(), false);
              }
            });
          }
        }
      }
      
      // Handle format legacy
      if (data.containsKey('soil_humidity')) {
        final humidity = data['soil_humidity'];
        if (humidity is num) {
          print('🌱 Memproses kelembaban tanah legacy: ${humidity.toDouble()}%');
          if (mounted) {
            setState(() {
              _updateMinMaxHumidity(humidity.toDouble(), true); // Default ke sensor 1
            });
          }
        }
      }
      
      // Handle status pompa
      if (data.containsKey('pump_status') || data.containsKey('is_active')) {
        final isActive = data['pump_status'] ?? data['is_active'];
        if (isActive is bool) {
          print('💧 Memproses status pompa: ${isActive ? "NYALA" : "MATI"}');
        }
      }
      
      // Handle pesan error
      if (data.containsKey('error') && data['error'] == true) {
        final errorMsg = data['error_message'] ?? 'Error MQTT tidak diketahui';
        print('❌ Error MQTT diterima: $errorMsg');
        _showSnackBar('Error MQTT: $errorMsg');
      }
      
    } catch (e) {
      print('❌ Error memproses data MQTT: $e');
    }
  }

  // Method reconnect MQTT
  Future<void> _reconnectMqtt() async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
    });
    
    try {
      // Dispose instance lama terlebih dahulu
      _mqttService?.dispose();
      
      // Buat instance baru
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
          ? '✅ MQTT berhasil terhubung kembali!' 
          : '❌ Koneksi ulang MQTT gagal');
      }
    } catch (e) {
      print('❌ Error koneksi ulang MQTT di Home: $e');
      if (mounted) {
        _showSnackBar('❌ Koneksi ulang MQTT gagal: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _updateMinMaxHumidity(double humidity, bool isSensor1) {
    if (humidity > 0) {
      if (isSensor1) {
        if (_maxHumidity24h_sensor1 == 0.0 || humidity > _maxHumidity24h_sensor1) {
          _maxHumidity24h_sensor1 = humidity;
        }
        if (_minHumidity24h_sensor1 == 100.0 || humidity < _minHumidity24h_sensor1) {
          _minHumidity24h_sensor1 = humidity;
        }
      } else {
        if (_maxHumidity24h_sensor2 == 0.0 || humidity > _maxHumidity24h_sensor2) {
          _maxHumidity24h_sensor2 = humidity;
        }
        if (_minHumidity24h_sensor2 == 100.0 || humidity < _minHumidity24h_sensor2) {
          _minHumidity24h_sensor2 = humidity;
        }
      }
    }
  }

  // Function manual refresh
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      // Jika MQTT tidak terhubung, coba reconnect dulu
      if (!_mqttConnected) {
        await _reconnectMqtt();
      }
      
      await context.read<GreenhouseProvider>().refreshData();
      _showSnackBar('🔄 Data berhasil diperbarui');
    } catch (e) {
      _showSnackBar('❌ Gagal memperbarui: $e');
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
    _mqttService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<GreenhouseProvider>(
          builder: (context, provider, child) {
            // Ambil data sensor untuk kedua sensor
            final sensor1Humidity = provider.sensor1Humidity ?? 0.0;
            final sensor2Humidity = provider.sensor2Humidity ?? 0.0;
            final averageHumidity = provider.currentSoilHumidity ?? 0.0;
            
            final sensor1Condition = provider.sensor1Condition ?? 'Tidak Ada Data';
            final sensor2Condition = provider.sensor2Condition ?? 'Tidak Ada Data';
            final overallCondition = provider.overallCondition ?? 'Tidak Ada Data';
            
            final sensor1Active = provider.sensor1Active ?? false;
            final sensor2Active = provider.sensor2Active ?? false;
            
            final isConnected = provider.isConnected || _mqttConnected;
            final lastUpdate = provider.sensorData != null ? 'Aktif' : 'Belum Pernah';
            
            // Update pelacakan min/max untuk kedua sensor
            if (sensor1Humidity > 0) {
              _updateMinMaxHumidity(sensor1Humidity, true);
            }
            if (sensor2Humidity > 0) {
              _updateMinMaxHumidity(sensor2Humidity, false);
            }
            
            // Ambil tanggal dan waktu saat ini
            final now = DateTime.now();
            final formattedDate = '${_getDayName(now.weekday)}, ${now.day} ${_getMonthName(now.month)} ${now.year}';
            final formattedTime = '${_formatHour(now.hour)}:${_formatMinute(now.minute)} ${now.hour >= 12 ? 'PM' : 'AM'}';
            
            return SingleChildScrollView(
              child: Column(
                children: [
                  // Top navigation bar dengan status koneksi
                  Container(
                    height: 50,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        // Indikator status koneksi dengan tap untuk reconnect
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
                                // Indikator auto-refresh
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
                        // Indikator cuaca
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
                        // Tombol refresh manual dengan kemampuan reconnect
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
                  
                  // Jarak putih
                  const SizedBox(height: 10),
                  
                  // Judul dengan status multi-sensor
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
                                ? 'Multi-Sensor Aktif • Terakhir: $lastUpdate'
                                : (_isConnecting 
                                    ? 'Menghubungkan ke Sensor...'
                                    : 'Sensor Terputus • Ketuk WiFi untuk menghubungkan ulang'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isConnected 
                                  ? Colors.green 
                                  : (_isConnecting ? Colors.blue : Colors.orange),
                              ),
                            ),
                          ],
                        ),
                        // Indikator status sensor
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Indikator Sensor 1
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: sensor1Active 
                                    ? Colors.green.shade100 
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.sensors,
                                    size: 10,
                                    color: sensor1Active ? Colors.green : Colors.grey,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'S1',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: sensor1Active ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Indikator Sensor 2
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: sensor2Active 
                                    ? Colors.green.shade100 
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.sensors,
                                    size: 10,
                                    color: sensor2Active ? Colors.green : Colors.grey,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'S2',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: sensor2Active ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Tampilkan indikator loading jika provider sedang loading
                        if (provider.isLoading || _isConnecting)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        // Tampilkan pesan error jika ada
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
                  
                  // Jarak putih
                  const SizedBox(height: 10),
                  
                  // Card cuaca
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
                        // Baris lokasi dan tanggal
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                          child: Row(
                            children: [
                              // Lokasi dengan ikon
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
                              // Tanggal dan waktu
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
                        
                        // Kondisi cuaca
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                          child: Row(
                            children: [
                              // Ikon dan status kondisi cuaca
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
                                  // Kelembaban cuaca
                                  Text(
                                    'Kelembaban: ${_weatherHumidity}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Suhu cuaca saat ini
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
                        
                        // Info cuaca
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
                                'Data Cuaca - Area Jambangan',
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
                  
                  // Jarak putih
                  const SizedBox(height: 10),
                  
                  // Card kondisi kelembaban tanah rata-rata
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
                        // Header kondisi kelembaban tanah rata-rata
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                          child: Row(
                            children: [
                              const Text(
                                'Kelembaban Tanah Rata-rata',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.analytics,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                        
                        // Tampilan kelembaban tanah rata-rata
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
                          child: Row(
                            children: [
                              // Ikon dan status kondisi keseluruhan
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _getOverallConditionIcon(averageHumidity),
                                    color: _getOverallConditionColor(averageHumidity),
                                    size: 32,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _translateCondition(overallCondition),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Kelembaban tanah rata-rata
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    averageHumidity == 0.0 ? '0.0' : averageHumidity.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: 64,
                                      fontWeight: FontWeight.w500,
                                      color: averageHumidity == 0.0 ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    '%',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                      color: averageHumidity == 0.0 ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Info sensor
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
                                'Multi-Sensor - Firebase Terhubung',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              // Indikator status koneksi
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
                                        : (_isConnecting ? 'MENGHUBUNGKAN' : 'OFFLINE'),
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
                  
                  // Jarak putih
                  const SizedBox(height: 10),
                  
                  // Card sensor individual dengan style seperti average soil humidity
                  Column(
                    children: [
                      // Card Sensor 1
                      _buildSensorCardLarge(
                        'Sensor 1',
                        sensor1Humidity,
                        sensor1Condition,
                        sensor1Active,
                        _maxHumidity24h_sensor1 > 0.0 
                            ? '24j: ${_minHumidity24h_sensor1.toStringAsFixed(1)}% - ${_maxHumidity24h_sensor1.toStringAsFixed(1)}%'
                            : null,
                        Colors.blue,
                      ),
                      
                      // Jarak putih
                      const SizedBox(height: 10),
                      
                      // Card Sensor 2
                      _buildSensorCardLarge(
                        'Sensor 2',
                        sensor2Humidity,
                        sensor2Condition,
                        sensor2Active,
                        _maxHumidity24h_sensor2 > 0.0 
                            ? '24j: ${_minHumidity24h_sensor2.toStringAsFixed(1)}% - ${_maxHumidity24h_sensor2.toStringAsFixed(1)}%'
                            : null,
                        Colors.green,
                      ),
                    ],
                  ),
                  
                  // Jarak putih
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Helper method untuk membuat card sensor besar seperti average soil humidity
  Widget _buildSensorCardLarge(
    String sensorName,
    double humidity,
    String condition,
    bool isActive,
    String? range24h,
    Color themeColor,
  ) {
    return Container(
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
          // Header sensor
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
            child: Row(
              children: [
                Text(
                  'Kelembaban $sensorName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.sensors,
                  color: themeColor,
                  size: 20,
                ),
              ],
            ),
          ),
          
          // Tampilan nilai sensor
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
            child: Row(
              children: [
                // Ikon dan status kondisi sensor
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _getSensorConditionIcon(condition),
                      color: _getSensorConditionColor(condition),
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _translateCondition(condition),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Range 24 jam jika tersedia
                    if (range24h != null)
                      Text(
                        range24h,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                // Kelembaban sensor
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      humidity == 0.0 ? '0.0' : humidity.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w500,
                        color: humidity == 0.0 ? Colors.grey : themeColor,
                      ),
                    ),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                        color: humidity == 0.0 ? Colors.grey : themeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Info status sensor
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              border: Border(
                top: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '$sensorName - Kelembaban Tanah',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Indikator status sensor
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive 
                      ? Colors.green.shade100 
                      : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: isActive ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'AKTIF' : 'TIDAK AKTIF',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.green : Colors.grey,
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
    );
  }

  // Ambil ikon kondisi keseluruhan berdasarkan kelembaban rata-rata
  IconData _getOverallConditionIcon(double humidity) {
    if (humidity == 0.0) {
      return Icons.help_outline; // Tidak ada data
    } else if (humidity < 40) {
      return Icons.warning; // Kering
    } else if (humidity > 70) {
      return Icons.water_drop; // Terlalu basah
    } else {
      return Icons.eco; // Optimal
    }
  }

  Color _getOverallConditionColor(double humidity) {
    if (humidity == 0.0) {
      return Colors.grey; // Tidak ada data
    } else if (humidity < 40) {
      return Colors.orange; // Kering
    } else if (humidity > 70) {
      return Colors.blue; // Terlalu basah
    } else {
      return Colors.green; // Optimal
    }
  }

  // Ambil ikon kondisi sensor berdasarkan kondisi
  IconData _getSensorConditionIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'optimal':
      case 'optimal':
        return Icons.eco;
      case 'dry':
      case 'kering':
        return Icons.warning;
      case 'too wet':
      case 'terlalu lembab':
      case 'terlalu basah':
        return Icons.water_drop;
      case 'inactive':
      case 'tidak aktif':
        return Icons.sensors_off;
      case 'no data':
      case 'tidak ada data':
        return Icons.help_outline;
      default:
        return Icons.error_outline;
    }
  }

  Color _getSensorConditionColor(String condition) {
    switch (condition.toLowerCase()) {
      case 'optimal':
        return Colors.green;
      case 'dry':
      case 'kering':
        return Colors.orange;
      case 'too wet':
      case 'terlalu lembab':
      case 'terlalu basah':
        return Colors.blue;
      case 'inactive':
      case 'tidak aktif':
        return Colors.grey;
      case 'no data':
      case 'tidak ada data':
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  // Method untuk menerjemahkan kondisi ke bahasa Indonesia
  String _translateCondition(String condition) {
    switch (condition.toLowerCase()) {
      case 'optimal':
        return 'Optimal';
      case 'dry':
        return 'Kering';
      case 'too wet':
        return 'Terlalu Basah';
      case 'inactive':
        return 'Tidak Aktif';
      case 'no data':
        return 'Tidak Ada Data';
      default:
        return condition;
    }
  }
  
  // Helper methods untuk format tanggal
  String _getDayName(int weekday) {
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 
                   'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
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