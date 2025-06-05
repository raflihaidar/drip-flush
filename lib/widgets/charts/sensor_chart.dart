import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';

class SensorChart extends StatelessWidget {
  final String sensorType;
  final String period;
  final List<Map<String, dynamic>>? historicalData;

  const SensorChart({
    Key? key,
    required this.sensorType,
    required this.period,
    this.historicalData,
  }) : super(key: key);

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
            verticalInterval: _getVerticalInterval(),
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
                interval: _getBottomInterval(),
                getTitlesWidget: _getBottomTitleWidget,
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
          minX: chartData.first.x,
          maxX: chartData.last.x,
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

  List<FlSpot> _prepareChartData() {
    if (historicalData == null || historicalData!.isEmpty) {
      return [];
    }

    // Sort data by timestamp
    final sortedData = List<Map<String, dynamic>>.from(historicalData!)
      ..sort((a, b) {
        final timestampA = a['timestamp'] as int? ?? 0;
        final timestampB = b['timestamp'] as int? ?? 0;
        return timestampA.compareTo(timestampB);
      });

    // Limit data points based on period for better performance
    final maxPoints = _getMaxDataPoints();
    final dataToUse = sortedData.length > maxPoints 
        ? _sampleData(sortedData, maxPoints)
        : sortedData;

    final spots = <FlSpot>[];
    
    for (int i = 0; i < dataToUse.length; i++) {
      final entry = dataToUse[i];
      
      try {
        // Safe extraction from your Firebase structure: sensor.soil_sensor.value
        final sensorData = entry['sensor'];
        if (sensorData is Map) {
          final soilSensor = sensorData['soil_sensor'];
          if (soilSensor is Map) {
            final value = soilSensor['value'];
            if (value is num && value >= 0 && value <= 100) {
              spots.add(FlSpot(i.toDouble(), value.toDouble()));
            }
          }
        }
      } catch (e) {
        print('❌ Error extracting chart data from entry: $entry, error: $e');
        continue;
      }
    }

    print('📊 [CHART] Prepared ${spots.length} data points for chart');
    return spots;
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

  double _getVerticalInterval() {
    final chartData = _prepareChartData();
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

  double _getBottomInterval() {
    final chartData = _prepareChartData();
    if (chartData.isEmpty) return 1.0;
    
    return (chartData.length / 6).roundToDouble().clamp(1.0, double.infinity);
  }

  Widget _getBottomTitleWidget(double value, TitleMeta meta) {
    final dataPoint = _findDataPointByX(value);
    if (dataPoint == null) return Text('');

    final timestamp = dataPoint['timestamp'] as int? ?? 0;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    
    String text;
    switch (period) {
      case '24 Hours':
        text = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        break;
      case '7 Days':
        text = '${dateTime.day}/${dateTime.month}';
        break;
      case '30 Days':
      case '90 Days':
        text = '${dateTime.day}/${dateTime.month}';
        break;
      default:
        text = '${dateTime.hour}:${dateTime.minute}';
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
    final index = x.round();
    final sortedData = List<Map<String, dynamic>>.from(historicalData!)
      ..sort((a, b) {
        final timestampA = a['timestamp'] as int? ?? 0;
        final timestampB = b['timestamp'] as int? ?? 0;
        return timestampA.compareTo(timestampB);
      });

    final maxPoints = _getMaxDataPoints();
    final dataToUse = sortedData.length > maxPoints 
        ? _sampleData(sortedData, maxPoints)
        : sortedData;

    if (index >= 0 && index < dataToUse.length) {
      return dataToUse[index];
    }
    return null;
  }

  String _formatTooltipTime(Map<String, dynamic> dataPoint) {
    final timestamp = dataPoint['timestamp'] as int? ?? 0;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    
    switch (period) {
      case '24 Hours':
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      case '7 Days':
        return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      case '30 Days':
      case '90 Days':
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      default:
        return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute}';
    }
  }
}