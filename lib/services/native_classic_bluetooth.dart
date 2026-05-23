import 'package:flutter/services.dart';

class NativeClassicBluetooth {
  static const _channel = MethodChannel(
    'robot_bluetooth_controller/classic_bluetooth',
  );

  static Future<List<Map<String, String>>> getPairedDevices() async {
    final devices = await _channel.invokeListMethod<dynamic>(
      'getPairedDevices',
    );
    return (devices ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (device) => device.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        )
        .toList();
  }

  static Future<bool> connect(String address) async {
    final connected = await _channel.invokeMethod<bool>('connect', {
      'address': address,
    });
    return connected ?? false;
  }

  static Future<void> disconnect() {
    return _channel.invokeMethod<void>('disconnect');
  }

  static Future<void> write(String message) {
    return _channel.invokeMethod<void>('write', {'message': message});
  }
}
