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
  String selectedSensor = 'Temperature';
  String selectedPeriod = '7 Days';
  
  final FirebaseService _firebaseService = FirebaseService();
  
  // Data variables
  Map<String, dynamic>? _dailySummary;
  List<Map<String, dynamic>> _historicalData = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Auto refresh timer
  Timer? _autoRefreshTimer;
  DateTime? _lastDataRefresh;

  final List<String> sensors = [
    'Temperature',
    'Humidity',
    'Soil Moisture',
    'pH Level',
    'Plant Health'
  ];

  final List<String> periods = ['24 Hours', '7 Days', '30 Days', '90 Days'];

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    // Cancel timers
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
      // Initialize Firebase if not already initialized
      print('🔥 [INIT] Initializing Firebase service...');
      await _firebaseService.initialize();
      print('✅ [INIT] Firebase service initialized');
      
      // Load initial data immediately
      print('📚 [INIT] Loading initial historical data...');
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

  // Auto refresh every 30 seconds, seperti HomeScreen
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
    
    // Don't set loading true if we're already loading from init
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

      // Calculate date range based on selected period
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

      // Load historical sensor data - this returns the values from sensor_history collection
      print('🔍 [LOAD] Fetching sensor history...');
      final historicalData = await _firebaseService.getSensorHistory(
        startDate: startDate,
        endDate: endDate,
        limit: selectedPeriod == '24 Hours' ? 100 : null,
      );

      // Load today's daily summary from daily_summaries/sensor/{date}
      final todayKey = _getDateKey(now);
      print('🔍 [LOAD] Fetching daily summary for: $todayKey');
      final dailySummary = await _firebaseService.getDailySummary('sensor', todayKey);

      if (mounted) {
        setState(() {
          _historicalData = historicalData;
          _dailySummary = dailySummary;
          _errorMessage = null;
          if (shouldShowLoading) {
            _isLoading = false;
          }
        });
      }

      print('✅ [LOAD] Data loaded - Historical: ${historicalData.length} records, Daily Summary: ${dailySummary != null ? "Found" : "None"}');

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

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<GreenhouseProvider>(
          builder: (context, provider, child) {
            // Listen untuk perubahan data dari MQTT melalui GreenhouseProvider
            final isConnected = provider.isConnected;
            final isProviderLoading = provider.isLoading;
            final currentSensorData = provider.sensorData;
            final lastSensorUpdate = provider.lastSensorUpdate;
            
            // Auto refresh history ketika ada data sensor baru dari MQTT
            _checkForNewSensorData(currentSensorData, lastSensorUpdate);
            
            return _isLoading && _historicalData.isEmpty
                ? _buildLoadingState()
                : SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(isConnected, isProviderLoading),
                        SizedBox(height: 24),
                        _buildFilterOptions(),
                        SizedBox(height: 24),
                        _buildChart(),
                        SizedBox(height: 24),
                        _buildSummaryCards(),
                        if (_errorMessage != null) ...[
                          SizedBox(height: 16),
                          _buildErrorCard(),
                        ],
                        // Show current sensor data dari provider
                        if (currentSensorData != null) ...[
                          SizedBox(height: 16),
                          _buildCurrentDataCard(currentSensorData, lastSensorUpdate),
                        ],
                      ],
                    ),
                  );
          },
        ),
      ),
    );
  }

  // Check for new sensor data dan trigger refresh history
  void _checkForNewSensorData(sensorData, DateTime? lastUpdate) {
    if (sensorData != null && lastUpdate != null) {
      if (_lastDataRefresh == null || lastUpdate.isAfter(_lastDataRefresh!)) {
        print('📨 [MQTT→HISTORY] New sensor data detected, refreshing history...');
        _lastDataRefresh = lastUpdate;
        
        // Debounce refresh to avoid too frequent updates
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
            'Loading Historical Data...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Fetching sensor history and statistics',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isConnected, bool isProviderLoading) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Sensor History',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // MQTT connection status indicator
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
                  color: isConnected 
                      ? Colors.green 
                      : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6),
              Text(
                'MQTT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isConnected 
                      ? Colors.green 
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 8),
        if (_isLoading || isProviderLoading)
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

  Widget _buildFilterOptions() {
    return Row(
      children: [
        Expanded(
          child: CustomCard(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  print('📊 [FILTER] Period changed to: $selectedPeriod');
                  _loadDataForPeriod();
                },
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        CustomCard(
          padding: EdgeInsets.all(8),
          child: IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _isLoading ? null : () {
              print('🔄 [MANUAL] Manual refresh triggered');
              _loadDataForPeriod();
            },
            tooltip: 'Refresh Data',
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    return CustomCard(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Soil Moisture Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              Row(
                children: [
                  Text(
                    '${_historicalData.length} readings',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(width: 8),
                  Consumer<GreenhouseProvider>(
                    builder: (context, provider, child) {
                      return Icon(
                        provider.isConnected ? Icons.wifi : Icons.wifi_off,
                        size: 12,
                        color: provider.isConnected ? Colors.green : Colors.grey,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: SensorChart(
              sensorType: selectedSensor,
              period: selectedPeriod,
              historicalData: _historicalData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final stats = _calculateStatistics();
    
    // Use daily summary if available (from daily_summaries/sensor/{date}), otherwise use calculated stats
    final averageValue = _dailySummary?['average_value'] ?? stats['average'];
    final maxValue = _dailySummary?['max_value'] ?? stats['maximum'];
    final minValue = _dailySummary?['min_value'] ?? stats['minimum'];
    final varianceValue = stats['variance'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Summary Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Spacer(),
            if (_dailySummary != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Average', 
                '${averageValue.toStringAsFixed(1)}%', 
                AppColors.primary,
                subtitle: _dailySummary != null ? '${_dailySummary!['count']} readings' : '${stats['count']} readings',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Maximum', 
                '${maxValue.toStringAsFixed(1)}%', 
                AppColors.warning,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Minimum', 
                '${minValue.toStringAsFixed(1)}%', 
                Colors.blue,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Variance', 
                '±${varianceValue.toStringAsFixed(1)}%', 
                Colors.purple,
              ),
            ),
          ],
        ),
        if (_dailySummary != null) ...[
          SizedBox(height: 12),
          _buildDailySummaryInfo(),
        ],
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, {String? subtitle}) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailySummaryInfo() {
    if (_dailySummary == null) return SizedBox.shrink();

    final firstReading = _dailySummary!['first_reading'];
    final lastReading = _dailySummary!['last_reading'];

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.today,
                size: 16,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                'Today\'s Activity',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (firstReading != null && firstReading is String)
            _buildInfoRow('First Reading', _formatTime(firstReading)),
          if (lastReading != null && lastReading is String)
            _buildInfoRow('Last Reading', _formatTime(lastReading)),
          _buildInfoRow('Total Readings', '${_dailySummary!['count'] ?? 0} times'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
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
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error Loading Data',
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
            onPressed: () {
              print('🔄 [RETRY] Retry button pressed');
              _loadDataForPeriod();
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentDataCard(sensorData, DateTime? lastUpdate) {
    final soilHumidity = sensorData.sensor.soilSensor.value;
    final soilCondition = sensorData.sensor.soilSensor.condition;
    
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sensors,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Current Sensor Data (Live)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Soil Moisture',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${soilHumidity.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Condition',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      soilCondition,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getConditionColor(soilCondition),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (lastUpdate != null) ...[
            SizedBox(height: 8),
            Text(
              'Last updated: ${_formatDateTime(lastUpdate)}',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getConditionColor(String condition) {
    switch (condition.toLowerCase()) {
      case 'optimal':
        return Colors.green;
      case 'dry':
        return Colors.orange;
      case 'wet':
        return Colors.blue;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      print('❌ Error parsing time: $isoString, error: $e');
      return 'Invalid time';
    }
  }

  // Calculate statistics from historical data matching your Firebase structure
  Map<String, dynamic> _calculateStatistics() {
    if (_historicalData.isEmpty) {
      return {
        'average': 0.0,
        'maximum': 0.0,
        'minimum': 0.0,
        'variance': 0.0,
        'count': 0,
      };
    }

    // Extract values from your Firebase structure: sensor.soil_sensor.value
    final values = _historicalData
        .map((entry) {
          try {
            // Safe casting to handle different data types
            final sensorData = entry['sensor'];
            if (sensorData is Map) {
              final soilSensor = sensorData['soil_sensor'];
              if (soilSensor is Map) {
                final value = soilSensor['value'];
                if (value is num) {
                  return value.toDouble();
                }
              }
            }
            return 0.0;
          } catch (e) {
            print('❌ Error extracting sensor value from entry: $entry, error: $e');
            return 0.0;
          }
        })
        .where((value) => value > 0)
        .toList();

    if (values.isEmpty) {
      return {
        'average': 0.0,
        'maximum': 0.0,
        'minimum': 0.0,
        'variance': 0.0,
        'count': 0,
      };
    }

    final average = values.reduce((a, b) => a + b) / values.length;
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    
    // Calculate variance
    final squaredDiffs = values.map((value) => (value - average) * (value - average));
    final variance = squaredDiffs.reduce((a, b) => a + b) / values.length;

    return {
      'average': average,
      'maximum': maximum,
      'minimum': minimum,
      'variance': variance,
      'count': values.length,
    };
  }
}