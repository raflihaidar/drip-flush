import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';

class SensorChart extends StatelessWidget {
  final String sensorType;
  final String period;
  final List<Map<String, dynamic>>? historicalData;

  const SensorChart({
    super.key,
    required this.sensorType,
    required this.period,
    this.historicalData,
  });

  @override
  Widget build(BuildContext context) {
    if (historicalData == null || historicalData!.isEmpty) {
      return _buildEmptyChart();
    }

    return _buildChart();
  }

  Widget _buildEmptyChart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No data available for this period',
            style: TextStyle(
              color: Colors.grey[600] ?? Colors.grey,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Historical data will appear here',
            style: TextStyle(
              color: Colors.grey[500] ?? Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final chartData = _prepareChartData();
    
    if (chartData.isEmpty) {
      return _buildEmptyChart();
    }

    return Padding(
      padding: EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 20,
            verticalInterval: _getVerticalInterval(chartData),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[300] ?? Colors.grey,
                strokeWidth: 0.5,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: Colors.grey[300] ?? Colors.grey,
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _getBottomInterval(chartData),
                getTitlesWidget: (value, meta) => _getBottomTitleWidget(value, meta, chartData),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 20,
                reservedSize: 40,
                getTitlesWidget: _getLeftTitleWidget,
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: Colors.grey[300] ?? Colors.grey,
              width: 1,
            ),
          ),
          minX: chartData.isNotEmpty ? chartData.first.x : 0,
          maxX: chartData.isNotEmpty ? chartData.last.x : 1,
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: chartData,
              isCurved: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withOpacity(0.7),
                ],
              ),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: chartData.length <= 20, // Show dots only for smaller datasets
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: AppColors.primary,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.3),
                    AppColors.primary.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: AppColors.primary.withOpacity(0.9),
              tooltipRoundedRadius: 8,
              tooltipPadding: EdgeInsets.all(8),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final dataPoint = _findDataPointByX(barSpot.x);
                  final value = barSpot.y.toStringAsFixed(1);
                  final time = dataPoint != null ? _formatTooltipTime(dataPoint) : '';
                  
                  return LineTooltipItem(
                    '$value%\n$time',
                    TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  // FIXED: Proper data preparation with safe timestamp handling
  List<FlSpot> _prepareChartData() {
    if (historicalData == null || historicalData!.isEmpty) {
      return [];
    }

    print('📊 [CHART] Starting chart data preparation...');
    print('📊 [CHART] Raw data count: ${historicalData!.length}');

    // Step 1: Convert and validate data with safe timestamp extraction
    final validEntries = <Map<String, dynamic>>[];
    
    for (final entry in historicalData!) {
      try {
        // Safe timestamp extraction - handle both DateTime and int formats
        DateTime? timestamp;
        dynamic timestampValue = entry['timestamp'];
        
        if (timestampValue is DateTime) {
          timestamp = timestampValue;
        } else if (timestampValue is int) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue);
        } else if (timestampValue is String) {
          // Try parsing string timestamp
          try {
            timestamp = DateTime.parse(timestampValue);
          } catch (e) {
            // Try parsing as milliseconds string
            final intValue = int.tryParse(timestampValue);
            if (intValue != null) {
              timestamp = DateTime.fromMillisecondsSinceEpoch(intValue);
            }
          }
        }

        // Safe value extraction - handle your specific data structure
        double? value;
        
        // Try the format from your history_screen.dart first
        if (entry.containsKey('value') && entry['value'] is num) {
          value = (entry['value'] as num).toDouble();
        }
        // Try y coordinate (from your processed data)
        else if (entry.containsKey('y') && entry['y'] is num) {
          value = (entry['y'] as num).toDouble();
        }
        // Try nested sensor structure
        else if (entry.containsKey('sensor')) {
          final sensorData = entry['sensor'];
          if (sensorData is Map) {
            // Try different sensor formats
            final possiblePaths = [
              ['soil_sensor_1', 'value'],
              ['soil_sensor_2', 'value'], 
              ['soil_sensor', 'value'],
              ['value'],
            ];
            
            for (final path in possiblePaths) {
              dynamic current = sensorData;
              bool found = true;
              
              for (final key in path) {
                if (current is Map && current.containsKey(key)) {
                  current = current[key];
                } else {
                  found = false;
                  break;
                }
              }
              
              if (found && current is num) {
                value = current.toDouble();
                break;
              }
            }
          }
        }

        // Validate both timestamp and value
        if (timestamp != null && value != null && value >= 0 && value <= 100) {
          validEntries.add({
            'timestamp': timestamp,
            'value': value,
            'originalEntry': entry, // Keep reference for tooltip
          });
        }
      } catch (e) {
        print('❌ [CHART] Error processing entry: $entry, error: $e');
        continue;
      }
    }

    print('📊 [CHART] Valid entries after processing: ${validEntries.length}');

    if (validEntries.isEmpty) {
      print('❌ [CHART] No valid entries found');
      return [];
    }

    // Step 2: Sort by timestamp (now safe because all timestamps are DateTime)
    validEntries.sort((a, b) {
      final DateTime timestampA = a['timestamp'];
      final DateTime timestampB = b['timestamp'];
      return timestampA.compareTo(timestampB);
    });

    // Step 3: Limit data points for performance
    final maxPoints = _getMaxDataPoints();
    final dataToUse = validEntries.length > maxPoints 
        ? _sampleData(validEntries, maxPoints)
        : validEntries;

    print('📊 [CHART] Data points after sampling: ${dataToUse.length}');

    // Step 4: Create FlSpot objects and store processed data for tooltips
    final spots = <FlSpot>[];
    
    for (int i = 0; i < dataToUse.length; i++) {
      final entry = dataToUse[i];
      final value = entry['value'] as double;
      
      // Use index as X coordinate for consistent spacing
      spots.add(FlSpot(i.toDouble(), value));
    }

    print('📊 [CHART] Final chart spots: ${spots.length}');
    
    return spots;
  }

  // Helper method to get processed data for tooltips and titles
  List<Map<String, dynamic>> _getProcessedData() {
    if (historicalData == null || historicalData!.isEmpty) {
      return [];
    }

    final validEntries = <Map<String, dynamic>>[];
    
    for (final entry in historicalData!) {
      try {
        DateTime? timestamp;
        dynamic timestampValue = entry['timestamp'];
        
        if (timestampValue is DateTime) {
          timestamp = timestampValue;
        } else if (timestampValue is int) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue);
        } else if (timestampValue is String) {
          try {
            timestamp = DateTime.parse(timestampValue);
          } catch (e) {
            final intValue = int.tryParse(timestampValue);
            if (intValue != null) {
              timestamp = DateTime.fromMillisecondsSinceEpoch(intValue);
            }
          }
        }

        double? value;
        if (entry.containsKey('value') && entry['value'] is num) {
          value = (entry['value'] as num).toDouble();
        } else if (entry.containsKey('y') && entry['y'] is num) {
          value = (entry['y'] as num).toDouble();
        }

        if (timestamp != null && value != null && value >= 0 && value <= 100) {
          validEntries.add({
            'timestamp': timestamp,
            'value': value,
            'originalEntry': entry,
          });
        }
      } catch (e) {
        continue;
      }
    }

    if (validEntries.isEmpty) return [];

    validEntries.sort((a, b) {
      final DateTime timestampA = a['timestamp'];
      final DateTime timestampB = b['timestamp'];
      return timestampA.compareTo(timestampB);
    });

    final maxPoints = _getMaxDataPoints();
    return validEntries.length > maxPoints 
        ? _sampleData(validEntries, maxPoints)
        : validEntries;
  }

  int _getMaxDataPoints() {
    switch (period) {
      case '24 Hours':
        return 48; // Every 30 minutes
      case '7 Days':
        return 168; // Every hour
      case '30 Days':
        return 120; // Every 6 hours
      case '90 Days':
        return 180; // Every 12 hours
      default:
        return 100;
    }
  }

  List<Map<String, dynamic>> _sampleData(List<Map<String, dynamic>> data, int maxPoints) {
    if (data.length <= maxPoints) return data;
    
    final step = data.length / maxPoints;
    final sampledData = <Map<String, dynamic>>[];
    
    for (int i = 0; i < maxPoints; i++) {
      final index = (i * step).floor();
      if (index < data.length) {
        sampledData.add(data[index]);
      }
    }
    
    return sampledData;
  }

  double _getVerticalInterval(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 1.0;
    
    switch (period) {
      case '24 Hours':
        return chartData.length > 24 ? (chartData.length / 6).roundToDouble() : 4.0;
      case '7 Days':
        return chartData.length > 14 ? (chartData.length / 7).roundToDouble() : 2.0;
      case '30 Days':
        return chartData.length > 30 ? (chartData.length / 10).roundToDouble() : 3.0;
      case '90 Days':
        return chartData.length > 90 ? (chartData.length / 12).roundToDouble() : 7.0;
      default:
        return (chartData.length / 6).roundToDouble();
    }
  }

  double _getBottomInterval(List<FlSpot> chartData) {
    if (chartData.isEmpty) return 1.0;
    
    return (chartData.length / 6).roundToDouble().clamp(1.0, double.infinity);
  }

  Widget _getBottomTitleWidget(double value, TitleMeta meta, List<FlSpot> chartData) {
    final dataPoint = _findDataPointByX(value);
    if (dataPoint == null) return Text('');

    final DateTime timestamp = dataPoint['timestamp'];
    
    String text;
    switch (period) {
      case '24 Hours':
        text = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
        break;
      case '7 Days':
        text = '${timestamp.day}/${timestamp.month}';
        break;
      case '30 Days':
      case '90 Days':
        text = '${timestamp.day}/${timestamp.month}';
        break;
      default:
        text = '${timestamp.hour}:${timestamp.minute}';
    }

    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey[600] ?? Colors.grey,
          fontWeight: FontWeight.w400,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _getLeftTitleWidget(double value, TitleMeta meta) {
    return Text(
      '${value.toInt()}%',
      style: TextStyle(
        color: Colors.grey[600] ?? Colors.grey,
        fontWeight: FontWeight.w400,
        fontSize: 10,
      ),
    );
  }

  Map<String, dynamic>? _findDataPointByX(double x) {
    final processedData = _getProcessedData();
    final index = x.round();
    
    if (index >= 0 && index < processedData.length) {
      return processedData[index];
    }
    return null;
  }

  String _formatTooltipTime(Map<String, dynamic> dataPoint) {
    final DateTime timestamp = dataPoint['timestamp'];
    
    switch (period) {
      case '24 Hours':
        return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      case '7 Days':
        return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      case '30 Days':
      case '90 Days':
        return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
      default:
        return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute}';
    }
  }
}