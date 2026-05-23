import 'package:flutter/material.dart';

class ControlButton extends StatefulWidget {
  const ControlButton({
    super.key,
    required this.label,
    required this.onPressedChanged,
    this.color = const Color(0xFF2B3440),
  });

  final String label;
  final ValueChanged<bool> onPressedChanged;
  final Color color;

  @override
  State<ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<ControlButton> {
  final Set<int> _activePointers = {};

  bool get _pressed => _activePointers.isNotEmpty;

  void _setPointer(int pointer, bool active) {
    final wasPressed = _pressed;
    if (active) {
      _activePointers.add(pointer);
    } else {
      _activePointers.remove(pointer);
    }

    if (wasPressed != _pressed) {
      widget.onPressedChanged(_pressed);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _pressed ? Colors.black : Colors.white;
    final background = _pressed ? const Color(0xFFFFC857) : widget.color;

    return Semantics(
      button: true,
      label: widget.label,
      child: Listener(
        onPointerDown: (event) => _setPointer(event.pointer, true),
        onPointerUp: (event) => _setPointer(event.pointer, false),
        onPointerCancel: (event) => _setPointer(event.pointer, false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _pressed
                  ? const Color(0xFFFFE6A3)
                  : const Color(0xFF3D4652),
              width: 2,
            ),
            boxShadow: [
              if (_pressed)
                BoxShadow(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.28),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: foreground,
              fontSize: 52,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
