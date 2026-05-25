import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/main.dart';
import 'package:robot_bluetooth_controller/services/bluetooth_service.dart';

void main() {
  testWidgets('shows manual robot controller controls', (tester) async {
    await tester.pumpWidget(
      RobotControllerApp(bluetoothService: RobotBluetoothService()),
    );

    expect(find.text('Traversal Mode'), findsOneWidget);
    expect(find.text('HC-05'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
  });
}
