String movementCommandFor({
  required bool upPressed,
  required bool downPressed,
  required bool leftPressed,
  required bool rightPressed,
}) {
  final forward = upPressed && !downPressed;
  final backward = downPressed && !upPressed;
  final left = leftPressed && !rightPressed;
  final right = rightPressed && !leftPressed;

  if (forward && left) {
    return 'G';
  }
  if (forward && right) {
    return 'I';
  }
  if (backward && left) {
    return 'H';
  }
  if (backward && right) {
    return 'J';
  }
  if (forward) {
    return 'F';
  }
  if (backward) {
    return 'B';
  }
  if (left) {
    return 'L';
  }
  if (right) {
    return 'R';
  }
  return 'S';
}
