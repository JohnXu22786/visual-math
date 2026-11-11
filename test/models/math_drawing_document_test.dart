import 'dart:convert';

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

MathDrawingSnapshot snapshot() => MathDrawingSnapshot(
  formulas: [
    FormulaEntry(
      id: 'f-17',
      rawExpression: r' x^2 + a ',
      color: const Color(0xFF123456),
      autoColor: false,
      visible: false,
      parameterValues: const {'a': 2.5},
    ),
  ],
  parameters: {'a': MathParameter(value: 2.5, min: -4, max: 8, step: 0.5)},
  activeView: ViewMode.mode3D,
  activeTool: ConstructionTool.point,
  viewport2D: const Viewport(xMin: -3, yMin: -4, xMax: 5, yMax: 6),
  camera3D: const Camera3D(
    target: Point3D(1, 2, 3),
    distance: 17,
    theta: 0.4,
    phi: 0.8,
  ),
  projection3D: ProjectionType.perspective,
  showAxes3D: false,
  showPlane3D: true,
  showGrid3D: true,
  showLabels3D: false,
  scene3D: [
    Object3D.sphere(
      center: const Point3D(2, 3, 4),
      radius: 6,
      color: 0xFFABCDEF,
      opacity: 0.4,
      label: 'sphere',
    ).copyWith(visible: false),
  ],
);

void main() {
  test('round trips editable 2D and 3D drawing state', () {
    final doc = MathDrawingDocument(
      name: 'study',
      drawing: snapshot(),
      extensions: const {
        'vendor': {'flag': true},
      },
    );
    final decoded = MathDrawingDocument.decode(doc.encode());
    final s = decoded.drawing;
    expect(decoded.extensions['vendor'], {'flag': true});
    expect(s.formulas.single.id, 'f-17');
    expect(s.formulas.single.rawExpression, r' x^2 + a ');
    expect(s.formulas.single.autoColor, isFalse);
    expect(s.formulas.single.color, const Color(0xFF123456));
    expect(s.formulas.single.parameterValues['a'], 2.5);
    expect(s.parameters['a']!.min, -4);
    expect(s.viewport2D.xMax, 5);
    expect(s.camera3D.target, const Point3D(1, 2, 3));
    expect(s.camera3D.distance, 17);
    expect(s.projection3D, ProjectionType.perspective);
    expect(
      [s.showAxes3D, s.showPlane3D, s.showGrid3D, s.showLabels3D],
      [false, true, true, false],
    );
    final sphere = s.scene3D.single;
    expect(sphere.type, Object3DType.sphere);
    expect(sphere.sphereCenter, const Point3D(2, 3, 4));
    expect(sphere.sphereRadius, 6);
    expect(sphere.color, 0xFFABCDEF);
    expect(sphere.opacity, 0.4);
    expect(sphere.visible, isFalse);
  });

  test('rejects unsupported versions and malformed required state', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    json['version'] = 99;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
    json['version'] = 1;
    (json['drawing'] as Map<String, dynamic>)['view'] = 'futureView';
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });
}
