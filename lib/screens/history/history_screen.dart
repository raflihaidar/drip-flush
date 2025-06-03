import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/custom_card.dart';
import '../../widgets/charts/sensor_chart.dart';

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedSensor = 'Temperature';
  String selectedPeriod = '7 Days';

  final List<String> sensors = [
    'Temperature',
    'Humidity',
    'Soil Moisture',
    'pH Level',
    'Plant Health'
  ];

  final List<String> periods = ['24 Hours', '7 Days', '30 Days', '90 Days'];

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
              _buildFilterOptions(),
              SizedBox(height: 24),
              _buildChart(),
              SizedBox(height: 24),
              _buildSummaryCards(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      'Sensor History',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
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
                onChanged: (String? newValue) {
                  setState(() {
                    selectedPeriod = newValue!;
                  });
                },
              ),
            ),
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
                '$selectedSensor Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: SensorChart(
              sensorType: selectedSensor,
              period: selectedPeriod,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summary Statistics',
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
              child: _buildStatCard('Average', '24.2°C', AppColors.primary),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard('Maximum', '26.8°C', AppColors.warning),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard('Minimum', '22.1°C', Colors.blue),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard('Variance', '±1.2°C', Colors.purple),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
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
        ],
      ),
    );
  }
}