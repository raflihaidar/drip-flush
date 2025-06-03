import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/utils/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/control/control_screen.dart';
import 'screens/history/history_screen.dart';
import 'services/mqtt_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';


// Di main.dart atau widget Anda
void testOfficialMethod() async {
  // Test connection dulu
  bool testResult = await MqttService.testConnection();
  
  if (testResult) {    
    // Gunakan service utama
    final mqttService = MqttService();
    bool connected = await mqttService.prepareMqttClient();
    
    if (connected) {
      print('✅ Service ready!');
      
      // Test publish
      await Future.delayed(Duration(seconds: 2));
      await mqttService.testPublish();
      
      // Test pump control
      await Future.delayed(Duration(seconds: 2));
      await mqttService.controlPump(true);
      
    } else {
      print('❌ Service connection failed');
    }
  } else {
    print('❌ Test connection failed');
  }
}

void main() async {
    // WAJIB: Pastikan Flutter binding sudah diinisialisasi sebelum Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // INISIALISASI FIREBASE - LETAKKAN DI SINI
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  testOfficialMethod();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Greenhouse Monitor',
      theme: AppTheme.lightTheme,
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1; // Start with home

  final List<Widget> _screens = [
    ControlScreen(),
    HomeScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        elevation: 8,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_remote),
            label: 'Control',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}