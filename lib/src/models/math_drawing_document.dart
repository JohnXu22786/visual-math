import 'dart:convert';

import 'package:flutter/material.dart' hide Viewport;

import 'formula_entry.dart';
import 'math_3d_object.dart';
import 'math_3d_relationship.dart';
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
    final MathDrawingSnapshot drawingSnapshot;
    try {
      drawingSnapshot = _snapshotFromJson(drawing);
    } on FormatException {
      rethrow;
    } on TypeError catch (error) {
      throw FormatException('Drawing data is malformed: $error');
    } on ArgumentError catch (error) {
      throw FormatException('Drawing data is malformed: $error');
    }
    return MathDrawingDocument(
      name: rawName,
      drawing: drawingSnapshot,
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
        'domainStart': s.formulas[i].domainStartExpression ?? '',
        'domainEnd': s.formulas[i].domainEndExpression ?? '',
        'includeDomainStart': s.formulas[i].includeDomainStart,
        'includeDomainEnd': s.formulas[i].includeDomainEnd,
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
  'polygonSides3D': s.polygonSides3D,
  'view2D': {
    'showAxes': s.showAxes2D,
    'showGrid': s.showGrid2D,
    'showZeros': s.showZeros2D,
    'showExtrema': s.showExtrema2D,
  },
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
    'objects': [
      for (var i = 0; i < s.scene3D.length; i++)
        _objectToJson(
          s.scene3D[i],
          s.scene3D[i].documentId.isEmpty
              ? 'object-$i'
              : s.scene3D[i].documentId,
        ),
    ],
    'pointAttachments': [
      for (final relationship in s.pointAttachments3D)
        {'pointId': relationship.pointId, 'targetId': relationship.targetId},
    ],
    'constructionDependencies': [
      for (final dependency in s.constructionDependencies3D)
        {
          'objectId': dependency.objectId,
          'tool': dependency.tool.name,
          'inputPoints': [for (final p in dependency.inputPoints) _point(p)],
          'sourcePointIds': dependency.sourcePointIds,
          'workingPlaneNormal': _vector(dependency.workingPlaneNormal),
          'polygonSides': dependency.polygonSides,
        },
    ],
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
        domainStartExpression: _optional<String>(f, 'domainStart', ''),
        domainEndExpression: _optional<String>(f, 'domainEnd', ''),
        includeDomainStart: _optional<bool>(f, 'includeDomainStart', true),
        includeDomainEnd: _optional<bool>(f, 'includeDomainEnd', true),
        parameterValues: _doubleMap(f['parameterValues']),
      ),
  ];
  final formulaIds = formulas.map((formula) => formula.id).toSet();
  if (formulaIds.length != formulas.length ||
      formulas.any((formula) => formula.id.isEmpty)) {
    throw const FormatException(
      'Formula row IDs must be non-empty and unique.',
    );
  }
  final parameterJson = obj(j['parameters'], 'parameters');
  final parameters = <String, MathParameter>{};
  parameterJson.forEach((key, value) {
    final p = obj(value, 'parameters.$key');
    final parameterValue = _num(p, 'value');
    final min = _num(p, 'min');
    final max = _num(p, 'max');
    if (parameterValue < min || parameterValue > max) {
      throw FormatException(
        'Parameter "$key" value must be within its saved slider range.',
      );
    }
    parameters[key] = MathParameter(
      value: parameterValue,
      min: min,
      max: max,
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
  final polygonSides3D = _optional<int>(j, 'polygonSides3D', 6);
  if (polygonSides3D < 3 || polygonSides3D > 12) {
    throw const FormatException(
      '3D polygon side count must be between 3 and 12.',
    );
  }
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
  final v2 = j['view2D'] == null
      ? const <String, dynamic>{}
      : obj(j['view2D'], 'view2D');
  final camera = obj(v3['camera'], 'view3D.camera');
  final target = _pointFrom(camera['target'], 'view3D.camera.target');
  final cameraDistance = _num(camera, 'distance');
  if (cameraDistance <= 0) {
    throw const FormatException('3D camera distance must be positive.');
  }
  final projection = ProjectionType.values
      .where((e) => e.name == v3['projection'])
      .firstOrNull;
  if (projection == null) throw const FormatException('Unknown 3D projection.');
  final objects = [
    for (final (index, object) in list(v3['objects'], 'view3D.objects').indexed)
      _objectFromJson(object, 'object-$index'),
  ];
  final ids = objects.map((object) => object.documentId).toSet();
  final objectsById = {for (final object in objects) object.documentId: object};
  if (ids.length != objects.length ||
      objects.any((object) => object.documentId.isEmpty)) {
    throw const FormatException('3D object IDs must be non-empty and unique.');
  }
  final attachments = [
    for (final relation in list(
      v3['pointAttachments'] ?? const <dynamic>[],
      'view3D.pointAttachments',
    ))
      PointAttachment(
        pointId: _required<String>(relation, 'pointId'),
        targetId: _required<String>(relation, 'targetId'),
      ),
  ];
  final dependencies = [
    for (final dependency in list(
      v3['constructionDependencies'] ?? const <dynamic>[],
      'view3D.constructionDependencies',
    ))
      _dependencyFromJson(dependency),
  ];
  for (final attachment in attachments) {
    if (!ids.contains(attachment.pointId) ||
        !ids.contains(attachment.targetId) ||
        objectsById[attachment.pointId]?.type != Object3DType.point) {
      throw const FormatException(
        'Point attachment references an unknown object ID.',
      );
    }
  }
  for (final dependency in dependencies) {
    if (!ids.contains(dependency.objectId) ||
        dependency.polygonSides < 3 ||
        dependency.polygonSides > 12 ||
        dependency.sourcePointIds.any(
          (id) =>
              id != null &&
              (!ids.contains(id) ||
                  objectsById[id]?.type != Object3DType.point),
        )) {
      throw const FormatException(
        'Construction dependency references an unknown object ID.',
      );
    }
  }
  return MathDrawingSnapshot(
    formulas: formulas,
    parameters: parameters,
    activeView: view,
    activeTool: tool,
    polygonSides3D: polygonSides3D,
    viewport2D: viewport,
    camera3D: Camera3D(
      target: target,
      distance: cameraDistance,
      theta: _num(camera, 'theta'),
      phi: _num(camera, 'phi'),
    ),
    projection3D: projection,
    showAxes3D: _required<bool>(v3, 'showAxes'),
    showPlane3D: _required<bool>(v3, 'showPlane'),
    showGrid3D: _required<bool>(v3, 'showGrid'),
    showLabels3D: _required<bool>(v3, 'showLabels'),
    scene3D: objects,
    showAxes2D: _optional<bool>(v2, 'showAxes', true),
    showGrid2D: _optional<bool>(v2, 'showGrid', true),
    showZeros2D: _optional<bool>(v2, 'showZeros', false),
    showExtrema2D: _optional<bool>(v2, 'showExtrema', false),
    pointAttachments3D: attachments,
    constructionDependencies3D: dependencies,
  );
}

T _required<T>(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is! T)
    throw FormatException('Required field "$k" is missing or invalid.');
  return v;
}

T _optional<T>(Map<String, dynamic> m, String k, T fallback) {
  if (!m.containsKey(k)) return fallback;
  final value = m[k];
  if (value is! T) {
    throw FormatException('Optional field "$k" is invalid.');
  }
  return value;
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

ConstructionDependency _dependencyFromJson(Map<String, dynamic> json) {
  final tool = ConstructionTool.values
      .where((value) => value.name == json['tool'])
      .firstOrNull;
  if (tool == null)
    throw const FormatException('Unknown construction dependency tool.');
  final inputPoints = json['inputPoints'];
  final sourceIds = json['sourcePointIds'];
  if (inputPoints is! List ||
      sourceIds is! List ||
      inputPoints.length != sourceIds.length) {
    throw const FormatException(
      'Construction dependency inputs are malformed.',
    );
  }
  if (sourceIds.any((id) => id != null && id is! String)) {
    throw const FormatException(
      'Construction dependency source IDs are malformed.',
    );
  }
  return ConstructionDependency(
    objectId: _required<String>(json, 'objectId'),
    tool: tool,
    inputPoints: [
      for (final point in inputPoints)
        _pointFrom(point, 'dependency.inputPoints'),
    ],
    sourcePointIds: sourceIds.cast<String?>(),
    workingPlaneNormal: _vectorFrom(
      json['workingPlaneNormal'],
      'dependency.workingPlaneNormal',
    ),
    polygonSides: _required<int>(json, 'polygonSides'),
  );
}

Map<String, dynamic> _objectToJson(Object3D o, String id) => {
  'id': id,
  'type': o.type.name,
  if (o.formulaRowId != null) 'formulaRowId': o.formulaRowId,
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
Object3D _objectFromJson(Map<String, dynamic> j, String fallbackId) {
  final type = Object3DType.values
      .where((e) => e.name == j['type'])
      .firstOrNull;
  if (type == null) throw const FormatException('Unsupported 3D object type.');
  final color = _required<int>(j, 'color'),
      opacity = _num(j, 'opacity'),
      label = j['label'] as String?,
      edgeWidth = _num(j, 'edgeWidth');
  final showEdges = _required<bool>(j, 'showEdges');
  final rawVertices = j['vertices'];
  final rawIndices = j['indices'];
  if (type == Object3DType.curve &&
      (rawVertices is! List || rawVertices.isEmpty)) {
    throw const FormatException(
      'Curve geometry must contain at least one point.',
    );
  }
  if ((type == Object3DType.surface || type == Object3DType.polyhedron) &&
      (rawVertices is! List ||
          rawIndices is! List ||
          rawVertices.length < 3 ||
          rawIndices.length < 3)) {
    throw const FormatException('Mesh geometry is missing required triangles.');
  }
  final vertices = (j['vertices'] as List? ?? const [])
      .map((p) => _pointFrom(p, 'object.vertices'))
      .toList();
  final indices = (j['indices'] as List? ?? const [])
      .map((v) => v as int)
      .toList();
  final normals = (j['normals'] as List? ?? const [])
      .map((v) => _vectorFrom(v, 'object.normals'))
      .toList();
  final curveStarts = (j['curveStarts'] as List? ?? const [])
      .map((value) => value as int)
      .toList();
  if (type == Object3DType.curve &&
      (curveStarts.any((start) => start <= 0 || start >= vertices.length) ||
          curveStarts.toSet().length != curveStarts.length ||
          curveStarts.asMap().entries.any(
            (entry) =>
                entry.key > 0 && curveStarts[entry.key - 1] >= entry.value,
          ))) {
    throw const FormatException('Curve branch indices are invalid.');
  }
  if ((type == Object3DType.surface || type == Object3DType.polyhedron) &&
      (indices.length % 3 != 0 ||
          indices.any((index) => index < 0 || index >= vertices.length))) {
    throw const FormatException('Mesh triangle indices are invalid.');
  }
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
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
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
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
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
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
    case Object3DType.surface:
      return Object3D.surface(
        vertices: vertices,
        indices: indices,
        normals: normals,
        color: color,
        opacity: opacity,
        edgeWidth: edgeWidth,
        showEdges: showEdges,
        label: label,
      ).copyWith(
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
    case Object3DType.sphere:
      return Object3D.sphere(
        center: _pointFrom(j['sphereCenter'], 'object.sphereCenter'),
        radius: _num(j, 'sphereRadius'),
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
    case Object3DType.polyhedron:
      return Object3D.polyhedron(
        vertices: vertices,
        indices: indices,
        color: color,
        opacity: opacity,
        edgeWidth: edgeWidth,
        showEdges: showEdges,
        label: label,
      ).copyWith(
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
    case Object3DType.vector:
      return Object3D.vectorObj(
        vector: _vectorFrom(j['vector'], 'object.vector'),
        origin: _pointFrom(j['point'], 'object.point'),
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
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
        curveStarts: curveStarts,
        conic: conic,
        color: color,
        opacity: opacity,
        label: label,
      ).copyWith(
        documentId: _optional<String>(j, 'id', fallbackId),
        formulaRowId: j['formulaRowId'] as String?,
        visible: _required<bool>(j, 'visible'),
        transformOrigin: _required<bool>(j, 'transformOrigin'),
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
  }
}
