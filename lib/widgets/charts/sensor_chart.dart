import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class SensorChart extends StatelessWidget {
  final String sensorType;
  final String period;

  const SensorChart({
    Key? key,
    required this.sensorType,
    required this.period,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: CustomPaint(
        painter: ChartPainter(sensorType: sensorType),
        child: Container(),
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final String sensorType;

  ChartPainter({required this.sensorType});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // Sample data points for the chart
    final dataPoints = _generateSampleData();
    
    // Draw grid lines
    _drawGrid(canvas, size);
    
    // Draw the chart line and fill
    final path = Path();
    final fillPath = Path();
    
    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final y = size.height - (dataPoints[i] / 100) * size.height;
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    
    // Draw fill first, then line
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
    
    // Draw data points
    final pointPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
      
    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final y = size.height - (dataPoints[i] / 100) * size.height;
      canvas.drawCircle(Offset(x, y), 3, pointPaint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    // Horizontal grid lines
    for (int i = 0; i <= 5; i++) {
      final y = (i / 5) * size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Vertical grid lines
    for (int i = 0; i <= 7; i++) {
      final x = (i / 7) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }

  List<double> _generateSampleData() {
    // Generate sample data based on sensor type
    switch (sensorType) {
      case 'Temperature':
        return [65, 70, 68, 72, 75, 74, 76, 73, 71, 69, 67, 70, 72, 74];
      case 'Humidity':
        return [80, 82, 85, 83, 78, 76, 74, 77, 79, 81, 84, 86, 83, 80];
      case 'Soil Moisture':
        return [60, 65, 63, 68, 70, 67, 64, 62, 66, 69, 71, 68, 65, 63];
      case 'pH Level':
        return [50, 52, 51, 53, 54, 52, 50, 51, 53, 55, 54, 52, 51, 50];
      case 'Plant Health':
        return [90, 92, 94, 93, 95, 96, 94, 92, 93, 95, 97, 96, 94, 93];
      default:
        return [50, 55, 53, 58, 60, 57, 54, 52, 56, 59, 61, 58, 55, 53];
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}