# Flutter Greenhouse Dashboard App

## Project Structure
```
lib/
├── main.dart
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   └── app_strings.dart
│   └── utils/
│       └── app_theme.dart
├── models/
│   ├── sensor_data.dart
│   └── weather_data.dart
├── widgets/
│   ├── common/
│   │   ├── custom_card.dart
│   │   └── sensor_card.dart
│   └── charts/
│       └── sensor_chart.dart
├── screens/
│   ├── control/
│   │   └── control_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   └── history/
│       └── history_screen.dart
└── services/
    └── sensor_service.dart
```
## Key Features

### 🏠 **Home Screen**
- Weather information display
- Sensor status overview (active/inactive counts)
- Two zone cards (First Zone & Second Zone) 
- Grid layout for sensor monitoring (Plant Health, Temperature, pH Level, Humidity, Soil Moisture, Wind Speed)
- Real-time sensor readings with status indicators

### 🎛️ **Control Screen**
- Water pump control with start/stop functionality
- Automatic watering schedule with duration slider
- Device status monitoring
- Real-time status updates with confirmation dialogs

### 📊 **History Screen**
- Interactive sensor data charts
- Dropdown filters for sensor type and time period
- Summary statistics (Average, Maximum, Minimum, Variance)
- Custom painted charts with gradient fills

### 🎨 **Design Features**
- Green theme throughout the app (comfortable and modern)
- Consistent card-based UI design
- Responsive layout that works on different screen sizes
- Material Design 3 principles
- Smooth animations and transitions

### 🔧 **Architecture**
- **Clean Architecture** with separated concerns
- **Reusable Components** (CustomCard, SensorCard)
- **Modular Structure** with organized folders
- **Theme Management** with consistent colors and styles
- **Service Layer** for data management
- **Model Classes** for type safety

### 🚀 **Easy Maintenance**
- Well-documented code structure
- Consistent naming conventions
- Separated business logic from UI
- Configurable constants for easy customization
- Extensible design for adding new features
