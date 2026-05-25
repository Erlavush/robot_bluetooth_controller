import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/services/native_classic_bluetooth.dart';

void main() {
  test('splits each native Bluetooth event without waiting for newlines', () {
    expect(splitClassicBluetoothEvent('OK:PONG:BT'), ['OK:PONG:BT']);
    expect(
      splitClassicBluetoothEvent('T:FF,1,2,3,4,5,6,7,8,384'),
      ['T:FF,1,2,3,4,5,6,7,8,384'],
    );
  });

  test('still handles multiple newline-separated lines in one event', () {
    expect(splitClassicBluetoothEvent('STATE:LINE\nOK:TEL=RAW\r\n'), [
      'STATE:LINE',
      'OK:TEL=RAW',
    ]);
  });
}
