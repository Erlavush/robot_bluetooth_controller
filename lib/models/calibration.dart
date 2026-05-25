class CalibrationItem {
  const CalibrationItem({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.command,
  });

  final String key;
  final String label;
  final double min;
  final double max;
  final double step;
  final String command;
}

const calibrationItems = [
  CalibrationItem(
    key: 'threshold',
    label: 'Threshold',
    min: 0,
    max: 1023,
    step: 1,
    command: 'THR',
  ),
  CalibrationItem(
    key: 'baseSpeed',
    label: 'Base SPD',
    min: 90,
    max: 255,
    step: 1,
    command: 'SPD',
  ),
  CalibrationItem(
    key: 'turnSpeed',
    label: 'Turn SPD',
    min: 60,
    max: 255,
    step: 1,
    command: 'TURN',
  ),
  CalibrationItem(
    key: 'slowSpeed',
    label: 'Slow SPD',
    min: 50,
    max: 220,
    step: 1,
    command: 'SLOW',
  ),
  CalibrationItem(
    key: 'manualCurve',
    label: 'Manual Curve',
    min: 35,
    max: 90,
    step: 1,
    command: 'MCURVE',
  ),
  CalibrationItem(
    key: 'kp',
    label: 'Kp',
    min: 0,
    max: 60,
    step: 0.5,
    command: 'KP',
  ),
  CalibrationItem(
    key: 'nodePause',
    label: 'Pause ms',
    min: 0,
    max: 3000,
    step: 10,
    command: 'PAUSE',
  ),
  CalibrationItem(
    key: 'nodeCooldown',
    label: 'Cooldown',
    min: 0,
    max: 3000,
    step: 10,
    command: 'COOLDOWN',
  ),
  CalibrationItem(
    key: 'nodeForward',
    label: 'Node FWD',
    min: 0,
    max: 2500,
    step: 10,
    command: 'NODEFWD',
  ),
  CalibrationItem(
    key: 'turnTimeout',
    label: 'Turn TO',
    min: 200,
    max: 5000,
    step: 50,
    command: 'TURNTIME',
  ),
  CalibrationItem(
    key: 'minTurn',
    label: 'Min Turn',
    min: 0,
    max: 2000,
    step: 10,
    command: 'MINTURN',
  ),
  CalibrationItem(
    key: 'afterTurn',
    label: 'AfterTurn',
    min: 0,
    max: 2000,
    step: 10,
    command: 'AFTERTURN',
  ),
  CalibrationItem(
    key: 'finalForward',
    label: 'Final FWD',
    min: 0,
    max: 1500,
    step: 10,
    command: 'FINALFWD',
  ),
  CalibrationItem(
    key: 'minPwm',
    label: 'Min PWM',
    min: 0,
    max: 255,
    step: 1,
    command: 'MINPWM',
  ),
  CalibrationItem(
    key: 'minPivot',
    label: 'Min Pivot',
    min: 0,
    max: 255,
    step: 1,
    command: 'MINPIVOT',
  ),
  CalibrationItem(
    key: 'leftTrim',
    label: 'L Trim',
    min: -80,
    max: 80,
    step: 1,
    command: 'LTRIM',
  ),
  CalibrationItem(
    key: 'rightTrim',
    label: 'R Trim',
    min: -80,
    max: 80,
    step: 1,
    command: 'RTRIM',
  ),
  CalibrationItem(
    key: 'stableMs',
    label: 'Stable',
    min: 0,
    max: 1000,
    step: 10,
    command: 'STABLEMS',
  ),
  CalibrationItem(
    key: 'lostMs',
    label: 'Lost',
    min: 0,
    max: 1000,
    step: 10,
    command: 'LOSTMS',
  ),
  CalibrationItem(
    key: 'telemetryMs',
    label: 'Telem',
    min: 80,
    max: 1000,
    step: 10,
    command: 'TELMS',
  ),
];

Map<String, double> defaultCalibrationValues() {
  return {
    'threshold': 930,
    'baseSpeed': 155,
    'turnSpeed': 145,
    'slowSpeed': 95,
    'manualCurve': 68,
    'kp': 12,
    'nodePause': 3000,
    'nodeCooldown': 450,
    'nodeForward': 260,
    'turnTimeout': 1900,
    'minTurn': 320,
    'afterTurn': 120,
    'finalForward': 90,
    'minPwm': 90,
    'minPivot': 125,
    'leftTrim': 0,
    'rightTrim': 0,
    'stableMs': 45,
    'lostMs': 35,
    'telemetryMs': 140,
  };
}

String formatCalibrationValue(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}
