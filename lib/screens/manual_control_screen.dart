import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/bluetooth_service.dart';
import '../services/movement_protocol.dart';
import '../widgets/arrow_control_button.dart';
import 'traversal_screen.dart';

const manualLedOptions = [
  LedOption('RED', 'CRED', 0xFFFF3131),
  LedOption('GREEN', 'CGREEN', 0xFF10C772),
  LedOption('BLUE', 'CBLUE', 0xFF2D7DFF),
  LedOption('PINK', 'CPINK', 0xFFFF69C8),
  LedOption('CYAN', 'CCYAN', 0xFF33D2D2),
  LedOption('YELLOW', 'CYELLOW', 0xFFFFE066),
  LedOption('WHITE', 'CWHITE', 0xFFFFFFFF),
  LedOption('POLICE', 'CPOLICE', 0xFFFF3131),
  LedOption('RAINBOW', 'CRAINBOW', 0xFFB967FF),
  LedOption('RANDOM', 'CRANDOM', 0xFFFF9F1C),
  LedOption('OFF', 'COFF', 0xFF888888),
];

class ManualControlScreen extends StatefulWidget {
  const ManualControlScreen({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  State<ManualControlScreen> createState() => _ManualControlScreenState();
}

class _ManualControlScreenState extends State<ManualControlScreen> {
  static const _minimumTapPulse = Duration(milliseconds: 160);
  static const _heartbeatInterval = Duration(milliseconds: 220);

  bool _upPressed = false;
  bool _downPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;
  bool _ledMenuOpen = false;
  bool _deviceMenuOpen = false;
  String _lastMovementCommand = 'S';
  Timer? _movementHeartbeat;
  Timer? _stopRepeatTimer;
  Timer? _deferredStopTimer;
  int _movementEpoch = 0;
  DateTime? _movementStartedAt;

  RobotBluetoothService get _bluetooth => widget.bluetoothService;

  @override
  void initState() {
    super.initState();
    _bluetooth.addListener(_handleBluetoothUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _bluetooth.isConnected) {
        _bluetooth.enterManualControlMode();
      }
    });
  }

  @override
  void dispose() {
    _bluetooth.removeListener(_handleBluetoothUpdate);
    _stopMovementHeartbeat();
    _stopRepeatTimer?.cancel();
    _deferredStopTimer?.cancel();
    _bluetooth.sendSafetyStop();
    super.dispose();
  }

  void _handleBluetoothUpdate() {
    if (_bluetooth.isConnected) {
      return;
    }

    if (!_upPressed && !_downPressed && !_leftPressed && !_rightPressed) {
      return;
    }

    _stopMovementHeartbeat();
    _stopRepeatTimer?.cancel();
    _deferredStopTimer?.cancel();
    _lastMovementCommand = 'S';

    if (mounted) {
      setState(() {
        _upPressed = false;
        _downPressed = false;
        _leftPressed = false;
        _rightPressed = false;
      });
    }
  }

  void _setDirection(String direction, bool pressed) {
    setState(() {
      switch (direction) {
        case 'up':
          _upPressed = pressed;
        case 'down':
          _downPressed = pressed;
        case 'left':
          _leftPressed = pressed;
        case 'right':
          _rightPressed = pressed;
      }
    });
    _sendMovementIfChanged();
  }

  String _computeMovementCommand() {
    return movementCommandFor(
      upPressed: _upPressed,
      downPressed: _downPressed,
      leftPressed: _leftPressed,
      rightPressed: _rightPressed,
    );
  }

  void _sendMovementIfChanged() {
    final command = _computeMovementCommand();
    if (command == _lastMovementCommand) {
      return;
    }

    _lastMovementCommand = command;
    if (command == 'S') {
      _updateMovementHeartbeat(command);
      _sendStopAfterMinimumPulse();
      return;
    } else {
      _stopRepeatTimer?.cancel();
      _deferredStopTimer?.cancel();
      _movementStartedAt = DateTime.now();
      _bluetooth.sendMovementCommand(command);
    }
    _updateMovementHeartbeat(command);
  }

