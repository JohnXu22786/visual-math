import 'dart:convert';

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

MathDrawingSnapshot snapshot({
  List<FormulaEntry>? formulas,
  List<Object3D>? scene,
  List<ConstructionDependency>? dependencies,
  List<PointAttachment>? attachments,
}) => MathDrawingSnapshot(
  formulas: formulas ?? [
    FormulaEntry(
      id: 'f-17',
      rawExpression: r' x^2 + a ',
      color: const Color(0xFF123456),
      autoColor: false,
      visible: false,
      domainStartExpression: r'-2\pi',
      domainEndExpression: 'a + 1',
      includeDomainStart: false,
      includeDomainEnd: true,
      parameterValues: const {'a': 2.5},
    ),
    FormulaEntry(
      id: 'f-auto',
      rawExpression: r'\sin(x)',
      color: const Color(0xFF0088CC),
      autoColor: true,
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
  showAxes2D: false,
  showGrid2D: true,
  showZeros2D: false,
  showExtrema2D: true,
  polygonSides3D: 8,
  scene3D:
      scene ??
      [
        Object3D.sphere(
          center: const Point3D(2, 3, 4),
          radius: 6,
          color: 0xFFABCDEF,
          opacity: 0.4,
          label: 'sphere',
        ).copyWith(
          documentId: 'sphere-id',
          visible: false,
          edgeWidth: 4.5,
          showEdges: false,
        ),
        Object3D.point(
          const Point3D(1, 2, 3),
        ).copyWith(documentId: 'point-id', edgeWidth: 3.25, showEdges: false),
        Object3D.surface(
          vertices: const [
            Point3D(0, 0, 0),
            Point3D(1, 0, 0),
            Point3D(0, 1, 0),
          ],
          indices: const [0, 1, 2],
        ).copyWith(documentId: 'surface-id'),
      ],
  constructionDependencies3D:
      dependencies ??
      [
        ConstructionDependency(
          objectId: 'sphere-id',
          tool: ConstructionTool.sphere,
          inputPoints: const [Point3D(1, 2, 3)],
          sourcePointIds: const ['point-id'],
          workingPlaneNormal: Vector3D.unitZ,
          polygonSides: 5,
        ),
      ],
  pointAttachments3D:
      attachments ??
      const [PointAttachment(pointId: 'point-id', targetId: 'sphere-id')],
);

void main() {
  test('assigns unique fallback IDs when saved IDs collide', () {
    final drawing = snapshot(
      formulas: const [
        FormulaEntry(rawExpression: 'x'),
        FormulaEntry(id: 'formula-0', rawExpression: 'y'),
        FormulaEntry(id: 'formula-0-1', rawExpression: 'z'),
      ],
      scene: [
        Object3D.point(const Point3D(0, 0, 0)),
        Object3D.point(const Point3D(1, 0, 0)).copyWith(documentId: 'object-0'),
        Object3D.point(const Point3D(2, 0, 0)).copyWith(
          documentId: 'object-0-1',
        ),
      ],
      attachments: const [],
      dependencies: const [],
    );

    final decoded = MathDrawingDocument.decode(
      MathDrawingDocument(name: 'colliding IDs', drawing: drawing).encode(),
    );

    expect(decoded.drawing.formulas.map((formula) => formula.id).toSet(), {
      'formula-0',
      'formula-0-1',
      'formula-0-2',
    });
    expect(decoded.drawing.scene3D.map((object) => object.documentId).toSet(), {
      'object-0',
      'object-0-1',
      'object-0-2',
    });
  });

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
    final formula = s.formulas.first;
    expect(formula.id, 'f-17');
    expect(formula.rawExpression, r' x^2 + a ');
    expect(formula.autoColor, isFalse);
    expect(formula.color, const Color(0xFF123456));
    expect(formula.domainStartExpression, r'-2\pi');
    expect(formula.domainEndExpression, 'a + 1');
    expect(
      [formula.includeDomainStart, formula.includeDomainEnd],
      [false, true],
    );
    expect(formula.parameterValues['a'], 2.5);
    expect(s.formulas.last.autoColor, isTrue);
    expect(s.formulas.last.color, const Color(0xFF0088CC));
    expect(s.parameters['a']!.min, -4);
    expect(s.viewport2D.xMax, 5);
    expect(
      [s.showAxes2D, s.showGrid2D, s.showZeros2D, s.showExtrema2D],
      [false, true, false, true],
    );
    expect(s.camera3D.target, const Point3D(1, 2, 3));
    expect(s.camera3D.distance, 17);
    expect(s.projection3D, ProjectionType.perspective);
    expect(
      [s.showAxes3D, s.showPlane3D, s.showGrid3D, s.showLabels3D],
      [false, true, true, false],
    );
    final sphere = s.scene3D.first;
    expect(sphere.documentId, 'sphere-id');
    expect(sphere.type, Object3DType.sphere);
    expect(sphere.sphereCenter, const Point3D(2, 3, 4));
    expect(sphere.sphereRadius, 6);
    expect(sphere.color, 0xFFABCDEF);
    expect(sphere.opacity, 0.4);
    expect(sphere.visible, isFalse);
    expect(sphere.edgeWidth, 4.5);
    expect(sphere.showEdges, isFalse);
    expect(s.scene3D[1].edgeWidth, 3.25);
    expect(s.scene3D[1].showEdges, isFalse);
    expect(s.pointAttachments3D.single.pointId, 'point-id');
    expect(s.polygonSides3D, 8);
    final dependency = s.constructionDependencies3D.single;
    expect(dependency.objectId, 'sphere-id');
    expect(dependency.sourcePointIds, ['point-id']);
    expect(dependency.inputPoints, [const Point3D(1, 2, 3)]);
  });

  test('rejects unsupported versions and malformed required state', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    json['version'] = 99;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    json['version'] = 1;
    (json['drawing'] as Map<String, dynamic>)['polygonSides3D'] = 99;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
    (json['drawing'] as Map<String, dynamic>)['view'] = 'futureView';
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('rejects dangling construction references', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final view3D = drawing['view3D'] as Map<String, dynamic>;
    final deps = view3D['constructionDependencies'] as List<dynamic>;
    (deps.single as Map<String, dynamic>)['sourcePointIds'] = ['missing'];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test(
    'rejects a construction dependency attached to the wrong object type',
    () {
      final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
      final drawing = json['drawing'] as Map<String, dynamic>;
      final view3D = drawing['view3D'] as Map<String, dynamic>;
      final dependency =
          (view3D['constructionDependencies'] as List<dynamic>).single
              as Map<String, dynamic>;
      dependency['objectId'] = 'point-id';
      dependency['tool'] = ConstructionTool.polygon.name;

      expect(
        () => MathDrawingDocument.decode(jsonEncode(json)),
        throwsFormatException,
      );

      dependency['tool'] = ConstructionTool.move.name;
      expect(
        () => MathDrawingDocument.decode(jsonEncode(json)),
        throwsFormatException,
      );
    },
  );

  test('round trips a valid polygon construction dependency', () {
    final scene = [
      Object3D.point(const Point3D(0, 0, 0)).copyWith(documentId: 'p1'),
      Object3D.point(const Point3D(1, 0, 0)).copyWith(documentId: 'p2'),
      Object3D.point(const Point3D(0, 1, 0)).copyWith(documentId: 'p3'),
      Object3D.polyhedron(
        vertices: const [Point3D(0, 0, 0), Point3D(1, 0, 0), Point3D(0, 1, 0)],
        indices: const [0, 1, 2],
      ).copyWith(documentId: 'polygon-id'),
    ];
    final drawing = snapshot(
      scene: scene,
      attachments: const [],
      dependencies: [
        ConstructionDependency(
          objectId: 'polygon-id',
          tool: ConstructionTool.polygon,
          inputPoints: const [
            Point3D(0, 0, 0),
            Point3D(1, 0, 0),
            Point3D(0, 1, 0),
          ],
          sourcePointIds: const ['p1', 'p2', 'p3'],
          workingPlaneNormal: Vector3D.unitZ,
          polygonSides: 6,
        ),
      ],
    );

    final decoded = MathDrawingDocument.decode(
      MathDrawingDocument(name: 'polygon', drawing: drawing).encode(),
    );
    expect(decoded.drawing.scene3D.last.type, Object3DType.polyhedron);
    expect(
      decoded.drawing.constructionDependencies3D.single.tool,
      ConstructionTool.polygon,
    );
  });

  test('rejects relationships that point to non-point objects', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final view3D = drawing['view3D'] as Map<String, dynamic>;
    final attachments = view3D['pointAttachments'] as List<dynamic>;
    (attachments.single as Map<String, dynamic>)['pointId'] = 'sphere-id';
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    (attachments.single as Map<String, dynamic>)['pointId'] = 'point-id';
    final dependencies = view3D['constructionDependencies'] as List<dynamic>;
    (dependencies.single as Map<String, dynamic>)['sourcePointIds'] = [
      'sphere-id',
    ];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    (dependencies.single as Map<String, dynamic>)['sourcePointIds'] = [
      'point-id',
    ];
    (dependencies.single as Map<String, dynamic>)['polygonSides'] = 99;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('rejects malformed object values and invalid camera distance', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final view3D = drawing['view3D'] as Map<String, dynamic>;
    final objects = view3D['objects'] as List<dynamic>;
    (objects.first as Map<String, dynamic>)['indices'] = ['bad-index'];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    (objects.first as Map<String, dynamic>)['indices'] = [];
    final camera = view3D['camera'] as Map<String, dynamic>;
    camera['distance'] = 0;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    camera['distance'] = 6;
    final parameters = drawing['parameters'] as Map<String, dynamic>;
    final parameter = parameters['a'] as Map<String, dynamic>;
    parameter['min'] = 12.0;
    parameter['max'] = 8.0;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('rejects parameter values outside their saved slider ranges', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final parameters = drawing['parameters'] as Map<String, dynamic>;
    (parameters['a'] as Map<String, dynamic>)['value'] = 10.0;
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test(
    'opens version 1 drawings written before persistence fields were added',
    () {
      final json = MathDrawingDocument(
        name: 'legacy',
        drawing: snapshot(),
      ).toJson();
      final drawing = json['drawing'] as Map<String, dynamic>;
      for (final formula in drawing['formulas'] as List<dynamic>) {
        final fields = formula as Map<String, dynamic>;
        fields.remove('domainStart');
        fields.remove('domainEnd');
        fields.remove('includeDomainStart');
        fields.remove('includeDomainEnd');
      }
      drawing.remove('view2D');
      drawing.remove('polygonSides3D');
      final view3D = drawing['view3D'] as Map<String, dynamic>;
      view3D.remove('pointAttachments');
      view3D.remove('constructionDependencies');
      for (final object in view3D['objects'] as List<dynamic>) {
        (object as Map<String, dynamic>).remove('id');
      }

      final decoded = MathDrawingDocument.decode(jsonEncode(json)).drawing;
      expect(decoded.formulas.first.domainStartExpression, '');
      expect(decoded.formulas.first.includeDomainStart, isTrue);
      expect(decoded.polygonSides3D, 6);
      expect(decoded.showAxes2D, isTrue);
      expect(decoded.showGrid2D, isTrue);
      expect(decoded.showZeros2D, isFalse);
      expect(decoded.showExtrema2D, isFalse);
      expect(decoded.scene3D.map((object) => object.documentId), [
        'object-0',
        'object-1',
        'object-2',
      ]);
      expect(decoded.pointAttachments3D, isEmpty);
      expect(decoded.constructionDependencies3D, isEmpty);
    },
  );

  test('rejects mesh indices that cannot describe stored vertices', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final view3D = drawing['view3D'] as Map<String, dynamic>;
    final objects = view3D['objects'] as List<dynamic>;
    final surface = objects.last as Map<String, dynamic>;
    surface['indices'] = [0, 1, 3];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
    surface['indices'] = [0, 1];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('round trips a curve with a single sampled point', () {
    final points = Expression3D.parametricCurve(
      '(t, sqrt(-t), 0)',
      tMin: 0,
      tMax: 1,
    ).sampleCurve();
    expect(points, [Point3D.origin]);
    final drawing = snapshot(
      scene: [
        ...snapshot().scene3D,
        Object3D.curve(points: points),
      ],
    );

    final decoded = MathDrawingDocument.decode(
      MathDrawingDocument(name: 'curve', drawing: drawing).encode(),
    );
    expect(decoded.drawing.scene3D.last.type, Object3DType.curve);
    expect(decoded.drawing.scene3D.last.vertices, points);
  });

  test('round trips a sampled formula surface with no triangles', () {
    final surface = Object3D.surface(
      vertices: const [Point3D(0, 0, 0)],
      indices: const [],
      label: 'sqrt(A-x*x-y*y)',
    ).copyWith(documentId: 'plot', formulaRowId: 'f-17');
    final document = MathDrawingDocument(
      name: 'partial',
      drawing: snapshot(scene: [...snapshot().scene3D, surface]),
    );
    final restored = MathDrawingDocument.decode(document.encode())
        .drawing
        .scene3D
        .singleWhere((o) => o.documentId == 'plot');
    expect(restored.vertices, hasLength(1));
    expect(restored.indices, isEmpty);
    expect(restored.formulaRowId, 'f-17');
  });

  test('serializes a very large flat sampled surface with finite normals', () {
    final mesh = SurfaceMesh.fromFunction(
      xMin: 0,
      xMax: 1e155,
      yMin: 0,
      yMax: 1e155,
      gridX: 1,
      gridY: 1,
      f: (_, _) => 0,
    );
    expect(mesh.vertices, hasLength(4));
    expect(mesh.indices, hasLength(6));
    for (final normal in mesh.normals) {
      expect(
        normal.x.isFinite && normal.y.isFinite && normal.z.isFinite,
        isTrue,
      );
      expect(normal.z, greaterThan(0));
    }

    final document = MathDrawingDocument(
      name: 'large flat mesh',
      drawing: snapshot(
        scene: [
          ...snapshot().scene3D,
          Object3D.surface(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
          ),
        ],
      ),
    );
    final encoded = document.encode();
    final restored = MathDrawingDocument.decode(encoded);
    expect(restored.drawing.scene3D.last.normals, mesh.normals);
  });

  test('serializes finite mesh vertices whose edge differences overflow', () {
    final mesh = SurfaceMesh.fromFunction(
      xMin: 0,
      xMax: 1e-200,
      yMin: 0,
      yMax: 1e-200,
      gridX: 1,
      gridY: 1,
      f: (x, y) => x == 0 && y == 0 ? -1e308 : 1e308,
    );
    expect(mesh.vertices, hasLength(4));
    expect(mesh.indices, hasLength(6));
    for (final normal in mesh.normals) {
      expect(
        normal.x.isFinite && normal.y.isFinite && normal.z.isFinite,
        isTrue,
      );
      expect(normal.magnitude, closeTo(1, 1e-10));
    }

    final document = MathDrawingDocument(
      name: 'large elevation mesh',
      drawing: snapshot(
        scene: [
          ...snapshot().scene3D,
          Object3D.surface(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
          ),
        ],
      ),
    );
    final restored = MathDrawingDocument.decode(document.encode());
    expect(restored.drawing.scene3D.last.normals, mesh.normals);
  });

  test('rejects mesh and curve objects with missing geometry', () {
    final json = MathDrawingDocument(name: 'x', drawing: snapshot()).toJson();
    final drawing = json['drawing'] as Map<String, dynamic>;
    final view3D = drawing['view3D'] as Map<String, dynamic>;
    final objects = view3D['objects'] as List<dynamic>;
    final mesh = objects.last as Map<String, dynamic>;
    mesh['vertices'] = [];
    mesh['indices'] = [0, 0, 0];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    mesh.remove('vertices');
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    mesh['type'] = Object3DType.curve.name;
    mesh['indices'] = [];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(json)),
      throwsFormatException,
    );

    final curveJson = MathDrawingDocument(
      name: 'curve',
      drawing: snapshot(),
    ).toJson();
    final curveDrawing = curveJson['drawing'] as Map<String, dynamic>;
    final curveView = curveDrawing['view3D'] as Map<String, dynamic>;
    final curve =
        (curveView['objects'] as List<dynamic>).first as Map<String, dynamic>;
    curve['type'] = Object3DType.curve.name;
    curve['vertices'] = [
      {'x': 0.0, 'y': 0.0, 'z': 0.0},
      {'x': 1.0, 'y': 1.0, 'z': 0.0},
    ];
    curve['curveStarts'] = [999];
    expect(
      () => MathDrawingDocument.decode(jsonEncode(curveJson)),
      throwsFormatException,
    );
  });
}
