import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/services/movement_protocol.dart';

void main() {
  test('maps button states to robot movement commands', () {
    expect(_command(), 'S');
    expect(_command(up: true), 'F');
    expect(_command(down: true), 'B');
    expect(_command(left: true), 'L');
    expect(_command(right: true), 'R');
    expect(_command(up: true, left: true), 'G');
    expect(_command(up: true, right: true), 'I');
    expect(_command(down: true, left: true), 'H');
    expect(_command(down: true, right: true), 'J');
  });
}

String _command({
  bool up = false,
  bool down = false,
  bool left = false,
  bool right = false,
}) {
  return movementCommandFor(
    upPressed: up,
    downPressed: down,
    leftPressed: left,
    rightPressed: right,
  );
}
