import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/main.dart';
import 'package:robot_bluetooth_controller/services/bluetooth_service.dart';

void main() {
  testWidgets('shows robot controller title', (tester) async {
    await tester.pumpWidget(
      RobotControllerApp(bluetoothService: RobotBluetoothService()),
    );

    expect(find.text('Robot Controller'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
