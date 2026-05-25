import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bluetooth_service.dart';
import '../services/movement_protocol.dart';
import '../widgets/control_button.dart';
import 'settings_screen.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen>
    with WidgetsBindingObserver {
  bool upPressed = false;
  bool downPressed = false;
  bool leftPressed = false;
  bool rightPressed = false;
  String _lastMovementCommand = 'S';
  Timer? _movementHeartbeat;

  RobotBluetoothService get _bluetooth => widget.bluetoothService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopMovementHeartbeat();
    _bluetooth.sendRawCommand('S', force: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _releaseAll(send: false);
      _lastMovementCommand = 'S';
      _stopMovementHeartbeat();
      _bluetooth.sendRawCommand('S', force: true);
    }
  }

  void _setDirection(String direction, bool pressed) {
    setState(() {
      switch (direction) {
        case 'up':
          upPressed = pressed;
        case 'down':
          downPressed = pressed;
        case 'left':
          leftPressed = pressed;
        case 'right':
          rightPressed = pressed;
      }
    });
    _sendMovementIfChanged();
  }

  void _releaseAll({bool send = true}) {
    setState(() {
      upPressed = false;
      downPressed = false;
      leftPressed = false;
      rightPressed = false;
    });
    if (send) {
      _sendMovementIfChanged();
    }
  }

  String _computeMovementCommand() {
    return movementCommandFor(
      upPressed: upPressed,
      downPressed: downPressed,
      leftPressed: leftPressed,
      rightPressed: rightPressed,
    );
  }

  void _sendMovementIfChanged() {
    final command = _computeMovementCommand();
    if (command == _lastMovementCommand) {
      return;
    }
    _lastMovementCommand = command;
    _bluetooth.sendMovementCommand(command);
    _updateMovementHeartbeat(command);
  }

  void _updateMovementHeartbeat(String command) {
    _stopMovementHeartbeat();
    if (command == 'S') {
      return;
    }

    _movementHeartbeat = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _bluetooth.sendRawCommand(command, force: true);
    });
  }

  void _stopMovementHeartbeat() {
    _movementHeartbeat?.cancel();
    _movementHeartbeat = null;
  }

  Future<void> _openDevicePicker() async {
    await _bluetooth.refreshPairedDevices();
    if (!mounted) {
      return;
    }

    final selected = await showDialog<BluetoothDeviceInfo>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paired Bluetooth Devices'),
          content: SizedBox(
            width: 460,
            child: _bluetooth.pairedDevices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No paired Bluetooth devices found.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _bluetooth.pairedDevices.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = _bluetooth.pairedDevices[index];
                      final selected =
                          device.address == _bluetooth.selectedDevice?.address;
                      return ListTile(
                        selected: selected,
                        title: Text(device.name),
                        subtitle: Text(device.address),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      await _bluetooth.selectDevice(selected);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(bluetoothService: _bluetooth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bluetooth,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final buttonSize = ((constraints.maxHeight - 72) / 2)
                    .clamp(96.0, 154.0)
                    .toDouble();

                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      SizedBox(
                        width: buttonSize,
                        child: _VerticalControls(
                          buttonSize: buttonSize,
                          onUp: (pressed) => _setDirection('up', pressed),
                          onDown: (pressed) => _setDirection('down', pressed),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _CenterPanel(
                          bluetooth: _bluetooth,
                          lastMovementCommand: _lastMovementCommand,
                          onPickDevice: _openDevicePicker,
                          onConnect: _bluetooth.connect,
                          onDisconnect: () => _bluetooth.disconnect(),
                          onOpenSettings: _openSettings,
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: buttonSize * 2 + 16,
                        child: _HorizontalControls(
                          buttonSize: buttonSize,
                          onLeft: (pressed) => _setDirection('left', pressed),
                          onRight: (pressed) => _setDirection('right', pressed),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _VerticalControls extends StatelessWidget {
  const _VerticalControls({
    required this.buttonSize,
    required this.onUp,
    required this.onDown,
  });

  final double buttonSize;
  final ValueChanged<bool> onUp;
  final ValueChanged<bool> onDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: ControlButton(label: '↑', onPressedChanged: onUp),
        ),
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: ControlButton(label: '↓', onPressedChanged: onDown),
        ),
      ],
    );
  }
}

class _HorizontalControls extends StatelessWidget {
  const _HorizontalControls({
    required this.buttonSize,
    required this.onLeft,
    required this.onRight,
  });

  final double buttonSize;
  final ValueChanged<bool> onLeft;
  final ValueChanged<bool> onRight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: ControlButton(label: '←', onPressedChanged: onLeft),
        ),
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: ControlButton(label: '→', onPressedChanged: onRight),
        ),
      ],
    );
  }
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({
    required this.bluetooth,
    required this.lastMovementCommand,
    required this.onPickDevice,
    required this.onConnect,
    required this.onDisconnect,
    required this.onOpenSettings,
  });

  final RobotBluetoothService bluetooth;
  final String lastMovementCommand;
  final VoidCallback onPickDevice;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final selectedDeviceName = bluetooth.selectedDevice?.name ?? 'None';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191F27),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF303946)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Robot Controller',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusPill(connected: bluetooth.isConnected),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.bluetooth,
                label: selectedDeviceName,
                color: const Color(0xFF33D2B2),
              ),
              _InfoChip(
                icon: Icons.speed,
                label: 'Speed ${bluetooth.speed}',
                color: const Color(0xFFFFC857),
              ),
              _InfoChip(
                icon: Icons.light_mode,
                label: bluetooth.ledLabel,
                color: const Color(0xFFFF5C7A),
              ),
              _InfoChip(
                icon: Icons.route,
                label: bluetooth.modeLabel,
                color: const Color(0xFF7CC7FF),
              ),
              _InfoChip(
                icon: Icons.gamepad,
                label: 'Cmd $lastMovementCommand',
                color: const Color(0xFFA6E36A),
              ),
            ],
          ),
          Text(
            bluetooth.statusMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB8C0CC)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PanelActionButton(
                icon: Icons.devices,
                label: 'Device',
                onPressed: bluetooth.isBusy ? null : onPickDevice,
              ),
              _PanelActionButton(
                icon: Icons.link,
                label: 'Connect',
                onPressed:
                    bluetooth.selectedDevice == null ||
                        bluetooth.isConnected ||
                        bluetooth.isBusy
                    ? null
                    : onConnect,
              ),
              _PanelActionButton(
                icon: Icons.link_off,
                label: 'Disconnect',
                outlined: true,
                onPressed: bluetooth.isConnected && !bluetooth.isBusy
                    ? onDisconnect
                    : null,
              ),
              IconButton.filledTonal(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  const _PanelActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    if (outlined) {
      return SizedBox(
        width: 128,
        child: OutlinedButton(onPressed: onPressed, child: child),
      );
    }

    return SizedBox(
      width: 112,
      child: FilledButton(onPressed: onPressed, child: child),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF33D2B2) : const Color(0xFFFF5C7A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        connected ? 'Connected' : 'Disconnected',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
