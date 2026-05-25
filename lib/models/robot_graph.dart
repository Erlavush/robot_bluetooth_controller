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

const Size graphSize = Size(1000, 1000);

final Map<int, Offset> graphNodes = {
  1: const Offset(95, 55),
  2: const Offset(255, 55),
  3: const Offset(415, 55),
  4: const Offset(785, 45),
  5: const Offset(710, 135),
  6: const Offset(865, 125),
  7: const Offset(95, 195),
  8: const Offset(255, 195),
  9: const Offset(415, 195),
  10: const Offset(640, 195),
  11: const Offset(785, 195),
  12: const Offset(945, 205),
  13: const Offset(710, 270),
  14: const Offset(860, 270),
  15: const Offset(95, 345),
  16: const Offset(255, 345),
  17: const Offset(415, 345),
  18: const Offset(785, 345),
  19: const Offset(255, 430),
  20: const Offset(785, 430),
  21: const Offset(140, 470),
  22: const Offset(905, 470),
  23: const Offset(255, 540),
  24: const Offset(520, 540),
  25: const Offset(785, 540),
  26: const Offset(140, 620),
  27: const Offset(905, 620),
  28: const Offset(255, 680),
  29: const Offset(785, 680),
  30: const Offset(255, 760),
  31: const Offset(625, 760),
  32: const Offset(785, 760),
  33: const Offset(945, 760),
  34: const Offset(115, 870),
  35: const Offset(255, 870),
  36: const Offset(395, 870),
  37: const Offset(625, 870),
  38: const Offset(785, 870),
  39: const Offset(945, 870),
  40: const Offset(255, 985),
  41: const Offset(625, 985),
  42: const Offset(785, 985),
  43: const Offset(945, 985),
};

final Map<int, List<int>> graphAdjacency = {
  1: [2, 7],
  2: [1, 3, 8],
  3: [2, 9],
  4: [5, 6],
  5: [4, 10, 11],
  6: [4, 12, 11],
  7: [1, 8, 15],
  8: [2, 7, 9, 16],
  9: [3, 8, 17, 10],
  10: [5, 9, 13],
  11: [5, 6, 13, 14],
  12: [6, 14],
  13: [10, 11, 18],
  14: [11, 12, 18],
  15: [7, 16],
  16: [8, 15, 17, 19],
  17: [9, 16],
  18: [13, 14, 20],
  19: [16, 20, 21, 23],
  20: [18, 19, 22, 25],
  21: [19, 26],
  22: [20, 27],
  23: [19, 24, 28],
  24: [23, 25],
  25: [20, 24, 29],
  26: [21, 28],
  27: [22, 29],
  28: [23, 26, 29, 30],
  29: [25, 27, 28, 32],
  30: [28, 34, 35, 36],
  31: [32, 37],
  32: [29, 31, 33, 38],
  33: [32, 39],
  34: [30, 35, 40],
  35: [30, 34, 36, 40],
  36: [30, 35, 37, 40],
  37: [31, 36, 38, 41],
  38: [32, 37, 39, 42],
  39: [33, 38, 43],
  40: [34, 35, 36],
  41: [37, 42],
  42: [38, 41, 43],
  43: [39, 42],
};

final Map<String, CubicEdge> curvedEdges = {
  '19-21': const CubicEdge(
    Offset(255, 430),
    Offset(205, 430),
    Offset(165, 442),
    Offset(140, 470),
  ),
  '21-26': const CubicEdge(
    Offset(140, 470),
    Offset(75, 520),
    Offset(75, 570),
    Offset(140, 620),
  ),
  '26-28': const CubicEdge(
    Offset(140, 620),
    Offset(165, 658),
    Offset(205, 680),
    Offset(255, 680),
  ),
  '20-22': const CubicEdge(
    Offset(785, 430),
    Offset(835, 430),
    Offset(875, 442),
    Offset(905, 470),
  ),
  '22-27': const CubicEdge(
    Offset(905, 470),
    Offset(970, 520),
    Offset(970, 570),
    Offset(905, 620),
  ),
  '27-29': const CubicEdge(
    Offset(905, 620),
    Offset(875, 658),
    Offset(835, 680),
    Offset(785, 680),
  ),
  '30-34': const CubicEdge(
    Offset(255, 760),
    Offset(165, 760),
    Offset(115, 800),
    Offset(115, 870),
  ),
  '34-40': const CubicEdge(
    Offset(115, 870),
    Offset(115, 945),
    Offset(170, 985),
    Offset(255, 985),
  ),
  '30-36': const CubicEdge(
    Offset(255, 760),
    Offset(340, 760),
    Offset(395, 805),
    Offset(395, 870),
  ),
  '36-40': const CubicEdge(
    Offset(395, 870),
    Offset(395, 945),
    Offset(340, 985),
    Offset(255, 985),
  ),
};

final Map<int, Offset> labelOffsets = {
  1: const Offset(-18, -28),
  2: const Offset(0, -28),
  3: const Offset(0, -28),
  4: const Offset(0, -30),
  5: const Offset(-34, -12),
  6: const Offset(34, -8),
  7: const Offset(-40, 4),
  8: const Offset(-28, -25),
  9: const Offset(-28, -25),
  10: const Offset(-36, -28),
  11: const Offset(0, -34),
  12: const Offset(44, 4),
  13: const Offset(-28, 36),
  14: const Offset(28, 36),
  15: const Offset(-35, -5),
  16: const Offset(-35, -5),
  17: const Offset(-28, -5),
  18: const Offset(-28, -28),
  19: const Offset(30, 28),
  20: const Offset(-30, 28),
  21: const Offset(24, 12),
  22: const Offset(-24, 12),
  23: const Offset(-58, 0),
  24: const Offset(0, 38),
  25: const Offset(38, 6),
  26: const Offset(24, 10),
  27: const Offset(-24, 10),
  28: const Offset(30, 28),
  29: const Offset(-30, 28),
  30: const Offset(-26, -24),
  31: const Offset(-30, 28),
  32: const Offset(-28, 28),
  33: const Offset(-28, 28),
  34: const Offset(-38, 0),
  35: const Offset(-28, 28),
  36: const Offset(28, 28),
  37: const Offset(-30, 28),
  38: const Offset(-28, 28),
  39: const Offset(-28, 28),
  40: const Offset(28, -10),
  41: const Offset(-32, -18),
  42: const Offset(-28, -18),
  43: const Offset(-28, -18),
};

final List<GraphEdge> allGraphEdges = _buildEdges();

String edgeKey(int a, int b) {
  return '${math.min(a, b)}-${math.max(a, b)}';
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

  final start = graphNodes[a]!;
  final end = graphNodes[b]!;
  path.moveTo(start.dx, start.dy);
  path.lineTo(end.dx, end.dy);
  return path;
}

double edgeDistance(int a, int b) {
  final start = graphNodes[a]!;
  final end = graphNodes[b]!;
  return (start - end).distance;
}

double angleBetweenNodes(int a, int b) {
  final start = graphNodes[a]!;
  final end = graphNodes[b]!;
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
