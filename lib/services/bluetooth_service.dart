import 'dart:async';

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

class RobotTelemetry {
  String sensorBits = '00000000';
  List<int> rawD1ToD8 = List<int>.filled(8, 0);
  bool hasRawValues = false;
  double position = 0;
  int blackCount = 0;
  int threshold = 900;
  int sensorPacketEventId = 0;
  DateTime? lastSensorPacketAt;

  int? node;
  int nodeEventId = 0;
  int? routeIndex;
  int? routeTotal;
  String? command;
  String state = 'MANUAL';
  String? lastOk;
  String? lastError;
  String? warning;
  final Map<String, num> configValues = {};

  List<int> get rawD8ToD1 => rawD1ToD8.reversed.toList();
  List<int> get bitsD8ToD1 => sensorBits
      .split('')
      .map((bit) => bit == '1' ? 1 : 0)
      .toList()
      .reversed
      .toList();

  void parseLine(String line) {
    if (line.startsWith('SENS:')) {
      _parseSensorPacket(line);
      return;
    }

    if (line.startsWith('T:')) {
      _parseCompactTelemetry(line);
      return;
    }

    if (line.startsWith('NODE:')) {
      final parsed = int.tryParse(line.substring(5).trim());
      if (parsed != null) {
        node = parsed;
        nodeEventId++;
      }
      return;
    }

    if (line.startsWith('IDX:')) {
      final parts = line.substring(4).split('/');
      if (parts.length == 2) {
        routeIndex = int.tryParse(parts[0].trim());
        routeTotal = int.tryParse(parts[1].trim());
      }
      return;
    }

    if (line.startsWith('CMD:')) {
      command = line.substring(4).trim();
      return;
    }

    if (line.startsWith('STATE:')) {
      state = line.substring(6).trim();
      return;
    }

    if (line.startsWith('OK:')) {
      lastOk = line.substring(3).trim();
      _parseConfigPair(lastOk!);
      return;
    }

    if (line.startsWith('CFG:')) {
      _parseConfigPair(line.substring(4).trim());
      return;
    }

    if (line.startsWith('ERR:')) {
      lastError = line.substring(4).trim();
      return;
    }

    if (line.startsWith('WARN:')) {
      warning = line.substring(5).trim();
    }
  }

  void _parseSensorPacket(String line) {
    _markSensorPacket(hasRaw: true);
    final parts = line.split('|');
    final bits = parts.first.replaceFirst('SENS:', '').trim();
    if (bits.length == 8) {
      sensorBits = bits;
    }

    for (final part in parts.skip(1)) {
      if (part.startsWith('RAW:')) {
        final values = part
            .substring(4)
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .toList();
        if (values.length == 8 && values.every((value) => value != null)) {
          rawD1ToD8 = values.cast<int>();
        }
      } else if (part.startsWith('POS:')) {
        position = double.tryParse(part.substring(4).trim()) ?? position;
      } else if (part.startsWith('BLACK:')) {
        blackCount = int.tryParse(part.substring(6).trim()) ?? blackCount;
      } else if (part.startsWith('THR:')) {
        threshold = int.tryParse(part.substring(4).trim()) ?? threshold;
        configValues['THR'] = threshold;
      }
    }
  }

  void _parseCompactTelemetry(String line) {
    final parts = line.substring(2).trim().split(',');
    if (parts.isEmpty) {
      return;
    }

    final bitsMask = int.tryParse(parts[0].trim(), radix: 16);
    if (bitsMask == null) {
      return;
    }

    final bits = List<int>.generate(8, (index) => (bitsMask >> index) & 1);
    sensorBits = bits.join();
    blackCount = bits.where((bit) => bit == 1).length;
    if (blackCount > 0) {
      const weights = [7, 5, 3, 1, -1, -3, -5, -7];
      var weightedSum = 0;
      for (var i = 0; i < bits.length; i++) {
        if (bits[i] == 1) {
          weightedSum += weights[i];
        }
      }
      position = weightedSum / blackCount;
    } else {
      position = 0;
    }

    if (parts.length >= 10) {
      final values = parts
          .skip(1)
          .take(8)
          .map((value) => int.tryParse(value.trim(), radix: 16))
          .toList();
      final parsedThreshold = int.tryParse(parts[9].trim(), radix: 16);
      if (values.length == 8 &&
          values.every((value) => value != null) &&
          parsedThreshold != null) {
        rawD1ToD8 = values.cast<int>();
        threshold = parsedThreshold;
        configValues['THR'] = threshold;
        _markSensorPacket(hasRaw: true);
      } else {
        _markSensorPacket(hasRaw: false);
      }
    } else {
      _markSensorPacket(hasRaw: false);
    }
  }

