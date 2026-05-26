import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calibration.dart';
import '../models/robot_graph.dart';
import '../models/route_planner.dart';
import '../services/bluetooth_service.dart';
import '../widgets/node_map.dart';

class TraversalScreen extends StatefulWidget {
  const TraversalScreen({super.key, required this.bluetoothService});

  final RobotBluetoothService bluetoothService;

  @override
  State<TraversalScreen> createState() => _TraversalScreenState();
}

class _CalibrationUndo {
  const _CalibrationUndo({required this.item, required this.previousValue});

  final CalibrationItem item;
  final double previousValue;
}

enum _RouteSetupMode { showcase, manual }

enum _ShowcaseRouteType { shortest, longest }

class _TraversalScreenState extends State<TraversalScreen>
    with SingleTickerProviderStateMixin {
  static const _calibrationPrefsPrefix = 'traversal_calibration.';
  static const _calibrationCommandGap = Duration(milliseconds: 55);
  static const Map<String, List<String>> _calibrationGroups = {
    'Drive': [
      'baseSpeed',
      'slowSpeed',
      'turnSpeed',
      'shallowTurnSpeed',
      'catchTurnSpeed',
      'minPivot',
      'minPwm',
      'manualCurve',
    ],
    'Node': [
      'nodePause',
      'nodeForward',
      'minTurn',
      'shallowMinTurn',
      'stableMs',
      'afterTurn',
      'turnTimeout',
      'nodeCooldown',
      'finalForward',
    ],
    'Sensors': [
      'threshold',
      'kp',
      'leftTrim',
      'rightTrim',
      'nodeBlackMin',
      'lineBlackMax',
      'lostMs',
      'telemetryMs',
    ],
  };

  final TransformationController _mapController = TransformationController();

  late final AnimationController _robotSlideController;
  late final Map<String, double> _calibration;
  late final Map<String, double> _savedCalibration;

  _RouteSetupMode _routeMode = _RouteSetupMode.showcase;
  _ShowcaseRouteType _showcaseRouteType = _ShowcaseRouteType.shortest;
  GraphEdge? _selectedEdge;
  List<int>? _direction;
  int? _destination;
  List<int> _currentPath = [];
  List<String> _commands = [];
  String? _finishAction;
  bool _running = false;
  bool _calibrationOpen = false;
  String _calibrationGroup = 'Drive';
  bool _mapFitted = false;
  bool _showRawSensorValues = true;
  final Set<String> _pendingCalibrationKeys = <String>{};
  _CalibrationUndo? _lastCalibrationUndo;

  Offset? _robotPosition;
  Offset? _slideStart;
  Offset? _slideTarget;
  double _robotAngle = 0;
  bool _robotVisible = false;
  bool _robotBlinkRed = false;
  Timer? _blinkTimer;
  Timer? _blinkStopTimer;
  Timer? _sensorModeTimer;
  Timer? _telemetryWatchdogTimer;
  DateTime? _lastTelemetrySyncAt;
  int? _currentNode;
  int _lastNodeEventId = 0;
  int _lastSensorPacketEventId = 0;

  RobotBluetoothService get _bluetooth => widget.bluetoothService;

  @override
  void initState() {
    super.initState();
    _calibration = defaultCalibrationValues();
    _savedCalibration = Map<String, double>.from(_calibration);
    unawaited(_loadSavedCalibration());

    _robotSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addListener(_updateRobotSlide);

    _lastNodeEventId = _bluetooth.telemetry.nodeEventId;
    _lastSensorPacketEventId = _bluetooth.telemetry.sensorPacketEventId;
    _bluetooth.addListener(_handleBluetoothUpdate);
    _sensorModeTimer = Timer(const Duration(milliseconds: 120), () async {
      await _syncTelemetryMode(
        requestSample: true,
        ensureLineMode: true,
        includeRate: true,
      );
    });
    _telemetryWatchdogTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _watchTelemetryStream(),
    );
  }

  @override
  void dispose() {
    _bluetooth.removeListener(_handleBluetoothUpdate);
    _robotSlideController.dispose();
    _blinkTimer?.cancel();
    _blinkStopTimer?.cancel();
    _sensorModeTimer?.cancel();
    _telemetryWatchdogTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  String get _telemetryModeCommand => 'TEL:RAW';

  Future<void> _syncTelemetryMode({
    bool requestSample = false,
    bool ensureLineMode = false,
    bool includeRate = false,
  }) async {
    if (!mounted || !_bluetooth.isConnected) {
      return;
    }

    await _bluetooth.sendCommandSequence([
      if (ensureLineMode) 'PING',
      if (ensureLineMode) 'LINE',
      if (includeRate)
        'CFG:TELMS=${formatCalibrationValue(_calibration['telemetryMs'] ?? RobotBluetoothService.traversalTelemetryIntervalMs.toDouble())}',
      _telemetryModeCommand,
      if (requestSample) 'GETSENS',
    ]);
  }

  Future<void> _requestTelemetryResync({
    bool requestSample = false,
    bool ensureLineMode = false,
    bool includeRate = false,
  }) async {
    final now = DateTime.now();
    final last = _lastTelemetrySyncAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }

    _lastTelemetrySyncAt = now;
    await _syncTelemetryMode(
      requestSample: requestSample,
      ensureLineMode: ensureLineMode,
      includeRate: includeRate,
    );
  }

  void _watchTelemetryStream() {
    if (!mounted || !_bluetooth.isConnected) {
      return;
    }

    final lastPacketAt = _bluetooth.telemetry.lastSensorPacketAt;
    final streamStale =
        lastPacketAt == null ||
        DateTime.now().difference(lastPacketAt) >
            const Duration(milliseconds: 850);
    final rawModeOutOfSync =
        _showRawSensorValues && !_bluetooth.telemetry.hasRawValues;

    if (streamStale) {
      _bluetooth.logNativeDebugStatus();
      _requestTelemetryResync(
        requestSample: true,
        ensureLineMode: !_running,
        includeRate: true,
      );
    } else if (rawModeOutOfSync) {
      _requestTelemetryResync(requestSample: true);
    }
  }

  void _handleBluetoothUpdate() {
    final telemetry = _bluetooth.telemetry;
    final threshold = telemetry.threshold.toDouble();

    if (_pendingCalibrationKeys.contains('threshold') &&
        _calibration['threshold'] == threshold) {
      _pendingCalibrationKeys.remove('threshold');
    }

    if (telemetry.nodeEventId != _lastNodeEventId && telemetry.node != null) {
      _lastNodeEventId = telemetry.nodeEventId;
      _onNodeConfirmed(telemetry.node!);
      return;
    }

    if (telemetry.state == 'FINISHED' && _running) {
      _running = false;
    }

    if (telemetry.sensorPacketEventId != _lastSensorPacketEventId) {
      _lastSensorPacketEventId = telemetry.sensorPacketEventId;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _updateRobotSlide() {
    final start = _slideStart;
    final target = _slideTarget;
    if (start == null || target == null) {
      return;
    }

    final t = Curves.easeInOut.transform(_robotSlideController.value);
    setState(() {
      _robotPosition = Offset.lerp(start, target, t);
    });
  }

  void _onNodeConfirmed(int node) {
    final target = graphNodes[node];
    if (target == null) {
      return;
    }

    final previousNode = _currentNode;
    final start = _robotPosition ?? target;
    final angle = previousNode != null && previousNode != node
        ? angleBetweenNodes(previousNode, node)
        : _robotAngle;

    setState(() {
      _currentNode = node;
      _robotVisible = true;
      _robotAngle = angle;
      _slideStart = start;
      _slideTarget = target;
    });

    _startRobotBlink();
    _robotSlideController.forward(from: 0);
  }

  void _startRobotBlink() {
    _blinkTimer?.cancel();
    _blinkStopTimer?.cancel();
    setState(() {
      _robotBlinkRed = true;
    });

    _blinkTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _robotBlinkRed = !_robotBlinkRed;
      });
    });

    _blinkStopTimer = Timer(const Duration(milliseconds: 760), () {
      _blinkTimer?.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _robotBlinkRed = false;
      });
    });
  }

  void _fitMap(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return;
    }

    final scale = math.max(
      0.22,
      math.min(
        1.15,
        math.max(
              viewport.width / graphSize.width,
              viewport.height / graphSize.height,
            ) *
            0.98,
      ),
    );
    final dx = (viewport.width - graphSize.width * scale) / 2;
    final dy = (viewport.height - graphSize.height * scale) / 2;
    _mapController.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(dx, dy, 0);
  }

  void _zoom(double factor) {
    final current = _mapController.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.22, 4.0).toDouble();
    _mapController.value = Matrix4.diagonal3Values(next, next, 1);
  }

  void _selectEdge(GraphEdge edge) {
    if (_running) {
      _showMessage('Stop traversal first');
      return;
    }

    setState(() {
      _routeMode = _RouteSetupMode.manual;
      _selectedEdge = edge;
      _direction = null;
      _currentPath = [];
      _commands = [];
      _finishAction = null;
    });
  }

  void _selectDestination(int node) {
    if (_running) {
      _showMessage('Stop traversal first');
      return;
    }

    setState(() {
      _routeMode = _RouteSetupMode.manual;
      _destination = node;
      _currentPath = [];
      _commands = [];
      _finishAction = null;
    });
  }

  void _clearRouteSelection() {
    if (_running) {
      _stopTraversal();
    }

    setState(() {
      _selectedEdge = null;
      _direction = null;
      _destination = null;
      _currentPath = [];
      _commands = [];
      _finishAction = null;
      _robotVisible = false;
      _robotPosition = null;
      _currentNode = null;
    });
  }

  void _setRouteMode(_RouteSetupMode mode) {
    if (_running) {
      _showMessage('Stop traversal first');
      return;
    }

    setState(() {
      _routeMode = mode;
      _currentPath = [];
      _commands = [];
      _finishAction = null;
      _robotVisible = false;
      _robotPosition = null;
      _currentNode = null;
    });
  }

  void _setShowcaseRouteType(_ShowcaseRouteType type) {
    if (_running) {
      _showMessage('Stop traversal first');
      return;
    }

    setState(() {
      _showcaseRouteType = type;
      _currentPath = [];
      _commands = [];
      _finishAction = null;
    });
  }

  void _calculateRoute() {
    final RoutePlan plan;
    final int previousNode;
    final int startNode;
    if (_routeMode == _RouteSetupMode.showcase) {
      previousNode = startGuideNode;
      startNode = showcaseStartNode;
      plan = RoutePlanner.calculate(
        previousNode: previousNode,
        startNode: startNode,
        destinationNode: showcaseFinishNode,
        preferLongest: _showcaseRouteType == _ShowcaseRouteType.longest,
        finishExit: true,
      );
    } else {
      final direction = _direction;
      final destination = _destination;
      if (direction == null || destination == null) {
        _showMessage('Select edge direction and destination first');
        return;
      }

      previousNode = direction[0];
      startNode = direction[1];
      plan = RoutePlanner.calculate(
        previousNode: previousNode,
        startNode: startNode,
        destinationNode: destination,
      );
    }

    if (!plan.isValid) {
      _showMessage('No path found');
      return;
    }

    final start = graphNodes[startNode]!;
    setState(() {
      _currentPath = plan.path;
      _commands = plan.commands;
      _finishAction = plan.finishAction;
      _robotPosition = start;
      _robotAngle = angleBetweenNodes(previousNode, startNode);
      _robotVisible = true;
      _currentNode = null;
    });
  }

  Future<void> _confirmAndStart() async {
    if (!_confirmEnabled) {
      return;
    }

    setState(() {
      _running = true;
    });

    await _bluetooth.sendCommandSequence(['S', 'LINE']);
    await _sendCalibrationProfile();
    await _bluetooth.sendCommandSequence([
      'FINISH:${_finishAction ?? 'OFF'}',
      'PATH:${_currentPath.join(',')}',
      'ROUTE:${_commands.join()}',
      'START',
    ]);
    await _syncTelemetryMode(requestSample: true, includeRate: true);
  }

  Future<void> _stopTraversal() async {
    await _bluetooth.sendCommandSequence(['S', 'MANUAL', 'CBLUE']);
    if (!mounted) {
      return;
    }

    setState(() {
      _running = false;
      _robotBlinkRed = false;
    });
    _blinkTimer?.cancel();
    _blinkStopTimer?.cancel();
  }

  Future<void> _backToManual() async {
    await _stopTraversal();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  bool get _routeValid {
    return _currentPath.isNotEmpty &&
        _commands.isNotEmpty &&
        _commands.every(RoutePlanner.validRouteCommands.contains) &&
        (_finishAction == null ||
            RoutePlanner.validRouteCommands.contains(_finishAction));
  }

  bool get _confirmEnabled {
    return _bluetooth.isConnected && _routeValid && !_running;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  void _setDirectionForward(bool forward) {
    final edge = _selectedEdge;
    if (edge == null) {
      return;
    }

    setState(() {
      _direction = forward ? [edge.a, edge.b] : [edge.b, edge.a];
      _currentPath = [];
      _commands = [];
      _finishAction = null;
    });
  }

  void _setCalibrationValue(String key, double value, {bool send = false}) {
    final item = calibrationItems.firstWhere((entry) => entry.key == key);
    final clamped = value.clamp(item.min, item.max).toDouble();
    final previousSaved =
        _savedCalibration[key] ?? _calibration[key] ?? item.min;

    setState(() {
      _calibration[key] = clamped;
      if (send && previousSaved != clamped) {
        _lastCalibrationUndo = _CalibrationUndo(
          item: item,
          previousValue: previousSaved,
        );
      }
    });

    if (send) {
      _savedCalibration[key] = clamped;
      unawaited(_saveCalibrationValue(item, clamped));
      _pendingCalibrationKeys.add(item.key);
      _sendCalibrationValue(item);
    }
  }

  void _undoCalibrationChange() {
    final undo = _lastCalibrationUndo;
    if (undo == null) {
      return;
    }

    setState(() {
      _calibration[undo.item.key] = undo.previousValue;
      _savedCalibration[undo.item.key] = undo.previousValue;
      _lastCalibrationUndo = null;
    });

    unawaited(_saveCalibrationValue(undo.item, undo.previousValue));
    _pendingCalibrationKeys.add(undo.item.key);
    _sendCalibrationValue(undo.item);
  }

  Future<void> _loadSavedCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValues = defaultCalibrationValues();

    for (final item in calibrationItems) {
      final saved = prefs.getDouble('$_calibrationPrefsPrefix${item.key}');
      if (saved != null) {
        savedValues[item.key] = saved.clamp(item.min, item.max).toDouble();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _calibration
        ..clear()
        ..addAll(savedValues);
      _savedCalibration
        ..clear()
        ..addAll(savedValues);
    });

    if (_bluetooth.isConnected) {
      await _sendCalibrationProfile();
    }
  }

  Future<void> _saveCalibrationValue(CalibrationItem item, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_calibrationPrefsPrefix${item.key}', value);
  }

  List<String> _calibrationCommands() {
    return [
      for (final item in calibrationItems)
        'CFG:${item.command}=${formatCalibrationValue(_calibration[item.key] ?? item.min)}',
    ];
  }

  Future<void> _sendCalibrationProfile() {
    if (!_bluetooth.isConnected) {
      return Future<void>.value();
    }
    return _bluetooth.sendCommandSequence(
      _calibrationCommands(),
      gap: _calibrationCommandGap,
    );
  }

  void _sendCalibrationValue(CalibrationItem item) {
    final value = _calibration[item.key] ?? item.min;
    _bluetooth.sendRawCommand(
      'CFG:${item.command}=${formatCalibrationValue(value)}',
      force: true,
    );
  }

  List<CalibrationItem> get _visibleCalibrationItems {
    final keys = _calibrationGroups[_calibrationGroup] ?? const <String>[];
    return [
      for (final item in calibrationItems)
        if (keys.contains(item.key)) item,
    ];
  }

  void _setRawSensorValuesEnabled(bool enabled) {
    setState(() {
      _showRawSensorValues = enabled;
    });
    _syncTelemetryMode(requestSample: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _stopTraversal();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _TraversalTopBar(
                        bluetooth: _bluetooth,
                        showRawSensorValues: _showRawSensorValues,
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _buildMapCard()),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                SizedBox(width: 342, child: _buildControlCard()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return _BorderCard(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Container(
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (!_mapFitted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _fitMap(constraints.biggest);
                          _mapFitted = true;
                        }
                      });
                    }

                    return NodeMap(
                      transformationController: _mapController,
                      selectedEdge: _selectedEdge,
                      direction: _routeMode == _RouteSetupMode.showcase
                          ? const [startGuideNode, showcaseStartNode]
                          : _direction,
                      destination: _routeMode == _RouteSetupMode.showcase
                          ? showcaseFinishNode
                          : _destination,
                      path: _currentPath,
                      currentNode: _currentNode,
                      robotPosition: _robotPosition,
                      robotAngle: _robotAngle,
                      robotVisible: _robotVisible,
                      robotBlinkRed: _robotBlinkRed,
                      onEdgeSelected: _selectEdge,
                      onNodeSelected: _selectDestination,
                    );
                  },
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Row(
                  children: [
                    _MapCircleButton(
                      icon: Icons.remove,
                      onPressed: () => _zoom(1 / 1.18),
                    ),
                    const SizedBox(width: 8),
                    _MapCircleButton(
                      icon: Icons.refresh,
                      onPressed: () {
                        _mapFitted = false;
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _MapCircleButton(
                      icon: Icons.add,
                      onPressed: () => _zoom(1.18),
                    ),
                    const SizedBox(width: 8),
                    _MapCircleButton(
                      icon: Icons.close,
                      danger: true,
                      onPressed: _clearRouteSelection,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteModeSection() {
    return _PanelSection(
      title: 'Route Mode',
      children: [
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: 'SHOWCASE',
                green: _routeMode == _RouteSetupMode.showcase,
                onPressed: () => _setRouteMode(_RouteSetupMode.showcase),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                label: 'MANUAL',
                green: _routeMode == _RouteSetupMode.manual,
                onPressed: () => _setRouteMode(_RouteSetupMode.manual),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShowcaseSelectionSection() {
    return _PanelSection(
      title: 'Showcase Route',
      children: [
        const _KeyValue(label: 'Start', value: 'START -> 1'),
        const _KeyValue(label: 'Finish', value: '21 -> FINISH'),
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: 'SHORTEST',
                green: _showcaseRouteType == _ShowcaseRouteType.shortest,
                onPressed: () =>
                    _setShowcaseRouteType(_ShowcaseRouteType.shortest),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                label: 'LONGEST',
                green: _showcaseRouteType == _ShowcaseRouteType.longest,
                onPressed: () =>
                    _setShowcaseRouteType(_ShowcaseRouteType.longest),
              ),
            ),
          ],
        ),
        _MiniButton(
          label: 'CALCULATE ROUTE',
          green: true,
          onPressed: _calculateRoute,
        ),
      ],
    );
  }

  Widget _buildManualSelectionSection() {
    return _PanelSection(
      title: 'Manual Placement',
      children: [
        _KeyValue(
          label: 'Start edge',
          value: _selectedEdge == null
              ? 'None'
              : '${_selectedEdge!.a} - ${_selectedEdge!.b}',
        ),
        _KeyValue(
          label: 'Facing into',
          value: _direction == null
              ? 'None'
              : '${_direction![0]} -> ${_direction![1]}',
        ),
        _KeyValue(
          label: 'Destination',
          value: _destination?.toString() ?? 'None',
        ),
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                label: _selectedEdge == null
                    ? 'A -> B'
                    : '${_selectedEdge!.a} -> ${_selectedEdge!.b}',
                onPressed: _selectedEdge == null
                    ? null
                    : () => _setDirectionForward(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                label: _selectedEdge == null
                    ? 'B -> A'
                    : '${_selectedEdge!.b} -> ${_selectedEdge!.a}',
                onPressed: _selectedEdge == null
                    ? null
                    : () => _setDirectionForward(false),
              ),
            ),
          ],
        ),
        _MiniButton(
          label: 'CALCULATE ROUTE',
          green: true,
          onPressed: _calculateRoute,
        ),
      ],
    );
  }

  Widget _buildControlCard() {
    return _BorderCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TRAVERSAL MODE',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 94,
                    child: _MiniButton(
                      label: 'MANUAL',
                      onPressed: _backToManual,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TelemetrySnapshot(
                bluetooth: _bluetooth,
                showRawSensorValues: _showRawSensorValues,
              ),
              const SizedBox(height: 12),
              _PanelSection(
                title: 'Sensor Telemetry',
                children: [
                  _ToggleRow(
                    label: 'Show raw values',
                    value: _showRawSensorValues,
                    onChanged: _setRawSensorValuesEnabled,
                  ),
                  const _HintLine(
                    text:
                        'Telemetry packets stay enabled; this only hides numbers in the top strip.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildRouteModeSection(),
              const SizedBox(height: 12),
              _routeMode == _RouteSetupMode.showcase
                  ? _buildShowcaseSelectionSection()
                  : _buildManualSelectionSection(),
              const SizedBox(height: 12),
              _PanelSection(
                title: 'Route Output',
                children: [
                  _KeyValue(
                    label: 'Shortest path',
                    value: _currentPath.isEmpty
                        ? 'None'
                        : _currentPath.join(' -> '),
                  ),
                  _KeyValue(
                    label: 'Commands',
                    value: _commands.isEmpty
                        ? 'None'
                        : _commands.map(RoutePlanner.commandLabel).join(' | '),
                  ),
                  _KeyValue(
                    label: 'Finish exit',
                    value: _finishAction == null
                        ? 'Off'
                        : RoutePlanner.commandLabel(_finishAction!),
                  ),
                  _KeyValue(
                    label: 'Bluetooth',
                    value: _commands.isEmpty
                        ? 'None'
                        : 'FINISH:${_finishAction ?? 'OFF'} | PATH:${_currentPath.join(',')} | ROUTE:${_commands.join()} | START',
                  ),
                  _StartButton(
                    enabled: _confirmEnabled,
                    onPressed: _confirmAndStart,
                  ),
                  _StopButton(onPressed: _stopTraversal),
                ],
              ),
              const SizedBox(height: 12),
              _CalibrationPanel(
                open: _calibrationOpen,
                values: _calibration,
                items: _visibleCalibrationItems,
                groups: _calibrationGroups.keys.toList(growable: false),
                selectedGroup: _calibrationGroup,
                canUndo: _lastCalibrationUndo != null,
                onToggle: () {
                  setState(() {
                    _calibrationOpen = !_calibrationOpen;
                  });
                },
                onGroupChanged: (group) {
                  setState(() {
                    _calibrationGroup = group;
                  });
                },
                onUndo: _undoCalibrationChange,
                onChanged: _setCalibrationValue,
              ),
              const SizedBox(height: 12),
              _PanelSection(
                title: 'Arduino Log',
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 86,
                      child: _MiniButton(
                        label: 'CLEAR',
                        danger: true,
                        onPressed: _bluetooth.clearLogs,
                      ),
                    ),
                  ),
                  _LogBox(lines: _bluetooth.logs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelemetrySnapshot extends StatelessWidget {
  const _TelemetrySnapshot({
    required this.bluetooth,
    required this.showRawSensorValues,
  });

  final RobotBluetoothService bluetooth;
  final bool showRawSensorValues;

  @override
  Widget build(BuildContext context) {
    final telemetry = bluetooth.telemetry;
    final lastPacketAt = telemetry.lastSensorPacketAt;
    final age = lastPacketAt == null
        ? null
        : DateTime.now().difference(lastPacketAt);
    final live = age != null && age < const Duration(milliseconds: 900);
    final ageLabel = age == null
        ? 'No packet'
        : age.inMilliseconds < 1000
        ? '${age.inMilliseconds} ms ago'
        : '${age.inSeconds} s ago';
    final rawValues = telemetry.hasRawValues
        ? telemetry.rawD8ToD1.join(', ')
        : 'Waiting for RAW packet';

    return _PanelSection(
      title: 'Live Sensor RX',
      children: [
        Row(
          children: [
            _StatusBadge(label: live ? 'LIVE' : 'WAIT', live: live),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ageLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        _KeyValue(label: 'Bits D8-D1', value: telemetry.bitsD8ToD1.join()),
        _KeyValue(label: 'Black count', value: '${telemetry.blackCount}'),
        _KeyValue(label: 'Threshold', value: '${telemetry.threshold}'),
        _KeyValue(
          label: 'Position',
          value: telemetry.position.toStringAsFixed(2),
        ),
        _KeyValue(
          label: showRawSensorValues ? 'Raw D8-D1' : 'Raw D8-D1 hidden',
          value: showRawSensorValues ? rawValues : 'Tap Show raw values',
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? const Color(0xFF10C772) : const Color(0xFFFFC400);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TraversalTopBar extends StatelessWidget {
  const _TraversalTopBar({
    required this.bluetooth,
    required this.showRawSensorValues,
  });

  final RobotBluetoothService bluetooth;
  final bool showRawSensorValues;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: const Color(0xFFCFCFCF), width: 3),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0xFF151515), spreadRadius: 2)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SensorStrip(
              bluetooth: bluetooth,
              showRawSensorValues: showRawSensorValues,
            ),
          ),
          const SizedBox(width: 8),
          _BluetoothPill(connected: bluetooth.isConnected),
        ],
      ),
    );
  }
}

class _SensorStrip extends StatelessWidget {
  const _SensorStrip({
    required this.bluetooth,
    required this.showRawSensorValues,
  });

  final RobotBluetoothService bluetooth;
  final bool showRawSensorValues;

  @override
  Widget build(BuildContext context) {
    final values = bluetooth.telemetry.rawD8ToD1;
    final bits = bluetooth.telemetry.bitsD8ToD1;
    final rawValuesReady = bluetooth.telemetry.hasRawValues;
    const labels = ['D8', 'D7', 'D6', 'D5', 'D4', 'D3', 'D2', 'D1'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    labels[i],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bits[i] == 1
                          ? const Color(0xFFFF3131)
                          : const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: bits[i] == 1
                            ? Colors.white
                            : const Color(0xFF4A4A4A),
                        width: 1,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        showRawSensorValues
                            ? rawValuesReady
                                  ? '${values[i]}'
                                  : '--'
                            : '',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BluetoothPill extends StatelessWidget {
  const _BluetoothPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF10C772) : const Color(0xFFFF3131);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: connected ? color : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth,
            color: connected ? Colors.white : color,
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            'HC-05',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: connected ? Colors.white : color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _BorderCard extends StatelessWidget {
  const _BorderCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: const Color(0xFFCFCFCF), width: 4),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0xFF151515), spreadRadius: 2)],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292929), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 9),
          ...children.expand((child) sync* {
            yield child;
            if (child != children.last) {
              yield const SizedBox(height: 8);
            }
          }),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF292929))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 12),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapCircleButton extends StatelessWidget {
  const _MapCircleButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF3131) : Colors.black;
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 5,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: color, size: 21),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: const Color(0xFF10C772),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HintLine extends StatelessWidget {
  const _HintLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFBDBDBD),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.green = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool green;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFFF3131)
        : green
        ? const Color(0xFF10C772)
        : Colors.black;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        disabledForegroundColor: Colors.black.withValues(alpha: 0.35),
        side: BorderSide(
          color: onPressed == null
              ? Colors.white.withValues(alpha: 0.35)
              : color,
          width: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        minimumSize: const Size(34, 32),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF10C772),
        disabledBackgroundColor: const Color(
          0xFF555555,
        ).withValues(alpha: 0.55),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
      ),
      child: const Text('CONFIRM & START!'),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFF3131),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      child: const Text('STOP'),
    );
  }
}

