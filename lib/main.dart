import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/manual_control_screen.dart';
import 'services/bluetooth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _enterFullscreen();

  final bluetoothService = RobotBluetoothService();
  await bluetoothService.initialize();

  runApp(RobotControllerApp(bluetoothService: bluetoothService));
}

class RobotControllerApp extends StatefulWidget {
  const RobotControllerApp({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  State<RobotControllerApp> createState() => _RobotControllerAppState();
}

class _RobotControllerAppState extends State<RobotControllerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bluetoothService.sendSafetyStop();
    widget.bluetoothService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterFullscreen();
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.bluetoothService.sendSafetyStop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Robot Controller',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Quicksand',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10C772),
          secondary: Color(0xFFFFE066),
          tertiary: Color(0xFFFF3131),
          surface: Color(0xFF0C0C0E),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.white,
          contentTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      home: ManualControlScreen(bluetoothService: widget.bluetoothService),
    );
  }
}

Future<void> _enterFullscreen() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}
