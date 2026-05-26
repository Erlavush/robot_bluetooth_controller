import 'dart:math' as math;

import 'package:flutter/material.dart';

class GraphEdge {
  const GraphEdge(this.a, this.b);

  final int a;
  final int b;

  String get key => edgeKey(a, b);

  bool containsNode(int node) => a == node || b == node;
}

class CubicEdge {
  const CubicEdge(this.start, this.control1, this.control2, this.end);

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
}

const Size graphSize = Size(1900, 2050);
const double graphTrackWidth = 28;
const double graphNodeBlockSize = 78;
const int startGuideNode = 0;
const int finishGuideNode = 22;
const int showcaseStartNode = 1;
const int showcaseFinishNode = 21;

final Map<int, Offset> graphNodes = {
  1: const Offset(250, 120),
  2: const Offset(820, 120),
  3: const Offset(1420, 120),
  4: const Offset(820, 350),
  5: const Offset(1200, 350),
  6: const Offset(1680, 350),
  7: const Offset(250, 640),
  8: const Offset(520, 640),
  9: const Offset(820, 640),
  10: const Offset(1420, 640),
  11: const Offset(520, 880),
  12: const Offset(1420, 880),
  13: const Offset(520, 1180),
  14: const Offset(1420, 1180),
  15: const Offset(1200, 1410),
  16: const Offset(1420, 1410),
  17: const Offset(1680, 1410),
  18: const Offset(520, 1660),
  19: const Offset(1200, 1660),
  20: const Offset(1200, 1875),
  21: const Offset(1680, 1875),
};

final Map<int, Offset> externalGraphPoints = {
  startGuideNode: const Offset(105, 120),
  finishGuideNode: const Offset(1835, 1875),
};

final Map<int, List<int>> graphAdjacency = {
  1: [2, 7],
  2: [1, 4],
  3: [5, 6],
  4: [2, 9, 5],
  5: [4, 10, 3],
  6: [3, 10],
  7: [1, 8],
  8: [7, 9, 11],
  9: [4, 8],
  10: [5, 6, 12],
  11: [8, 12, 13],
  12: [10, 11, 14],
  13: [14, 11, 18],
  14: [13, 12, 16],
  15: [19, 16],
  16: [14, 15, 17],
  17: [16, 21],
  18: [13, 19],
  19: [18, 15, 20],
  20: [21, 19],
  21: [17, 20],
};

final Map<String, double> graphEdgeDistancesCm = {
  '1-2': 54,
  '1-7': 50,
  '2-4': 19,
  '4-9': 21,
  '4-5': 36,
  '7-8': 22.5,
  '8-9': 22,
  '5-10': 33,
  '3-5': 33,
  '3-6': 33,
  '6-10': 33,
  '8-11': 19.5,
  '10-12': 19.5,
  '11-12': 100,
  '13-14': 100,
  '12-14': 43,
  '11-13': 43,
  '14-16': 29.5,
  '13-18': 48.5,
  '18-19': 69,
  '15-19': 17,
  '15-16': 23,
  '16-17': 22,
  '17-21': 47,
  '20-21': 54.5,
  '19-20': 21,
};

final Map<String, CubicEdge> curvedEdges = const {};

final Map<int, Offset> labelOffsets = {
  1: const Offset(0, -70),
  2: const Offset(0, -70),
  3: const Offset(36, -70),
  4: const Offset(-88, -8),
  5: const Offset(74, -8),
  6: const Offset(86, 28),
  7: const Offset(0, 70),
  8: const Offset(48, 70),
  9: const Offset(0, 70),
  10: const Offset(78, 70),
  11: const Offset(-90, 0),
  12: const Offset(86, 0),
  13: const Offset(-90, 0),
  14: const Offset(86, 0),
  15: const Offset(-22, -70),
  16: const Offset(42, -70),
  17: const Offset(80, -70),
  18: const Offset(-78, -70),
  19: const Offset(-66, -70),
  20: const Offset(-66, 0),
  21: const Offset(80, 62),
};

final List<GraphEdge> allGraphEdges = _buildEdges();

String edgeKey(int a, int b) {
  return '${math.min(a, b)}-${math.max(a, b)}';
}

Offset graphPointFor(int node) {
  final point = graphNodes[node] ?? externalGraphPoints[node];
  if (point == null) {
    throw ArgumentError.value(node, 'node', 'Unknown graph node');
  }
  return point;
}

Path edgePath(int a, int b) {
  final key = edgeKey(a, b);
  final curve = curvedEdges[key];
  final path = Path();
  if (curve != null) {
    path.moveTo(curve.start.dx, curve.start.dy);
    path.cubicTo(
      curve.control1.dx,
      curve.control1.dy,
      curve.control2.dx,
      curve.control2.dy,
      curve.end.dx,
      curve.end.dy,
    );
    return path;
  }

  final start = graphPointFor(a);
  final end = graphPointFor(b);
  path.moveTo(start.dx, start.dy);
  path.lineTo(end.dx, end.dy);
  return path;
}

double edgeDistance(int a, int b) {
  final measuredDistance = graphEdgeDistancesCm[edgeKey(a, b)];
  if (measuredDistance != null) {
    return measuredDistance;
  }

  final start = graphPointFor(a);
  final end = graphPointFor(b);
  return (start - end).distance;
}

double angleBetweenNodes(int a, int b) {
  final start = graphPointFor(a);
  final end = graphPointFor(b);
  return math.atan2(end.dy - start.dy, end.dx - start.dx) + math.pi / 2;
}

List<GraphEdge> _buildEdges() {
  final seen = <String>{};
  final edges = <GraphEdge>[];

  for (final entry in graphAdjacency.entries) {
    for (final next in entry.value) {
      final key = edgeKey(entry.key, next);
      if (seen.add(key)) {
        edges.add(GraphEdge(entry.key, next));
      }
    }
  }

  return edges;
}
