import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/custom_card.dart';
import '../../widgets/charts/sensor_chart.dart';
import '../../services/firebase_service.dart';
import '../../providers/greenhouse_provider.dart';

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedPeriod = '7 Days';
  
  final FirebaseService _firebaseService = FirebaseService();
  
  // Data variables
  List<Map<String, dynamic>> _historicalData = [];
  List<Map<String, dynamic>> _sensor1ChartData = [];
  List<Map<String, dynamic>> _sensor2ChartData = [];
  Map<String, dynamic> _sensor1Stats = {};
  Map<String, dynamic> _sensor2Stats = {};
  bool _isLoading = false;
  String? _errorMessage;

  // Auto refresh timer
  Timer? _autoRefreshTimer;
  DateTime? _lastDataRefresh;

  final List<String> periods = ['24 Hours', '7 Days', '30 Days', '90 Days'];

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeAndLoadData() async {
    print('🚀 [INIT] Starting HistoryScreen initialization...');
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _firebaseService.initialize();
      await _loadDataForPeriod();
      print('✅ [INIT] Initial data loaded successfully');
      
    } catch (e) {
      print('❌ [INIT] Error during initialization: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted && !_isLoading) {
        print('🔄 [AUTO-REFRESH] Periodic refresh executing...');
        _loadDataForPeriod();
      }
    });
    print('⏰ [AUTO-REFRESH] Auto refresh started (every 30 seconds)');
  }

  Future<void> _loadDataForPeriod() async {
    print('📊 [LOAD] Starting data load for period: $selectedPeriod');
    
    final shouldShowLoading = !_isLoading;
    
    try {
      if (shouldShowLoading && mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      switch (selectedPeriod) {
        case '24 Hours':
          startDate = now.subtract(Duration(hours: 24));
          break;
        case '7 Days':
          startDate = now.subtract(Duration(days: 7));
          break;
        case '30 Days':
          startDate = now.subtract(Duration(days: 30));
          break;
        case '90 Days':
          startDate = now.subtract(Duration(days: 90));
          break;
        default:
          startDate = now.subtract(Duration(days: 7));
      }

      print('📅 [LOAD] Date range: ${startDate.toString()} to ${endDate.toString()}');

      // Load historical sensor data
      final historicalData = await _firebaseService.getSensorHistory(
        startDate: startDate,
        endDate: endDate,
        limit: selectedPeriod == '24 Hours' ? 100 : null,
      );

      // Process chart data for both sensors
      final sensor1ChartData = _processChartData(historicalData, 'sensor_1');
      final sensor2ChartData = _processChartData(historicalData, 'sensor_2');

      // Calculate statistics
      final sensor1Stats = _calculateStats(sensor1ChartData);
      final sensor2Stats = _calculateStats(sensor2ChartData);

      if (mounted) {
        setState(() {
          _historicalData = historicalData;
          _sensor1ChartData = sensor1ChartData;
          _sensor2ChartData = sensor2ChartData;
          _sensor1Stats = sensor1Stats;
          _sensor2Stats = sensor2Stats;
          _errorMessage = null;
          if (shouldShowLoading) {
            _isLoading = false;
          }
        });
      }

      print('✅ [LOAD] Chart data processed:');
      print('   Historical records: ${historicalData.length}');
      print('   Sensor 1 chart points: ${sensor1ChartData.length}');
      print('   Sensor 2 chart points: ${sensor2ChartData.length}');

    } catch (e) {
      print('❌ [LOAD] Error loading data for period: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load data: $e';
          if (shouldShowLoading) {
            _isLoading = false;
          }
        });
      }
    }
  }

  List<Map<String, dynamic>> _processChartData(List<Map<String, dynamic>> data, String sensorId) {
    final chartData = <Map<String, dynamic>>[];

    for (final entry in data) {
      try {
        final sensorData = entry['sensor'];
        if (sensorData != null) {
          double? value;
          DateTime? timestamp;
          
          // Extract value based on sensor ID
          if (sensorId == 'sensor_1') {
            // Try new format first
            if (sensorData['soil_sensor_1'] != null) {
              value = (sensorData['soil_sensor_1']['value'] as num?)?.toDouble();
            }
            // Fallback to legacy format for sensor 1
            else if (sensorData['soil_sensor'] != null) {
              value = (sensorData['soil_sensor']['value'] as num?)?.toDouble();
            }
          } else if (sensorId == 'sensor_2') {
            // Only new format for sensor 2
            if (sensorData['soil_sensor_2'] != null) {
              value = (sensorData['soil_sensor_2']['value'] as num?)?.toDouble();
            }
          }

          // Extract timestamp
          if (entry['timestamp'] != null) {
            timestamp = DateTime.fromMillisecondsSinceEpoch(entry['timestamp']);
          } else if (entry['recorded_at'] != null) {
            timestamp = DateTime.parse(entry['recorded_at']);
          }

          if (value != null && value > 0 && timestamp != null) {
            chartData.add({
              'value': value,
              'timestamp': timestamp,
              'x': timestamp.millisecondsSinceEpoch.toDouble(),
              'y': value,
            });
          }
        }
      } catch (e) {
        print('❌ [$sensorId] Error processing chart entry: $e');
      }
    }

    // Sort by timestamp
    chartData.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));

    print('📊 [$sensorId] Processed ${chartData.length} chart points');
    return chartData;
  }

  Map<String, dynamic> _calculateStats(List<Map<String, dynamic>> chartData) {
    if (chartData.isEmpty) {
      return {
        'count': 0,
        'average': 0.0,
        'minimum': 0.0,
        'maximum': 0.0,
        'latest': 0.0,
      };
    }

    final values = chartData.map((e) => e['value'] as double).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final latest = values.last;

    return {
      'count': values.length,
      'average': average,
      'minimum': minimum,
      'maximum': maximum,
      'latest': latest,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<GreenhouseProvider>(
          builder: (context, provider, child) {
            final isConnected = provider.isConnected;
            final currentSensorData = provider.sensorData;
            final lastSensorUpdate = provider.lastSensorUpdate;
            
            _checkForNewSensorData(currentSensorData, lastSensorUpdate);
            
            return _isLoading && _historicalData.isEmpty
                ? _buildLoadingState()
                : SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(isConnected),
                        SizedBox(height: 24),
                        _buildPeriodSelector(),
                        SizedBox(height: 24),
                        
                        // KOMPONEN 1: GRAFIK SENSOR 1
                        _buildSensor1Chart(),
                        
                        SizedBox(height: 20),
                        
                        // KOMPONEN 2: GRAFIK SENSOR 2
                        _buildSensor2Chart(),
                        
                        if (_errorMessage != null) ...[
                          SizedBox(height: 16),
                          _buildErrorCard(),
                        ],
                      ],
                    ),
                  );
          },
        ),
      ),
    );
  }

  void _checkForNewSensorData(sensorData, DateTime? lastUpdate) {
    if (sensorData != null && lastUpdate != null) {
      if (_lastDataRefresh == null || lastUpdate.isAfter(_lastDataRefresh!)) {
        print('📨 [MQTT→HISTORY] New sensor data detected, refreshing charts...');
        _lastDataRefresh = lastUpdate;
        
        Future.delayed(Duration(seconds: 2), () {
          if (mounted && !_isLoading) {
            _loadDataForPeriod();
          }
        });
      }
    }
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 24),
          Text(
            'Loading Sensor Charts...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isConnected) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Sensor History Charts',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected 
                ? Colors.green.withOpacity(0.1) 
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6),
              Text(
                'MQTT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 8),
        if (_isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return CustomCard(
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedPeriod,
                isExpanded: true,
                items: periods.map((String period) {
                  return DropdownMenuItem<String>(
                    value: period,
                    child: Text(period),
                  );
                }).toList(),
                onChanged: _isLoading ? null : (String? newValue) {
                  setState(() {
                    selectedPeriod = newValue!;
                  });
                  _loadDataForPeriod();
                },
              ),
            ),
          ),
          SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _isLoading ? null : () => _loadDataForPeriod(),
            tooltip: 'Refresh Charts',
          ),
        ],
      ),
    );
  }

  // KOMPONEN 1: GRAFIK SENSOR 1
  Widget _buildSensor1Chart() {
    final stats = _sensor1Stats;
    
    return CustomCard(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sensor 1 History Chart',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildChartStats(stats, Colors.blue),
            ],
          ),
          SizedBox(height: 16),
          
          // Chart
          Expanded(
            child: _sensor1ChartData.isEmpty 
                ? _buildNoDataChart('Sensor 1')
                : SensorChart(
                    sensorType: 'Sensor 1',
                    period: selectedPeriod,
                    historicalData: _sensor1ChartData,
                    // chartColor: Colors.blue,
                  ),
          ),
          
          // Quick stats
          SizedBox(height: 8),
          _buildQuickStats(stats, Colors.blue),
        ],
      ),
    );
  }

  // KOMPONEN 2: GRAFIK SENSOR 2
  Widget _buildSensor2Chart() {
    final stats = _sensor2Stats;
    
    return CustomCard(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sensor 2 History Chart',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildChartStats(stats, Colors.green),
            ],
          ),
          SizedBox(height: 16),
          
          // Chart
          Expanded(
            child: _sensor2ChartData.isEmpty 
                ? _buildNoDataChart('Sensor 2')
                : SensorChart(
                    sensorType: 'Sensor 2',
                    period: selectedPeriod,
                    historicalData: _sensor2ChartData,
                    // chartColor: Colors.green,
                  ),
          ),
          
          // Quick stats
          SizedBox(height: 8),
          _buildQuickStats(stats, Colors.green),
        ],
      ),
    );
  }

  Widget _buildChartStats(Map<String, dynamic> stats, Color color) {
    final count = stats['count'] ?? 0;
    final latest = stats['latest'] ?? 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count points',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Current: ${latest.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(Map<String, dynamic> stats, Color color) {
    final average = stats['average'] ?? 0.0;
    final minimum = stats['minimum'] ?? 0.0;
    final maximum = stats['maximum'] ?? 0.0;
    
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Avg', '${average.toStringAsFixed(1)}%', color),
          _buildStatItem('Min', '${minimum.toStringAsFixed(1)}%', Colors.orange),
          _buildStatItem('Max', '${maximum.toStringAsFixed(1)}%', Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildNoDataChart(String sensorName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timeline,
            size: 48,
            color: AppColors.textSecondary.withOpacity(0.5),
          ),
          SizedBox(height: 12),
          Text(
            'No $sensorName Data',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Chart will appear when data is available',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return CustomCard(
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error Loading Charts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _loadDataForPeriod,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
}