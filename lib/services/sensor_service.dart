// import '../models/sensor_data.dart';

// class SensorService {
//   static Future<List<SensorData>> getSensorData() async {
//     // Simulate API call delay
//     await Future.delayed(Duration(milliseconds: 500));
    
//     return [
//       SensorData(
//         name: 'Temperature',
//         value: 24.5,
//         unit: '°C',
//         timestamp: DateTime.now(),
//         isActive: true,
//       ),
//       SensorData(
//         name: 'Humidity',
//         value: 82.0,
//         unit: '%',
//         timestamp: DateTime.now(),
//         isActive: true,
//       ),
//       SensorData(
//         name: 'Soil Moisture',
//         value: 65.0,
//         unit: '%',
//         timestamp: DateTime.now(),
//         isActive: true,
//       ),
//       SensorData(
//         name: 'pH Level',
//         value: 7.6,
//         unit: '',
//         timestamp: DateTime.now(),
//         isActive: true,
//       ),
//       SensorData(
//         name: 'Plant Health',
//         value: 94.0,
//         unit: '%',
//         timestamp: DateTime.now(),
//         isActive: true,
//       ),
//     ];
//   }

//   static Future<List<SensorData>> getHistoricalData(
//     String sensorType,
//     String period,
//   ) async {
//     await Future.delayed(Duration(milliseconds: 300));
    
//     // Generate sample historical data
//     final List<SensorData> data = [];
//     final now = DateTime.now();
    
//     int dataPoints = period == '24 Hours' ? 24 : 
//                     period == '7 Days' ? 7 : 
//                     period == '30 Days' ? 30 : 90;
    
//     for (int i = 0; i < dataPoints; i++) {
//       data.add(SensorData(
//         name: sensorType,
//         value: _generateRandomValue(sensorType),
//         unit: _getUnit(sensorType),
//         timestamp: now.subtract(Duration(
//           hours: period == '24 Hours' ? i : 0,
//           days: period != '24 Hours' ? i : 0,
//         )),
//         isActive: true,
//       ));
//     }
    
//     return data.reversed.toList();
//   }

//   static double _generateRandomValue(String sensorType) {
//     switch (sensorType) {
//       case 'Temperature':
//         return 20.0 + (10.0 * (DateTime.now().millisecond % 100) / 100);
//       case 'Humidity':
//         return 70.0 + (20.0 * (DateTime.now().millisecond % 100) / 100);
//       case 'Soil Moisture':
//         return 50.0 + (30.0 * (DateTime.now().millisecond % 100) / 100);
//       case 'pH Level':
//         return 6.0 + (2.0 * (DateTime.now().millisecond % 100) / 100);
//       case 'Plant Health':
//         return 85.0 + (15.0 * (DateTime.now().millisecond % 100) / 100);
//       default:
//         return 50.0;
//     }
//   }

//   static String _getUnit(String sensorType) {
//     switch (sensorType) {
//       case 'Temperature':
//         return '°C';
//       case 'Humidity':
//       case 'Soil Moisture':
//       case 'Plant Health':
//         return '%';
//       case 'pH Level':
//         return '';
//       default:
//         return '';
//     }
//   }
// }