  void _markSensorPacket({required bool hasRaw}) {
    sensorPacketEventId++;
    lastSensorPacketAt = DateTime.now();
    hasRawValues = hasRaw;
  }

  void _parseConfigPair(String pair) {
    final equals = pair.indexOf('=');
    if (equals <= 0) {
      return;
    }

    final key = pair.substring(0, equals).trim().toUpperCase();
    final valueText = pair.substring(equals + 1).trim();
    final parsed = num.tryParse(valueText);
    if (parsed == null) {
      return;
    }

    configValues[key] = parsed;
    if (key == 'THR') {
      threshold = parsed.round();
    }
  }
}

class RobotBluetoothService extends ChangeNotifier {
  static const _lastDeviceNameKey = 'last_device_name';
  static const _lastDeviceAddressKey = 'last_device_address';
  static const manualTelemetryIntervalMs = 1000;
  static const traversalTelemetryIntervalMs = 140;
  static const modeCommandGap = Duration(milliseconds: 250);

  final List<BluetoothDeviceInfo> _pairedDevices = [];
  final List<String> _logs = [];
  final List<String> _manualCommandLogs = [];
  final RobotTelemetry telemetry = RobotTelemetry();

  StreamSubscription<String>? _lineSubscription;
  BluetoothDeviceInfo? _selectedDevice;
  bool _connected = false;
  bool _busy = false;
  String _statusMessage = 'Disconnected';
  int _speed = 180;
  String _ledLabel = 'Blue';
  String _modeLabel = 'Manual';
  String? _lastSentCommand;
  String? _lastQueuedCommand;
  String? _lastManualLogCommand;
  DateTime? _lastManualLogAt;
  DateTime? _lastNativeDebugLogAt;
  Future<void> _writeChain = Future<void>.value();
  int _pendingWriteCount = 0;

