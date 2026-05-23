import 'package:flutter/material.dart';

import '../services/bluetooth_service.dart';

const ledOptions = [
  LedOption('Red', 'CRED', 0xFFFF4D5E),
  LedOption('Green', 'CGREEN', 0xFF55D66B),
  LedOption('Blue', 'CBLUE', 0xFF4C8DFF),
  LedOption('Pink', 'CPINK', 0xFFFF69C8),
  LedOption('Cyan', 'CCYAN', 0xFF33D2D2),
  LedOption('Yellow', 'CYELLOW', 0xFFFFD23F),
  LedOption('White', 'CWHITE', 0xFFFFFFFF),
  LedOption('Off', 'COFF', 0xFF7B8494),
  LedOption('Police mode', 'CPOLICE', 0xFFFF5C7A),
  LedOption('Rainbow mode', 'CRAINBOW', 0xFFA66CFF),
  LedOption('Random mode', 'CRANDOM', 0xFF33D2B2),
];

const modeOptions = [
  ModeOption('Manual Mode', 'MMANUAL'),
  ModeOption('Line Tracing Mode', 'MLINE'),
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bluetoothService,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    bluetoothService.isConnected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      color: bluetoothService.isConnected
                          ? const Color(0xFF33D2B2)
                          : const Color(0xFFFF5C7A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
              children: [
                _SettingsSection(
                  title: 'Speed',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Color(0xFFFFC857)),
                          const SizedBox(width: 10),
                          Text(
                            '${bluetoothService.speed}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: bluetoothService.speed.toDouble(),
                        min: 50,
                        max: 255,
                        divisions: 205,
                        label: '${bluetoothService.speed}',
                        onChanged: (value) {
                          bluetoothService.previewSpeed(value.round());
                        },
                        onChangeEnd: (value) {
                          bluetoothService.setSpeed(value.round());
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: 'RGB LED',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in ledOptions)
                        _CommandChoice(
                          label: option.label,
                          selected: bluetoothService.ledLabel == option.label,
                          color: Color(option.color),
                          onPressed: () => bluetoothService.setLed(option),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: 'Mode',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in modeOptions)
                        _CommandChoice(
                          label: option.label,
                          selected:
                              bluetoothService.modeLabel ==
                              option.label.replaceAll(' Mode', ''),
                          color: option.command == 'MMANUAL'
                              ? const Color(0xFF33D2B2)
                              : const Color(0xFF7CC7FF),
                          onPressed: () => bluetoothService.setMode(
                            ModeOption(
                              option.label.replaceAll(' Mode', ''),
                              option.command,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  bluetoothService.statusMessage,
                  style: const TextStyle(color: Color(0xFFB8C0CC)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF191F27),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF303946)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CommandChoice extends StatelessWidget {
  const _CommandChoice({
    required this.label,
    required this.selected,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(112, 48)),
        backgroundColor: WidgetStatePropertyAll(
          selected ? color : const Color(0xFF252D38),
        ),
        foregroundColor: WidgetStatePropertyAll(
          selected && color.computeLuminance() > 0.55
              ? Colors.black
              : Colors.white,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: selected ? color : const Color(0xFF3D4652)),
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