  void _updateMovementHeartbeat(String command) {
    _stopMovementHeartbeat();
    _movementEpoch++;
    if (command == 'S') {
      return;
    }

    final epoch = _movementEpoch;
    _movementHeartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (epoch == _movementEpoch && _lastMovementCommand == command) {
        _bluetooth.sendRawCommand(command, force: true, dropIfQueued: true);
      }
    });
  }

  void _stopMovementHeartbeat() {
    _movementHeartbeat?.cancel();
    _movementHeartbeat = null;
  }

  void _repeatStopIfStillReleased() {
    _stopRepeatTimer?.cancel();
    _stopRepeatTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _computeMovementCommand() != 'S') {
        return;
      }
      _bluetooth.sendRawCommand('S', force: true);
    });
  }

  void _sendStopAfterMinimumPulse() {
    _deferredStopTimer?.cancel();

    final startedAt = _movementStartedAt;
    if (startedAt == null) {
      _sendStopNowAndRepeat();
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _minimumTapPulse - elapsed;
    if (remaining <= Duration.zero) {
      _sendStopNowAndRepeat();
      return;
    }

    _deferredStopTimer = Timer(remaining, () {
      if (!mounted || _computeMovementCommand() != 'S') {
        return;
      }
      _sendStopNowAndRepeat();
    });
  }

  void _sendStopNowAndRepeat() {
    _bluetooth.sendRawCommand('S', force: true);
    _repeatStopIfStillReleased();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _handleBluetoothTap() async {
    if (_bluetooth.isBusy) {
      return;
    }

    if (_bluetooth.isConnected) {
      setState(() {
        _deviceMenuOpen = !_deviceMenuOpen;
        _ledMenuOpen = false;
      });
      return;
    }

    await _bluetooth.refreshPairedDevices();
    if (!mounted) {
      return;
    }

    final device = _preferredBluetoothDevice();
    if (device != null) {
      setState(() {
        _deviceMenuOpen = false;
        _ledMenuOpen = false;
      });
      _showMessage('Connecting to ${device.name}');
      await _bluetooth.connectToDevice(device);
      if (mounted && !_bluetooth.isConnected) {
        setState(() {
          _deviceMenuOpen = true;
        });
      }
      return;
    }

    setState(() {
      _deviceMenuOpen = true;
      _ledMenuOpen = false;
    });
  }

  BluetoothDeviceInfo? _preferredBluetoothDevice() {
    final devices = _bluetooth.pairedDevices;
    if (devices.isEmpty) {
      return null;
    }

    final selected = _bluetooth.selectedDevice;
    if (selected != null) {
      for (final device in devices) {
        if (device.address == selected.address) {
          return device;
        }
      }
    }

    for (final device in devices) {
      final name = device.name.toLowerCase();
      if (name.contains('hc-05') ||
          name.contains('hc05') ||
          name.contains('zs-040')) {
        return device;
      }
    }

    if (devices.length == 1) {
      return devices.first;
    }

    return null;
  }

  Future<void> _selectDevice(BluetoothDeviceInfo device) async {
    setState(() {
      _deviceMenuOpen = false;
    });
    await _bluetooth.connectToDevice(device);
  }

  Future<void> _goTraversal() async {
    if (!_bluetooth.isConnected) {
      _showMessage('Connect HC-05 first');
      return;
    }

    await _bluetooth.sendCommandSequence(['S', 'LINE']);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TraversalScreen(bluetoothService: _bluetooth),
      ),
    );

    if (mounted && _bluetooth.isConnected) {
      await _bluetooth.enterManualControlMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bluetooth,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 46,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _PillButton(
                                  label: 'LED COLOR',
                                  icon: Icons.arrow_drop_down,
                                  compact: true,
                                  onPressed: () {
                                    setState(() {
                                      _ledMenuOpen = !_ledMenuOpen;
                                      _deviceMenuOpen = false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 14),
                                _PillButton(
                                  label: 'Traversal Mode',
                                  compact: true,
                                  onPressed: _goTraversal,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, mainConstraints) {
                                final leftColumnWidth =
                                    mainConstraints.maxWidth * 0.31;
                                final rightColumnWidth =
                                    mainConstraints.maxWidth * 0.41;
                                final buttonSize =
                                    [
                                          (mainConstraints.maxHeight - 28) / 2,
                                          leftColumnWidth,
                                          (rightColumnWidth - 46) / 2,
                                          220.0,
                                        ]
                                        .reduce(math.min)
                                        .clamp(96.0, 220.0)
                                        .toDouble();
                                final speedSliderHeight =
                                    (mainConstraints.maxHeight - 96)
                                        .clamp(150.0, 380.0)
                                        .toDouble();

                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 31,
                                      child: _VerticalArrows(
                                        size: buttonSize,
                                        enabled: _bluetooth.isConnected,
                                        upActive: _upPressed,
                                        downActive: _downPressed,
                                        onUp: (pressed) =>
                                            _setDirection('up', pressed),
                                        onDown: (pressed) =>
                                            _setDirection('down', pressed),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 28,
                                      child: _SpeedZone(
                                        speed: _bluetooth.speed,
                                        sliderHeight: speedSliderHeight,
                                        onPreview: _bluetooth.previewSpeed,
                                        onCommit: _bluetooth.setSpeed,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 41,
                                      child: _HorizontalArrows(
                                        size: buttonSize,
                                        enabled: _bluetooth.isConnected,
                                        leftActive: _leftPressed,
                                        rightActive: _rightPressed,
                                        onLeft: (pressed) =>
                                            _setDirection('left', pressed),
                                        onRight: (pressed) =>
                                            _setDirection('right', pressed),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 62,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PillButton(
                                  label: 'HC-05',
                                  icon: Icons.bluetooth,
                                  green: _bluetooth.isConnected,
                                  onPressed: _handleBluetoothTap,
                                ),
                                const SizedBox(width: 28),
                                _StatusPill(connected: _bluetooth.isConnected),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_ledMenuOpen)
                      Positioned(
                        top: 56,
                        right: 260,
                        child: _LedMenu(
                          onSelect: (option) {
                            setState(() {
                              _ledMenuOpen = false;
                            });
                            _bluetooth.setLed(option);
                          },
                        ),
                      ),
                    if (_deviceMenuOpen)
                      Positioned(
                        bottom: 92,
                        left: constraints.maxWidth / 2 - 145,
                        child: _DeviceMenu(
                          devices: _bluetooth.pairedDevices,
                          connected: _bluetooth.isConnected,
                          busy: _bluetooth.isBusy,
                          onSelect: _selectDevice,
                          onDisconnect: () async {
                            setState(() {
                              _deviceMenuOpen = false;
                            });
                            await _bluetooth.disconnect();
                          },
                        ),
                      ),
                    Positioned(
                      right: 18,
                      bottom: 8,
                      width: 230,
                      height: 104,
                      child: _ManualCommandMonitor(
                        lines: _bluetooth.manualCommandLogs,
                        onClear: _bluetooth.clearManualCommandLogs,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ManualCommandMonitor extends StatelessWidget {
  const _ManualCommandMonitor({required this.lines, required this.onClear});

  final List<String> lines;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final visibleLines = lines.length > 5
        ? lines.sublist(lines.length - 5)
        : lines;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6050505),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B2B2B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'MONITOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    'CLEAR',
                    style: TextStyle(
                      color: Color(0xFFFF3131),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                visibleLines.isEmpty
                    ? 'No commands yet'
                    : visibleLines.join('\n'),
                style: const TextStyle(
                  color: Color(0xFFDBEAFE),
                  fontSize: 8,
                  height: 1.15,
                  fontFamily: 'FiraCode',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalArrows extends StatelessWidget {
  const _VerticalArrows({
    required this.size,
    required this.enabled,
    required this.upActive,
    required this.downActive,
    required this.onUp,
    required this.onDown,
  });

  final double size;
  final bool enabled;
  final bool upActive;
  final bool downActive;
  final ValueChanged<bool> onUp;
  final ValueChanged<bool> onDown;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: ArrowControlButton(
                direction: ArrowDirection.up,
                active: upActive,
                disabled: !enabled,
                onPressedChanged: onUp,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: size,
              height: size,
              child: ArrowControlButton(
                direction: ArrowDirection.down,
                active: downActive,
                disabled: !enabled,
                onPressedChanged: onDown,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalArrows extends StatelessWidget {
  const _HorizontalArrows({
    required this.size,
    required this.enabled,
    required this.leftActive,
    required this.rightActive,
    required this.onLeft,
    required this.onRight,
  });

  final double size;
  final bool enabled;
  final bool leftActive;
  final bool rightActive;
  final ValueChanged<bool> onLeft;
  final ValueChanged<bool> onRight;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: ArrowControlButton(
                direction: ArrowDirection.left,
                active: leftActive,
                disabled: !enabled,
                onPressedChanged: onLeft,
              ),
            ),
            const SizedBox(width: 46),
            SizedBox(
              width: size,
              height: size,
              child: ArrowControlButton(
                direction: ArrowDirection.right,
                active: rightActive,
                disabled: !enabled,
                onPressedChanged: onRight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedZone extends StatelessWidget {
  const _SpeedZone({
    required this.speed,
    required this.sliderHeight,
    required this.onPreview,
    required this.onCommit,
  });

  final int speed;
  final double sliderHeight;
  final ValueChanged<int> onPreview;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Speed: $speed',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: sliderHeight,
              width: 70,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF555555),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.18),
                  ),
                  child: Slider(
                    value: speed.toDouble(),
                    min: 90,
                    max: 255,
                    divisions: 165,
                    label: '$speed',
                    onChanged: (value) => onPreview(value.round()),
                    onChangeEnd: (value) => onCommit(value.round()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.green = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool green;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: green ? const Color(0xFF10C772) : Colors.white,
        foregroundColor: green ? Colors.white : Colors.black,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.black.withValues(alpha: 0.45),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 6 : 8,
        ),
        minimumSize: Size(0, compact ? 36 : 42),
        shape: StadiumBorder(
          side: BorderSide(
            color: const Color(0xFFD9D9D9),
            width: compact ? 3 : 5,
          ),
        ),
        textStyle: TextStyle(
          fontSize: compact ? 15 : 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 24), const SizedBox(width: 8)],
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF10C772) : const Color(0xFFFF3131);
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 5),
      ),
      child: Text(
        connected ? 'CONNECTED' : 'DISCONNECTED',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LedMenu extends StatefulWidget {
  const _LedMenu({required this.onSelect});

  final ValueChanged<LedOption> onSelect;

  @override
  State<_LedMenu> createState() => _LedMenuState();
}

class _LedMenuState extends State<_LedMenu> {
  Timer? _animationTimer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 260), (_) {
      if (mounted) {
        setState(() {
          _tick++;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PopupPanel(
      width: 190,
      maxHeight: MediaQuery.sizeOf(context).height - 72,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in manualLedOptions)
              _LedOptionButton(
                option: option,
                tick: _tick,
                onPressed: () => widget.onSelect(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _LedOptionButton extends StatelessWidget {
  const _LedOptionButton({
    required this.option,
    required this.tick,
    required this.onPressed,
  });

  static const _rainbowColors = [
    Color(0xFFFF3131),
    Color(0xFFFFE066),
    Color(0xFF10C772),
    Color(0xFF33D2D2),
    Color(0xFF2D7DFF),
    Color(0xFFFF69C8),
  ];

  final LedOption option;
  final int tick;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = option.label;
    final background = _backgroundColor(label);
    final gradient = _gradient(label);
    final foreground = _foregroundColor(background, label);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: gradient == null ? background : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: label == 'WHITE'
                ? const Color(0xFFB7B7B7)
                : Colors.black.withValues(alpha: 0.18),
            width: label == 'WHITE' ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    shadows: label == 'RAINBOW' || label == 'RANDOM'
                        ? const [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(String label) {
    return switch (label) {
      'POLICE' =>
        tick.isEven ? const Color(0xFFFF3131) : const Color(0xFF2D7DFF),
      'OFF' => const Color(0xFF2F2F2F),
      _ => Color(option.color),
    };
  }

  Gradient? _gradient(String label) {
    if (label != 'RAINBOW' && label != 'RANDOM') {
      return null;
    }

    final colors = List<Color>.generate(
      _rainbowColors.length,
      (index) => _rainbowColors[(index + tick) % _rainbowColors.length],
    );

    if (label == 'RANDOM') {
      return LinearGradient(
        colors: [colors[0], colors[3], colors[5], colors[2]],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return LinearGradient(colors: colors);
  }

  Color _foregroundColor(Color background, String label) {
    if (label == 'RAINBOW' || label == 'RANDOM' || label == 'OFF') {
      return Colors.white;
    }
    return background.computeLuminance() > 0.58 ? Colors.black : Colors.white;
  }
}

class _DeviceMenu extends StatelessWidget {
  const _DeviceMenu({
    required this.devices,
    required this.connected,
    required this.busy,
    required this.onSelect,
    required this.onDisconnect,
  });

  final List<BluetoothDeviceInfo> devices;
  final bool connected;
  final bool busy;
  final ValueChanged<BluetoothDeviceInfo> onSelect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return _PopupPanel(
      width: 290,
      maxHeight: MediaQuery.sizeOf(context).height - 120,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              )
            else if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No paired Bluetooth devices found.',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a device to connect',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              for (final device in devices)
                _MenuButton(
                  label: 'Connect ${device.name}',
                  subtitle: device.address,
                  onPressed: () => onSelect(device),
                ),
            ],
            if (connected)
              _MenuButton(
                label: 'Disconnect',
                subtitle: 'send stop and close socket',
                danger: true,
                onPressed: onDisconnect,
              ),
          ],
        ),
      ),
    );
  }
}

class _PopupPanel extends StatelessWidget {
  const _PopupPanel({required this.width, required this.child, this.maxHeight});

  final double width;
  final Widget child;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9D9D9), width: 4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.danger = false,
  });

  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFF0F0F0),
          foregroundColor: danger ? const Color(0xFFDC2626) : Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
