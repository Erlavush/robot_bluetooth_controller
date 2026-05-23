import 'package:bluetooth_serial_android/bluetooth_serial_android.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'command_payload.dart';
import 'native_classic_bluetooth.dart';

class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({required this.name, required this.address});

  final String name;
  final String address;

  factory BluetoothDeviceInfo.fromMap(Map<String, String> map) {
    return BluetoothDeviceInfo(
      name: (map['name']?.trim().isNotEmpty ?? false)
          ? map['name']!.trim()
          : 'Unknown device',
      address: map['address'] ?? '',
    );
  }
}

class LedOption {
  const LedOption(this.label, this.command, this.color);

  final String label;
  final String command;
  final int color;
}

class ModeOption {
  const ModeOption(this.label, this.command);

  final String label;
  final String command;
}

class RobotBluetoothService extends ChangeNotifier {
  static const _lastDeviceNameKey = 'last_device_name';
  static const _lastDeviceAddressKey = 'last_device_address';

  final List<BluetoothDeviceInfo> _pairedDevices = [];

  BluetoothDeviceInfo? _selectedDevice;
  bool _connected = false;
  bool _busy = false;
  String _statusMessage = 'Disconnected';
  int _speed = 120;
  String _ledLabel = 'Off';
  String _modeLabel = 'Manual';
  String? _lastSentCommand;

  List<BluetoothDeviceInfo> get pairedDevices =>
      List.unmodifiable(_pairedDevices);
  BluetoothDeviceInfo? get selectedDevice => _selectedDevice;
  bool get isConnected => _connected;
  bool get isBusy => _busy;
  String get statusMessage => _statusMessage;
  int get speed => _speed;
  String get ledLabel => _ledLabel;
  String get modeLabel => _modeLabel;
  String? get lastSentCommand => _lastSentCommand;

  String get selectedDeviceLabel {
    final device = _selectedDevice;
    if (device == null) {
      return 'No device selected';
    }
    return '${device.name} (${device.address})';
  }

  Future<void> initialize() async {
    await _restoreLastDevice();
    await ensurePermissions();
    await refreshPairedDevices();
  }

  Future<bool> ensurePermissions() async {
    try {
      final granted = await FlutterBluetoothSerial.ensurePermissions();
      if (!granted) {
        _statusMessage = 'Bluetooth permission requested';
        notifyListeners();
      }
      return granted;
    } catch (error) {
      _statusMessage = 'Permission error: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshPairedDevices() async {
    _busy = true;
    _statusMessage = _connected ? 'Connected' : 'Loading paired devices';
    notifyListeners();

    try {
      await ensurePermissions();
      final rawDevices = await NativeClassicBluetooth.getPairedDevices();
      final devices =
          rawDevices
              .map(BluetoothDeviceInfo.fromMap)
              .where((device) => device.address.isNotEmpty)
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      _pairedDevices
        ..clear()
        ..addAll(devices);

      final selected = _selectedDevice;
      if (selected != null) {
        final index = _pairedDevices.indexWhere(
          (device) => device.address == selected.address,
        );
        if (index >= 0) {
          _selectedDevice = _pairedDevices[index];
        }
      }

      _statusMessage = _connected ? 'Connected' : 'Disconnected';
    } catch (error) {
      _statusMessage = 'Device list error: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> selectDevice(BluetoothDeviceInfo device) async {
    _selectedDevice = device;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDeviceNameKey, device.name);
    await prefs.setString(_lastDeviceAddressKey, device.address);
    notifyListeners();
  }

  Future<void> connect() async {
    final device = _selectedDevice;
    if (device == null || _busy) {
      return;
    }

    _busy = true;
    _statusMessage = 'Connecting to ${device.name}';
    notifyListeners();

    try {
      await ensurePermissions();
      final ok = await NativeClassicBluetooth.connect(device.address);
      _connected = ok;
      _statusMessage = ok ? 'Connected' : 'Connection failed';
    } catch (error) {
      _connected = false;
      _statusMessage = 'Connection error: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool sendStop = true}) async {
    if (_busy) {
      return;
    }

    _busy = true;
    notifyListeners();

    try {
      if (_connected && sendStop) {
        await sendRawCommand('S', force: true);
      }
      await NativeClassicBluetooth.disconnect();
    } catch (error) {
      _statusMessage = 'Disconnect error: $error';
    } finally {
      _connected = false;
      _busy = false;
      _statusMessage = 'Disconnected';
      notifyListeners();
    }
  }

  Future<void> sendRawCommand(String command, {bool force = false}) async {
    if (!_connected || command.isEmpty) {
      return;
    }

    if (!force && _lastSentCommand == command) {
      return;
    }

    try {
      final payload = bluetoothPayloadForCommand(command);
      await NativeClassicBluetooth.write(payload);
      _lastSentCommand = command;
      debugPrint('Bluetooth TX: $command');
      notifyListeners();
    } catch (error) {
      _connected = false;
      _statusMessage = 'Send failed: $error';
      notifyListeners();
    }
  }

  Future<void> sendMovementCommand(String command) {
    return sendRawCommand(command);
  }

  void previewSpeed(int speed) {
    _speed = speed.clamp(50, 255);
    notifyListeners();
  }

  Future<void> setSpeed(int speed) async {
    _speed = speed.clamp(50, 255);
    notifyListeners();
    await sendRawCommand('V$_speed', force: true);
  }

  Future<void> setLed(LedOption option) async {
    _ledLabel = option.label;
    notifyListeners();
    await sendRawCommand(option.command, force: true);
  }

  Future<void> setMode(ModeOption option) async {
    _modeLabel = option.label;
    notifyListeners();
    await sendRawCommand(option.command, force: true);
  }

  Future<void> _restoreLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_lastDeviceNameKey);
    final address = prefs.getString(_lastDeviceAddressKey);
    if (name != null && address != null && address.isNotEmpty) {
      _selectedDevice = BluetoothDeviceInfo(name: name, address: address);
    }
  }
}
