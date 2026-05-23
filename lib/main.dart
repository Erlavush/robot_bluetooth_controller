import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/controller_screen.dart';
import 'services/bluetooth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final bluetoothService = RobotBluetoothService();
  await bluetoothService.initialize();

  runApp(RobotControllerApp(bluetoothService: bluetoothService));
}

class RobotControllerApp extends StatelessWidget {
  const RobotControllerApp({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101318);
    const surface = Color(0xFF191F27);
    const accent = Color(0xFF33D2B2);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Robot Controller',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: Color(0xFFFFC857),
          tertiary: Color(0xFFFF5C7A),
          surface: surface,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: Color(0xFFD8DEE9)),
        ),
      ),
      home: ControllerScreen(bluetoothService: bluetoothService),
    );
  }
}
