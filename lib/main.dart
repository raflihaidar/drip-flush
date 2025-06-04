import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_colors.dart';
import 'core/utils/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/control/control_screen.dart';
import 'screens/history/history_screen.dart';
import 'providers/greenhouse_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  // WAJIB: Pastikan Flutter binding sudah diinisialisasi sebelum Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // INISIALISASI FIREBASE - LETAKKAN DI SINI
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provider untuk state management
        ChangeNotifierProvider(
          create: (context) => GreenhouseProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Greenhouse Monitor',
        theme: AppTheme.lightTheme,
        home: MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
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
  void initState() {
    super.initState();
    // Initialize greenhouse system setelah widget dibuat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GreenhouseProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<GreenhouseProvider>(
        builder: (context, provider, child) {
          // Show loading overlay saat inisialisasi
          if (provider.isLoading && provider.sensorData == null) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Connecting to Firebase...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Show error screen jika ada error
          if (provider.errorMessage != null && provider.sensorData == null) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Connection Error',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: provider.retryConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Retry Connection'),
                    ),
                  ],
                ),
              ),
            );
          }

          // Normal app dengan bottom navigation
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
        },
      ),
    );
  }
}