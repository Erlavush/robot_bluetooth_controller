import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/services/command_payload.dart';

void main() {
  test('appends newline to Bluetooth command payloads', () {
    expect(bluetoothPayloadForCommand('F'), 'F\n');
    expect(bluetoothPayloadForCommand('S'), 'S\n');
    expect(bluetoothPayloadForCommand('V100'), 'V100\n');
    expect(bluetoothPayloadForCommand('CCYAN'), 'CCYAN\n');
  });

  test('does not append a duplicate newline', () {
    expect(bluetoothPayloadForCommand('F\n'), 'F\n');
  });
}