  List<BluetoothDeviceInfo> get pairedDevices =>
      List.unmodifiable(_pairedDevices);
  List<String> get logs => List.unmodifiable(_logs);
  List<String> get manualCommandLogs => List.unmodifiable(_manualCommandLogs);
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
    _lineSubscription ??= NativeClassicBluetooth.lines.listen(
      _handleReceivedChunk,
      onError: (Object error) {
        _addLog('RX  ERR:$error', notify: false);
        _statusMessage = 'Bluetooth read error: $error';
        notifyListeners();
      },
    );

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
      if (ok) {
        _addLog('RX  OK:CONNECTED:${device.name}', notify: false);
        await enterManualControlMode();
        await sendRawCommand('PING', force: true);
        await useManualTelemetryRate();
      }
    } catch (error) {
      _connected = false;
      _statusMessage = 'Connection error: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> connectToDevice(BluetoothDeviceInfo device) async {
    await selectDevice(device);
    await connect();
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
      _lastSentCommand = null;
      _lastQueuedCommand = null;
      notifyListeners();
    }
  }

  Future<bool> sendRawCommand(
    String command, {
    bool force = false,
    bool dropIfQueued = false,
  }) async {
    final trimmed = command.trim();
    if (!_connected || trimmed.isEmpty) {
      if (trimmed.isNotEmpty) {
        _statusMessage = 'Connect HC-05 first';
        notifyListeners();
      }
      return false;
    }

    if (!force &&
        (_lastSentCommand == trimmed || _lastQueuedCommand == trimmed)) {
      return true;
    }

    if (dropIfQueued && _pendingWriteCount > 0) {
      return false;
    }

    _lastQueuedCommand = trimmed;
    _pendingWriteCount++;
    final payload = bluetoothPayloadForCommand(trimmed);
    final writeOperation = _writeChain
        .then((_) async {
          if (!_connected) {
            return false;
          }

          try {
            await NativeClassicBluetooth.write(payload);
            _lastSentCommand = trimmed;
            debugPrint('Bluetooth TX: $trimmed');
            _addLog('TX  $trimmed', notify: false);
            _addManualCommandLog(trimmed);
            notifyListeners();
            return true;
          } catch (error) {
            _connected = false;
            _statusMessage = 'Send failed: $error';
            _addLog('RX  ERR:$error', notify: false);
            notifyListeners();
            return false;
          }
        }, onError: (_) async => false)
        .whenComplete(() {
          if (_pendingWriteCount > 0) {
            _pendingWriteCount--;
          }
        });

    _writeChain = writeOperation.then<void>((_) {}, onError: (_) {});
    return writeOperation;
  }

  Future<bool> sendMovementCommand(String command) {
    return sendRawCommand(command);
  }

  Future<void> sendCommandSequence(
    List<String> commands, {
    Duration gap = modeCommandGap,
  }) async {
    for (var i = 0; i < commands.length; i++) {
      await sendRawCommand(commands[i], force: true);
      if (i < commands.length - 1) {
        await Future<void>.delayed(gap);
      }
    }
  }

  Future<void> sendSafetyStop() async {
    if (_connected) {
      await sendRawCommand('S', force: true);
    }
  }

  void previewSpeed(int speed) {
    _speed = speed.clamp(90, 255).toInt();
    notifyListeners();
  }

  Future<void> setSpeed(int speed) async {
    _speed = speed.clamp(90, 255).toInt();
    notifyListeners();
    await sendRawCommand('V$_speed', force: true);
  }

  Future<void> setLed(LedOption option) async {
    _ledLabel = option.label;
    notifyListeners();
    await sendCommandSequence(['MANUAL', option.command]);
  }

  Future<void> setMode(ModeOption option) async {
    _modeLabel = option.label;
    notifyListeners();
    await sendRawCommand(option.command, force: true);
  }

  Future<void> enterManualControlMode({bool restoreBlue = true}) async {
    if (!_connected) {
      return;
    }

    final commands = ['MANUAL', if (restoreBlue) 'CBLUE'];
    if (restoreBlue) {
      _ledLabel = 'Blue';
    }
    await sendCommandSequence(commands);
  }

  Future<void> useManualTelemetryRate() async {
    await sendRawCommand('CFG:TELMS=$manualTelemetryIntervalMs', force: true);
  }

  Future<void> useTraversalTelemetryRate() async {
    await sendRawCommand(
      'CFG:TELMS=$traversalTelemetryIntervalMs',
      force: true,
    );
  }

  Future<void> logNativeDebugStatus({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastNativeDebugLogAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 2)) {
      return;
    }

    _lastNativeDebugLogAt = now;
    try {
      final status = await NativeClassicBluetooth.debugStatus();
      final lastLine = (status['lastLine'] ?? '').toString();
      final preview = lastLine.length > 34
          ? '${lastLine.substring(0, 34)}...'
          : lastLine;
      _addLog(
        'RXDBG socket=${status['socketConnected']} reader=${status['readerRunning']} sink=${status['eventSinkActive']} bytes=${status['bytesRead']} lines=${status['linesRead']} avail=${status['lastAvailable']} loops=${status['readerLoops']} dropped=${status['droppedLines']} last=$preview',
        notify: true,
      );
      final socketConnected = status['socketConnected'] == true;
      final readerRunning = status['readerRunning'] == true;
      final bytesRead = status['bytesRead'];
      final hasNoBytes = bytesRead == 0 || bytesRead == '0' || bytesRead == 0.0;
      if (socketConnected && readerRunning && hasNoBytes) {
        _addLog(
          'RXDBG no incoming bytes from HC-05; check Nano D12/TX -> HC-05 RXD return path',
          notify: true,
        );
      }
    } catch (error) {
      _addLog('RXDBG ERR:$error', notify: true);
    }
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void clearManualCommandLogs() {
    _manualCommandLogs.clear();
    _lastManualLogCommand = null;
    _lastManualLogAt = null;
    notifyListeners();
  }

  void _handleReceivedChunk(String chunk) {
    final line = chunk.trim();
    if (line.isEmpty) {
      return;
    }

    telemetry.parseLine(line);

    if (line.startsWith('STATE:')) {
      final state = line.substring(6).trim();
      if (state == 'MANUAL' || state == 'STOP' || state == 'FAILSAFE_STOP') {
        _modeLabel = 'Manual';
      } else if (state == 'LINE' || state == 'ROUTE') {
        _modeLabel = 'Line';
      }
    }

    if (line.startsWith('OK:SPD=')) {
      _speed = int.tryParse(line.substring(7).trim()) ?? _speed;
    }

    if (line.startsWith('OK:LED=')) {
      _ledLabel = _ledLabelFromAck(line.substring(7).trim());
    }

    if (line.startsWith('SENS:') || line.startsWith('T:')) {
      notifyListeners();
      return;
    }

    _addLog('RX  $line', notify: false);
    notifyListeners();
  }

  void _addLog(String line, {bool notify = true}) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _logs.add('[$stamp] $line');
    if (_logs.length > 140) {
      _logs.removeRange(0, _logs.length - 140);
    }
    if (notify) {
      notifyListeners();
    }
  }

  void _addManualCommandLog(String command) {
    final isMovement = {
      'F',
      'B',
      'L',
      'R',
      'G',
      'I',
      'H',
      'J',
      'S',
    }.contains(command);
    const ledCommands = {
      'CRED',
      'CGREEN',
      'CBLUE',
      'CPINK',
      'CCYAN',
      'CYELLOW',
      'CWHITE',
      'COFF',
      'CPOLICE',
      'CRAINBOW',
      'CRANDOM',
      'RED',
      'GREEN',
      'BLUE',
      'PINK',
      'CYAN',
      'YELLOW',
      'WHITE',
      'OFF',
      'POLICE',
      'RAINBOW',
      'RANDOM',
    };
    final isLed = ledCommands.contains(command);
    final isSpeed = command.startsWith('V');

    if (!isMovement && !isLed && !isSpeed) {
      return;
    }

    final now = DateTime.now();
    final lastLogAt = _lastManualLogAt;
    if (command == 'S' &&
        _lastManualLogCommand == 'S' &&
        lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(milliseconds: 350)) {
      return;
    }

    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _manualCommandLogs.add('[$stamp] $command');
    _lastManualLogCommand = command;
    _lastManualLogAt = now;
    if (_manualCommandLogs.length > 40) {
      _manualCommandLogs.removeRange(0, _manualCommandLogs.length - 40);
    }
  }

  String _ledLabelFromAck(String rawValue) {
    final value = rawValue.toUpperCase();
    return switch (value) {
      'RED' => 'Red',
      'GREEN' => 'Green',
      'BLUE' => 'Blue',
      'PINK' => 'Pink',
      'CYAN' => 'Cyan',
      'YELLOW' => 'Yellow',
      'WHITE' => 'White',
      'OFF' => 'Off',
      'POLICE' => 'Police',
      'RAINBOW' => 'Rainbow',
      'RANDOM' => 'Random',
      _ => rawValue,
    };
  }

  Future<void> _restoreLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_lastDeviceNameKey);
    final address = prefs.getString(_lastDeviceAddressKey);
    if (name != null && address != null && address.isNotEmpty) {
      _selectedDevice = BluetoothDeviceInfo(name: name, address: address);
    }
  }

  @override
  void dispose() {
    _lineSubscription?.cancel();
    super.dispose();
  }
}