class _CalibrationPanel extends StatelessWidget {
  const _CalibrationPanel({
    required this.open,
    required this.values,
    required this.items,
    required this.groups,
    required this.selectedGroup,
    required this.canUndo,
    required this.onToggle,
    required this.onGroupChanged,
    required this.onUndo,
    required this.onChanged,
  });

  final bool open;
  final Map<String, double> values;
  final List<CalibrationItem> items;
  final List<String> groups;
  final String selectedGroup;
  final bool canUndo;
  final VoidCallback onToggle;
  final ValueChanged<String> onGroupChanged;
  final VoidCallback onUndo;
  final void Function(String key, double value, {bool send}) onChanged;

  @override
  Widget build(BuildContext context) {
    return _PanelSection(
      title: 'Calibration Settings',
      children: [
        TextButton(
          onPressed: onToggle,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Calibration Settings',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
        if (open) ...[
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedGroup,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                      items: [
                        for (final group in groups)
                          DropdownMenuItem(value: group, child: Text(group)),
                      ],
                      onChanged: (group) {
                        if (group != null) {
                          onGroupChanged(group);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: _MiniButton(
                  label: 'UNDO',
                  onPressed: canUndo ? onUndo : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            _CalibrationRow(
              item: item,
              value: values[item.key] ?? item.min,
              onChanged: onChanged,
            ),
        ],
      ],
    );
  }
}

class _CalibrationInfo {
  const _CalibrationInfo({
    required this.purpose,
    required this.tooLow,
    required this.tooHigh,
    required this.tuneWhen,
  });

  final String purpose;
  final String tooLow;
  final String tooHigh;
  final String tuneWhen;
}

const Map<String, _CalibrationInfo> _calibrationInfo = {
  'threshold': _CalibrationInfo(
    purpose: 'Analog cutoff that converts each sensor into black or white.',
    tooLow: 'White floor may be counted as black, causing false nodes.',
    tooHigh: 'The robot may miss the line or black node blocks.',
    tuneWhen:
        'Tune first. A 3 cm line should read about 3-4 black sensors; a node should read 6-8.',
  ),
  'baseSpeed': _CalibrationInfo(
    purpose: 'Normal forward speed while following a line between nodes.',
    tooLow: 'Traversal becomes slow and may stall on weak batteries.',
    tooHigh: 'The robot may wobble, overshoot nodes, or enter turns too fast.',
    tuneWhen:
        'Tune after sensors are correct. Lower it while proving the shortest route.',
  ),
  'turnSpeed': _CalibrationInfo(
    purpose: 'Blind pivot speed for normal left/right turns.',
    tooLow: 'The robot may fail to rotate enough or stall during turns.',
    tooHigh: 'The robot may overshoot the outgoing line before catch phase.',
    tuneWhen:
        'Tune normal turns at nodes 2, 4, 16, 17, and the finish turn at 21.',
  ),
  'shallowTurnSpeed': _CalibrationInfo(
    purpose:
        'Blind pivot speed for shallow Q/E turns at diagonal/Y intersections.',
    tooLow: 'The robot may barely leave the node direction.',
    tooHigh: 'A shallow turn can behave like a 90-degree turn and overshoot.',
    tuneWhen: 'Tune the E turns at nodes 5 and 10 on the shortest route.',
  ),
  'catchTurnSpeed': _CalibrationInfo(
    purpose:
        'Slow pivot speed after blind turn time while searching for the outgoing line.',
    tooLow: 'The robot may catch very slowly or not reach the line.',
    tooHigh:
        'The robot may pass over the outgoing line before it becomes stable.',
    tuneWhen:
        'Tune when turns are close but inconsistent after the blind phase.',
  ),
  'slowSpeed': _CalibrationInfo(
    purpose:
        'Careful forward speed during node handling and blind forward movement.',
    tooLow: 'The robot may stall while crossing a node block.',
    tooHigh: 'The robot may travel too far before turning or stopping.',
    tuneWhen: 'Tune together with Node FWD and Final FWD.',
  ),
  'manualCurve': _CalibrationInfo(
    purpose: 'Manual-mode curve strength for diagonal button movement.',
    tooLow: 'Manual diagonal movement feels almost straight.',
    tooHigh: 'Manual diagonal movement turns too sharply.',
    tuneWhen: 'Only affects manual driving, not autonomous traversal.',
  ),
  'kp': _CalibrationInfo(
    purpose: 'Line-following correction strength.',
    tooLow: 'The robot drifts slowly away from the line.',
    tooHigh: 'The robot zigzags aggressively on straight tracks.',
    tuneWhen: 'Tune after Threshold and motor trims are reasonable.',
  ),
  'nodePause': _CalibrationInfo(
    purpose: 'Pause after detecting a node before executing the route command.',
    tooLow: 'Harder to observe logs and debug node detections.',
    tooHigh: 'Traversal becomes slow at every node.',
    tuneWhen: 'Keep higher during testing; reduce for final demo if needed.',
  ),
  'nodeCooldown': _CalibrationInfo(
    purpose: 'Minimum time before another node can be counted.',
    tooLow: 'One 10 cm black block can be counted twice.',
    tooHigh: 'Short edges may cause the next node to be ignored.',
    tuneWhen: 'Tune if logs show duplicate NODE events or missed close nodes.',
  ),
  'nodeForward': _CalibrationInfo(
    purpose: 'Blind forward movement after detecting a node before turning.',
    tooLow:
        'The robot turns too early while its rotation center is not inside the node.',
    tooHigh: 'The robot drives past the node center before turning.',
    tuneWhen:
        'Tune before turn speeds. It affects every turn on the shortest route.',
  ),
  'turnTimeout': _CalibrationInfo(
    purpose: 'Maximum time allowed for a turn before timeout.',
    tooLow: 'Valid turns may stop with timeout warnings.',
    tooHigh: 'A bad turn can spin for too long before stopping.',
    tuneWhen:
        'Raise only if turn tuning is otherwise correct but timeouts still occur.',
  ),
  'minTurn': _CalibrationInfo(
    purpose: 'Blind time before normal turns are allowed to catch a line.',
    tooLow: 'The robot may accept the black node itself as the outgoing line.',
    tooHigh: 'The robot may rotate past the outgoing line before catch starts.',
    tuneWhen:
        'Tune normal 90-degree turns at nodes 2, 4, 16, 17, and finish 21.',
  ),
  'shallowMinTurn': _CalibrationInfo(
    purpose: 'Blind time before shallow Q/E turns are allowed to catch a line.',
    tooLow: 'The robot may catch while still on the black node block.',
    tooHigh: 'The robot may overshoot the shallow diagonal exit.',
    tuneWhen: 'Tune specifically for nodes 5 and 10 on the shortest route.',
  ),
  'afterTurn': _CalibrationInfo(
    purpose: 'Forward movement after catching the outgoing line.',
    tooLow:
        'The robot may redetect the same node or hesitate at the node edge.',
    tooHigh: 'The robot may drive too far before line following stabilizes.',
    tuneWhen: 'Tune after turns catch correctly but exit from nodes is messy.',
  ),
  'finalForward': _CalibrationInfo(
    purpose:
        'Extra forward movement before stopping at final node or finish line.',
    tooLow:
        'The robot may stop too early on node 21 or before the finish line.',
    tooHigh: 'The robot may pass too far beyond the finish line.',
    tuneWhen: 'Tune last, after the node 21 finish-exit turn works.',
  ),
  'minPwm': _CalibrationInfo(
    purpose: 'Minimum PWM applied to drive motors.',
    tooLow: 'Motors may hum or stall instead of moving.',
    tooHigh: 'Small corrections become jumpy.',
    tuneWhen: 'Tune if low-speed movement is unreliable.',
  ),
  'minPivot': _CalibrationInfo(
    purpose: 'Minimum PWM applied during pivot turns.',
    tooLow: 'Turns may stall or fail on carpet/low battery.',
    tooHigh: 'Turns become too sudden even with low turn speeds.',
    tuneWhen:
        'Tune if changing Turn SPD or Catch Turn does not affect weak pivots enough.',
  ),
  'leftTrim': _CalibrationInfo(
    purpose: 'Speed correction for the left motor.',
    tooLow: 'The robot may drift one direction on straight lines.',
    tooHigh: 'The robot may drift the opposite direction.',
    tuneWhen:
        'Tune with Right Trim after verifying both motors are wired correctly.',
  ),
  'rightTrim': _CalibrationInfo(
    purpose: 'Speed correction for the right motor.',
    tooLow: 'The robot may drift one direction on straight lines.',
    tooHigh: 'The robot may drift the opposite direction.',
    tuneWhen:
        'Tune with Left Trim after verifying both motors are wired correctly.',
  ),
  'nodeBlackMin': _CalibrationInfo(
    purpose:
        'Minimum black sensor count required to detect a 10 cm node block.',
    tooLow: 'A wide line or messy edge can be mistaken as a node.',
    tooHigh: 'Real nodes may be missed if not all sensors read black.',
    tuneWhen: 'Use telemetry on a node. Start at 6; try 5 if nodes are missed.',
  ),
  'lineBlackMax': _CalibrationInfo(
    purpose: 'Maximum black count accepted as a normal line during turn catch.',
    tooLow: 'The robot may rotate past the line and never catch it.',
    tooHigh: 'The robot may accept the full black node as the outgoing line.',
    tuneWhen: 'Tune if turns catch too early while still inside a node block.',
  ),
  'stableMs': _CalibrationInfo(
    purpose:
        'How long the outgoing line must stay centered before a turn is accepted.',
    tooLow: 'Noisy sensor flashes can be accepted as a real line.',
    tooHigh: 'The robot may see the line but keep rotating past it.',
    tuneWhen: 'Tune after Min Turn and Catch Turn are close.',
  ),
  'lostMs': _CalibrationInfo(
    purpose: 'How long a node candidate must persist before being confirmed.',
    tooLow: 'Sensor noise can create false node detections.',
    tooHigh: 'Fast movement may cross a node before it confirms.',
    tuneWhen: 'Tune if node logs are noisy or delayed.',
  ),
  'telemetryMs': _CalibrationInfo(
    purpose: 'Interval for sensor telemetry packets in traversal mode.',
    tooLow: 'Bluetooth/log traffic can become heavy.',
    tooHigh: 'Sensor UI updates slowly while tuning.',
    tuneWhen:
        'Use faster telemetry while tuning, slower telemetry for smoother driving.',
  ),
};

class _CalibrationRow extends StatelessWidget {
  const _CalibrationRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final CalibrationItem item;
  final double value;
  final void Function(String key, double value, {bool send}) onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((item.max - item.min) / item.step)
        .round()
        .clamp(1, 1000)
        .toInt();
    final fineStep = item.step;
    final coarseStep = _coarseStepFor(item);
    final info = _calibrationInfo[item.key];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (info != null)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    tooltip: '${item.label} info',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: const Color(0xFF33D2D2),
                    onPressed: () => _showCalibrationInfo(context, info),
                    icon: const Icon(Icons.info_outline),
                  ),
                ),
              const SizedBox(width: 4),
              Container(
                width: 72,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatCalibrationValue(value),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _CalStepButton(
                label: '-${_formatStep(coarseStep)}',
                onPressed: () =>
                    onChanged(item.key, value - coarseStep, send: true),
              ),
              const SizedBox(width: 4),
              _CalStepButton(
                label: '-${_formatStep(fineStep)}',
                onPressed: () =>
                    onChanged(item.key, value - fineStep, send: true),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF555555),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.14),
                    trackHeight: 5,
                  ),
                  child: Slider(
                    value: value.clamp(item.min, item.max).toDouble(),
                    min: item.min,
                    max: item.max,
                    divisions: divisions,
                    onChanged: (next) => onChanged(item.key, next),
                    onChangeEnd: (next) =>
                        onChanged(item.key, next, send: true),
                  ),
                ),
              ),
              _CalStepButton(
                label: '+${_formatStep(fineStep)}',
                onPressed: () =>
                    onChanged(item.key, value + fineStep, send: true),
              ),
              const SizedBox(width: 4),
              _CalStepButton(
                label: '+${_formatStep(coarseStep)}',
                onPressed: () =>
                    onChanged(item.key, value + coarseStep, send: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCalibrationInfo(BuildContext context, _CalibrationInfo info) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          title: Text(
            item.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoBlock(label: 'Controls', text: info.purpose),
                _InfoBlock(label: 'Too low', text: info.tooLow),
                _InfoBlock(label: 'Too high', text: info.tooHigh),
                _InfoBlock(label: 'Tune when', text: info.tuneWhen),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  double _coarseStepFor(CalibrationItem item) {
    if (item.key == 'kp') {
      return 1;
    }
    if (item.step >= 50) {
      return item.step * 2;
    }
    if (item.step >= 10) {
      return item.step * 5;
    }
    return 10;
  }

  String _formatStep(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF33D2D2),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalStepButton extends StatelessWidget {
  const _CalStepButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 30,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final visibleLines = lines.length > 60
        ? lines.sublist(lines.length - 60)
        : lines;
    return Container(
      height: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          visibleLines.join('\n'),
          style: const TextStyle(
            color: Color(0xFFDBEAFE),
            fontSize: 11,
            height: 1.45,
            fontFamily: 'FiraCode',
          ),
        ),
      ),
    );
  }
}
