import 'dart:convert';

import 'package:flutter/material.dart' hide Viewport;

import 'formula_entry.dart';
import 'math_3d_object.dart';
import 'math_3d_scene.dart';
import 'math_3d_tool.dart';
import 'math_drawing_controller.dart';
import 'math_drawing_state.dart';
import 'math_parameter.dart';

/// Portable, versioned `.vm` drawing file. Unknown optional keys are retained.
class MathDrawingDocument {
  static const int formatVersion = 1;
  final String name;
  final MathDrawingSnapshot drawing;
  final Map<String, dynamic> extensions;

  const MathDrawingDocument({
    required this.name,
    required this.drawing,
    this.extensions = const {},
  });

  Map<String, dynamic> toJson() => {
    'format': 'visual-math-drawing',
    'version': formatVersion,
    'name': name,
    'drawing': _snapshotToJson(drawing),
    'requiredFeatures': const <String>[],
    if (extensions.isNotEmpty) 'extensions': extensions,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory MathDrawingDocument.decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Invalid .vm JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>)
      throw const FormatException('A .vm document must be a JSON object.');
    if (decoded['format'] != 'visual-math-drawing')
      throw const FormatException(
        'This is not a Visual Math drawing document.',
      );
    final version = decoded['version'];
    if (version != formatVersion)
      throw FormatException('Unsupported .vm document version: $version.');
    final requiredFeatures = decoded['requiredFeatures'] ?? const <dynamic>[];
    if (requiredFeatures is! List || requiredFeatures.isNotEmpty) {
      throw const FormatException(
        'This document requires unsupported features.',
      );
    }
    final rawName = decoded['name'];
    if (rawName is! String || rawName.trim().isEmpty)
      throw const FormatException('Document name is missing.');
    final drawing = decoded['drawing'];
    if (drawing is! Map<String, dynamic>)
      throw const FormatException('Drawing data is missing or malformed.');
    final rawExtensions = decoded['extensions'];
    if (rawExtensions != null && rawExtensions is! Map<String, dynamic>)
      throw const FormatException('Document extensions must be an object.');
    return MathDrawingDocument(
      name: rawName,
      drawing: _snapshotFromJson(drawing),
      extensions: Map.unmodifiable(
        (rawExtensions as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

Map<String, dynamic> _snapshotToJson(MathDrawingSnapshot s) => {
  'formulas': [
    for (var i = 0; i < s.formulas.length; i++)
      {
        'id': s.formulas[i].id.isEmpty ? 'formula-$i' : s.formulas[i].id,
        'source': s.formulas[i].rawExpression,
        'color': s.formulas[i].color.toARGB32(),
        'colorMode': s.formulas[i].autoColor ? 'auto' : 'custom',
        'visible': s.formulas[i].visible,
        'parameterValues': s.formulas[i].parameterValues,
      },
  ],
  'parameters': {
    for (final e in s.parameters.entries)
      e.key: {
        'value': e.value.value,
        'min': e.value.min,
        'max': e.value.max,
        'step': e.value.step,
      },
  },
  'view': s.activeView.name,
  'activeTool': s.activeTool.name,
  'viewport2D': s.viewport2D.toJson(),
  'view3D': {
    'camera': {
      'target': _point(s.camera3D.target),
      'distance': s.camera3D.distance,
      'theta': s.camera3D.theta,
      'phi': s.camera3D.phi,
    },
    'projection': s.projection3D.name,
    'showAxes': s.showAxes3D,
    'showPlane': s.showPlane3D,
    'showGrid': s.showGrid3D,
    'showLabels': s.showLabels3D,
    'objects': [for (final o in s.scene3D) _objectToJson(o)],
  },
};

MathDrawingSnapshot _snapshotFromJson(Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v, String field) {
    if (v is! List || v.any((e) => e is! Map<String, dynamic>))
      throw FormatException(
        'Required field "$field" must be an array of objects.',
      );
    return v.cast<Map<String, dynamic>>();
  }

  Map<String, dynamic> obj(Object? v, String field) {
    if (v is! Map<String, dynamic>)
      throw FormatException('Required field "$field" must be an object.');
    return v;
  }

  final formulas = [
    for (final f in list(j['formulas'], 'formulas'))
      FormulaEntry(
        id: _required<String>(f, 'id'),
        rawExpression: _required<String>(f, 'source'),
        parsed: null,
        color: Color(_required<int>(f, 'color')),
        autoColor: switch (_required<String>(f, 'colorMode')) {
          'auto' => true,
          'custom' => false,
          _ => throw const FormatException('Unknown formula color mode.'),
        },
        visible: _required<bool>(f, 'visible'),
        parameterValues: _doubleMap(f['parameterValues']),
      ),
  ];
  final formulaIds = formulas.map((formula) => formula.id).toSet();
  if (formulaIds.length != formulas.length ||
      formulas.any((formula) => formula.id.isEmpty)) {
    throw const FormatException('Formula row IDs must be non-empty and unique.');
  }
  final parameterJson = obj(j['parameters'], 'parameters');
  final parameters = <String, MathParameter>{};
  parameterJson.forEach((key, value) {
    final p = obj(value, 'parameters.$key');
    parameters[key] = MathParameter(
      value: _num(p, 'value'),
      min: _num(p, 'min'),
      max: _num(p, 'max'),
      step: _num(p, 'step'),
    );
  });
  final view = ViewMode.values.where((e) => e.name == j['view']).firstOrNull;
  if (view == null) throw const FormatException('Unknown active view.');
  final tool = ConstructionTool.values
      .where((e) => e.name == j['activeTool'])
      .firstOrNull;
  if (tool == null)
    throw const FormatException('Unknown active construction tool.');
  final viewportJson = obj(j['viewport2D'], 'viewport2D');
  final viewport = Viewport(
    xMin: _num(viewportJson, 'xMin'),
    yMin: _num(viewportJson, 'yMin'),
    xMax: _num(viewportJson, 'xMax'),
    yMax: _num(viewportJson, 'yMax'),
  );
  if (viewport.xMin >= viewport.xMax || viewport.yMin >= viewport.yMax) {
    throw const FormatException('2D viewport bounds are invalid.');
  }
  final v3 = obj(j['view3D'], 'view3D');
  final camera = obj(v3['camera'], 'view3D.camera');
  final target = _pointFrom(camera['target'], 'view3D.camera.target');
  final projection = ProjectionType.values
      .where((e) => e.name == v3['projection'])
      .firstOrNull;
  if (projection == null) throw const FormatException('Unknown 3D projection.');
  final objects = [
    for (final o in list(v3['objects'], 'view3D.objects')) _objectFromJson(o),
  ];
  return MathDrawingSnapshot(
    formulas: formulas,
    parameters: parameters,
    activeView: view,
    activeTool: tool,
    viewport2D: viewport,
    camera3D: Camera3D(
      target: target,
      distance: _num(camera, 'distance'),
      theta: _num(camera, 'theta'),
      phi: _num(camera, 'phi'),
    ),
    projection3D: projection,
    showAxes3D: _required<bool>(v3, 'showAxes'),
    showPlane3D: _required<bool>(v3, 'showPlane'),
    showGrid3D: _required<bool>(v3, 'showGrid'),
    showLabels3D: _required<bool>(v3, 'showLabels'),
    scene3D: objects,
  );
}

T _required<T>(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is! T)
    throw FormatException('Required field "$k" is missing or invalid.');
  return v;
}

double _num(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is! num || !v.toDouble().isFinite)
    throw FormatException('Required number "$k" is invalid.');
  return v.toDouble();
}

Map<String, double> _doubleMap(Object? v) {
  if (v == null) return const {};
  if (v is! Map<String, dynamic>)
    throw const FormatException('Formula parameter values must be an object.');
  return {
    for (final e in v.entries)
      e.key: (e.value is num && (e.value as num).toDouble().isFinite)
          ? (e.value as num).toDouble()
          : (throw FormatException('Invalid parameter value "${e.key}".')),
  };
}

Map<String, double> _point(Point3D p) => {'x': p.x, 'y': p.y, 'z': p.z};
Point3D _pointFrom(Object? v, String field) {
  if (v is! Map<String, dynamic>)
    throw FormatException('Required point "$field" is invalid.');
  return Point3D(_num(v, 'x'), _num(v, 'y'), _num(v, 'z'));
}

Map<String, double> _vector(Vector3D v) => {'x': v.x, 'y': v.y, 'z': v.z};
Vector3D _vectorFrom(Object? v, String field) {
  if (v is! Map<String, dynamic>)
    throw FormatException('Required vector "$field" is invalid.');
  return Vector3D(_num(v, 'x'), _num(v, 'y'), _num(v, 'z'));
}

Map<String, dynamic> _objectToJson(Object3D o) => {
  'type': o.type.name,
  'color': o.color,
  'opacity': o.opacity,
  'edgeWidth': o.edgeWidth,
  'showEdges': o.showEdges,
  'visible': o.visible,
  'label': o.label,
  'transformOrigin': o.transformOrigin,
  'text': o.isTextAnnotation ? o.label : null,
  'point': _point(o.point),
  'pointA': _point(o.pointA),
  'pointB': _point(o.pointB),
  'lineKind': o.lineKind.name,
  'plane': [o.planeA, o.planeB, o.planeC, o.planeD],
  'vertices': [for (final p in o.vertices) _point(p)],
  'indices': o.indices,
  'normals': [for (final n in o.normals) _vector(n)],
  'curveStarts': o.curveStarts,
  'sphereCenter': _point(o.sphereCenter),
  'sphereRadius': o.sphereRadius,
  'vector': _vector(o.vector),
  if (o.conic != null)
    'conic': {
      'origin': _point(o.conic!.origin),
      'axisU': _vector(o.conic!.axisU),
      'axisV': _vector(o.conic!.axisV),
      'quadraticX': o.conic!.quadraticX,
      'quadraticXY': o.conic!.quadraticXY,
      'quadraticY': o.conic!.quadraticY,
      'linearX': o.conic!.linearX,
      'linearY': o.conic!.linearY,
      'constant': o.conic!.constant,
    },
};
Object3D _objectFromJson(Map<String, dynamic> j) {
  final type = Object3DType.values
      .where((e) => e.name == j['type'])
      .firstOrNull;
  if (type == null) throw const FormatException('Unsupported 3D object type.');
  final color = _required<int>(j, 'color'),
      opacity = _num(j, 'opacity'),
      label = j['label'] as String?;
  final vertices = (j['vertices'] as List? ?? const [])
      .map((p) => _pointFrom(p, 'object.vertices'))
      .toList();
  final indices = (j['indices'] as List? ?? const [])
      .map((v) => v as int)
      .toList();
  final normals = (j['normals'] as List? ?? const [])
      .map((v) => _vectorFrom(v, 'object.normals'))
      .toList();
  switch (type) {
    case Object3DType.point:
      final point = _pointFrom(j['point'], 'object.point');
      final result = j['text'] is String
          ? Object3D.text(
              point,
              text: j['text'] as String,
              color: color,
              opacity: opacity,
            )
          : Object3D.point(point, color: color, opacity: opacity, label: label);
      return result.copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.line:
      final kind = Line3DKind.values
          .where((e) => e.name == j['lineKind'])
          .firstOrNull;
      if (kind == null) throw const FormatException('Unknown line kind.');
      return Object3D.line(
        _pointFrom(j['pointA'], 'object.pointA'),
        _pointFrom(j['pointB'], 'object.pointB'),
        lineKind: kind,
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.plane:
      final p = j['plane'];
      if (p is! List ||
          p.length != 4 ||
          p.any((v) => v is! num || !v.toDouble().isFinite))
        throw const FormatException('Plane geometry is invalid.');
      return Object3D.plane(
        a: (p[0] as num).toDouble(),
        b: (p[1] as num).toDouble(),
        c: (p[2] as num).toDouble(),
        d: (p[3] as num).toDouble(),
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.surface:
      return Object3D.surface(
        vertices: vertices,
        indices: indices,
        normals: normals,
        color: color,
        opacity: opacity,
        edgeWidth: _num(j, 'edgeWidth'),
        showEdges: _required<bool>(j, 'showEdges'),
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.sphere:
      return Object3D.sphere(
        center: _pointFrom(j['sphereCenter'], 'object.sphereCenter'),
        radius: _num(j, 'sphereRadius'),
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.polyhedron:
      return Object3D.polyhedron(
        vertices: vertices,
        indices: indices,
        color: color,
        opacity: opacity,
        edgeWidth: _num(j, 'edgeWidth'),
        showEdges: _required<bool>(j, 'showEdges'),
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.vector:
      return Object3D.vectorObj(
        vector: _vectorFrom(j['vector'], 'object.vector'),
        origin: _pointFrom(j['point'], 'object.point'),
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
    case Object3DType.curve:
      final cj = j['conic'];
      Conic3D? conic;
      if (cj != null) {
        if (cj is! Map<String, dynamic>)
          throw const FormatException('Conic data is malformed.');
        conic = Conic3D(
          origin: _pointFrom(cj['origin'], 'conic.origin'),
          axisU: _vectorFrom(cj['axisU'], 'conic.axisU'),
          axisV: _vectorFrom(cj['axisV'], 'conic.axisV'),
          quadraticX: _num(cj, 'quadraticX'),
          quadraticXY: _num(cj, 'quadraticXY'),
          quadraticY: _num(cj, 'quadraticY'),
          linearX: _num(cj, 'linearX'),
          linearY: _num(cj, 'linearY'),
          constant: _num(cj, 'constant'),
        );
      }
      return Object3D.curve(
        points: vertices,
        curveStarts: (j['curveStarts'] as List? ?? const []).cast<int>(),
        conic: conic,
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
      );
  }
}
