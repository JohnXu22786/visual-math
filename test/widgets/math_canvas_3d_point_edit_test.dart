import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

Future<void> _expectPlanarArrowsFollowAxes(
  WidgetTester tester, {
  required Camera3D camera,
  required ProjectionType projectionType,
  required Point3D point,
}) async {
  const size = Size(800, 600);
  final projection = projectionType == ProjectionType.parallel
      ? Projection3D.parallel(
          width: size.width,
          height: size.height,
          scale: camera.distance * 0.6,
        )
      : Projection3D.perspective(
          width: size.width,
          height: size.height,
          fov: 60,
        );
  final center = worldToScreen(point, camera, projection);
  final origin = Offset(center.x, center.y);
  final sampleDistance = projectionType == ProjectionType.perspective
      ? 0.01
      : 1.0;

  Offset axisOffset(Vector3D axis) {
    final screenPoint = worldToScreen(
      point + axis * sampleDistance,
      camera,
      projection,
    );
    final projectedAxis = Offset(
      screenPoint.x - center.x,
      screenPoint.y - center.y,
    );
    return projectedAxis / projectedAxis.distance * 28;
  }

  final xAxis = axisOffset(Vector3D.unitX);
  final yAxis = axisOffset(Vector3D.unitY);
  final painter = MathCanvas3DPainter(
    cameraTarget: camera.target,
    cameraDistance: camera.distance,
    cameraTheta: camera.theta,
    cameraPhi: camera.phi,
    projectionType: projectionType,
    showAxes: false,
    showPlane: false,
    showGrid: false,
    showLabels: false,
    selectedPoint: Object3D.point(point),
    pointDragMode: PointDragMode.plane,
  );
  final pixels = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    image.dispose();

    final result = <Offset>[];
    for (var y = 0; y < size.height; y++) {
      for (var x = 0; x < size.width; x++) {
        final index = (y * size.width.toInt() + x) * 4;
        final red = bytes[index];
        final green = bytes[index + 1];
        final blue = bytes[index + 2];
        if (red > 100 && green < 140 && blue > 100) {
          result.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    return result;
  });

  expect(pixels, isNotNull);
  for (final direction in [xAxis, -xAxis, yAxis, -yAxis]) {
    final expectedArrowPoint = origin + direction * (20 / 28);
    expect(
      pixels!.any((pixel) => (pixel - expectedArrowPoint).distance < 2),
      isTrue,
      reason: 'Expected an arrow along projected direction $direction',
    );
  }
}

void main() {
  Future<MathCanvas3DState> setup(
    WidgetTester tester, {
    VoidCallback? onSceneChanged,
    void Function(MathCanvas3DState)? captureScene,
  }) async {
    final key = GlobalKey<MathCanvas3DState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathCanvas3D(
            key: key,
            currentTool: ConstructionTool.point,
            onSceneChanged: () {
              onSceneChanged?.call();
              captureScene?.call(key.currentState!);
            },
            onObjectCreated: (object) {
              key.currentState!.setObjects([
                ...key.currentState!.objects,
                object,
              ]);
              if (captureScene != null) key.currentState!.ensureDocumentIds();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  Offset screen(MathCanvas3DState state, Point3D point) {
    final projected = worldToScreen(
      point,
      state.camera,
      state.projectionType == ProjectionType.parallel
          ? Projection3D.parallel(
              width: 800,
              height: 600,
              scale: state.camera.distance * 0.6,
            )
          : Projection3D.perspective(width: 800, height: 600, fov: 60),
    );
    return Offset(projected.x, projected.y);
  }

  testWidgets('snapshot during creation retains point and construction links', (
    tester,
  ) async {
    var publishedDependencies = 0;
    var publishedAttachments = 0;
    var incompletePublication = false;
    final state = await setup(
      tester,
      captureScene: (canvas) {
        canvas.ensureDocumentIds();
        publishedDependencies = canvas.documentConstructionDependencies.length;
        publishedAttachments = canvas.documentPointAttachments.length;
        if (canvas.objects.any(
              (object) => object.type == Object3DType.polyhedron,
            ) &&
            publishedDependencies == 0) {
          incompletePublication = true;
        }
      },
    );
    const first = Point3D(-2, 0, 0);
    const second = Point3D(-1, 0, 0);
    state.setObjects([
      const Object3D.point(first),
      const Object3D.point(second),
    ]);
    state.setTool(ConstructionTool.tetrahedron);
    await tester.pump();
    await tester.tapAt(screen(state, first));
    await tester.pump();
    await tester.tapAt(screen(state, second));
    await tester.pump();
    expect(state.documentConstructionDependencies, hasLength(1));
    expect(publishedDependencies, 1);
    expect(incompletePublication, isFalse);

    state.setObjects([const Object3D.plane(c: 1, d: 0)]);
    state.setTool(ConstructionTool.pointOnObject);
    await tester.pump();
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(state.documentPointAttachments, hasLength(1));
    expect(state.selectedPoint, same(state.objects.last));
    expect(publishedAttachments, 1);
  });

  testWidgets('free point starts on z=0 even over an elevated surface', (
    tester,
  ) async {
    final state = await setup(tester);
    state.setObjects([const Object3D.plane(c: 1, d: 2)]);
    await tester.pump();
    await tester.tapAt(const Offset(340, 330));
    await tester.pump();
    expect(state.objects.last.point.z, 0);
    expect(state.selectedPoint, same(state.objects.last));
    expect(state.pointDragMode, PointDragMode.height);
  });

  testWidgets(
    'moving a source point updates its solid and deleting it preserves the solid',
    (tester) async {
      final state = await setup(tester);
      const first = Point3D(-2, 0, 0);
      const second = Point3D(-1, 0, 0);
      state.setObjects([
        const Object3D.point(first, label: 'A'),
        const Object3D.point(second, label: 'B'),
      ]);
      state.setTool(ConstructionTool.tetrahedron);
      await tester.pump();

      await tester.tapAt(screen(state, first));
      await tester.pump();
      await tester.tapAt(screen(state, second));
      await tester.pump();

      final initialSolid = state.objects.last;
      expect(initialSolid.type, Object3DType.polyhedron);
      expect(initialSolid.vertices[0], first);
      expect(initialSolid.vertices[1], second);

      state.setTool(ConstructionTool.move);
      await tester.pump();
      await tester.dragFrom(screen(state, first), const Offset(-45, 24));
      await tester.pump();

      final movedPoint = state.objects[0].point;
      final movedSolid = state.objects.last;
      expect(movedPoint.distanceTo(first), greaterThan(0.1));
      expect(movedSolid.vertices[0], movedPoint);
      expect(
        movedSolid.vertices[2].distanceTo(initialSolid.vertices[2]),
        greaterThan(0.1),
      );

      state.setTool(ConstructionTool.deleteObject);
      await tester.pump();
      await tester.tapAt(screen(state, movedPoint));
      await tester.pump();

      expect(state.objects, hasLength(2));
      expect(
        state.objects.any(
          (object) =>
              object.type == Object3DType.point && object.point == movedPoint,
        ),
        isFalse,
      );
      final preservedSolid = state.objects.singleWhere(
        (object) => object.type == Object3DType.polyhedron,
      );
      expect(preservedSolid.vertices, movedSolid.vertices);
    },
  );

  testWidgets('moving source points refreshes measurement labels', (
    tester,
  ) async {
    for (final tool in [ConstructionTool.distance, ConstructionTool.angle]) {
      final state = await setup(tester);
      const points = [Point3D(-2, 0, 0), Point3D(-1, 0, 0), Point3D(-1, 1, 0)];
      final count = tool == ConstructionTool.distance ? 2 : 3;
      state.setObjects(
        points.take(count).map((p) => Object3D.point(p)).toList(),
      );
      state.setTool(tool);
      await tester.pump();
      for (final point in points.take(count)) {
        await tester.tapAt(screen(state, point));
        await tester.pump();
      }
      final originalLabel = state.objects.last.label;
      state.setTool(ConstructionTool.move);
      await tester.pump();
      await tester.dragFrom(screen(state, points.first), const Offset(-45, 24));
      await tester.pump();

      final rebuilt = ConstructionState(tool: tool);
      for (final object in state.objects.take(count)) {
        rebuilt.addPoint(object.point);
      }
      expect(rebuilt.result!.label, isNot(originalLabel));
      expect(state.objects.last.label, rebuilt.result!.label);
      state.ensureDocumentIds();
      final document = MathDrawingDocument(
        name: 'measurement',
        drawing: MathDrawingSnapshot(
          formulas: const [],
          parameters: const {},
          activeView: ViewMode.mode3D,
          activeTool: ConstructionTool.move,
          viewport2D: Viewport.defaultViewport(),
          camera3D: state.camera,
          projection3D: state.projectionType,
          scene3D: state.objects,
          pointAttachments3D: state.documentPointAttachments,
          constructionDependencies3D: state.documentConstructionDependencies,
        ),
      );
      expect(
        MathDrawingDocument.decode(document.encode())
            .drawing
            .scene3D
            .last
            .label,
        rebuilt.result!.label,
      );
    }
  });

  testWidgets('restored construction dependencies remain editable', (
    tester,
  ) async {
    final original = await setup(tester);
    const first = Point3D(-2, 0, 0);
    const second = Point3D(-1, 0, 0);
    original.setObjects([
      const Object3D.point(first, label: 'A'),
      const Object3D.point(second, label: 'B'),
    ]);
    original.setTool(ConstructionTool.tetrahedron);
    await tester.pump();
    await tester.tapAt(screen(original, first));
    await tester.pump();
    await tester.tapAt(screen(original, second));
    await tester.pump();

    original.ensureDocumentIds();
    final document = MathDrawingDocument(
      name: 'construction',
      drawing: MathDrawingSnapshot(
        formulas: const [],
        parameters: const {},
        activeView: ViewMode.mode3D,
        activeTool: ConstructionTool.move,
        viewport2D: Viewport.defaultViewport(),
        camera3D: original.camera,
        projection3D: original.projectionType,
        scene3D: original.objects,
        pointAttachments3D: original.documentPointAttachments,
        constructionDependencies3D: original.documentConstructionDependencies,
      ),
    );
    final reopenedDocument = MathDrawingDocument.decode(document.encode());
    final reopenedSnapshot = reopenedDocument.drawing;
    final reopened = await setup(tester);
    reopened.setObjects(reopenedSnapshot.scene3D);
    reopened.restoreDocumentRelationships(
      pointAttachments: reopenedSnapshot.pointAttachments3D,
      constructionDependencies: reopenedSnapshot.constructionDependencies3D,
    );
    reopened.setTool(ConstructionTool.move);
    await tester.pump();
    final oldPoint = reopened.objects.first.point;
    final oldDerived = reopened.objects.last.vertices;
    await tester.dragFrom(screen(reopened, oldPoint), const Offset(-45, 24));
    await tester.pump();

    final movedPoint = reopened.objects.first.point;
    expect(movedPoint.distanceTo(oldPoint), greaterThan(0.1));
    expect(reopened.objects.last.vertices[0], movedPoint);
    expect(
      reopened.objects.last.vertices[2].distanceTo(oldDerived[2]),
      greaterThan(0.1),
    );
  });

  testWidgets(
    'restored construction and attachment chains follow a moved point',
    (tester) async {
      final state = await setup(tester);
      const a = Point3D(-2, 0, 0);
      const b = Point3D(2, 0, 0);
      const midpoint = Point3D(0, 0, 0);
      const attached = Point3D(1, 0, 0);
      state.setObjects([
        Object3D.point(a).copyWith(documentId: 'a'),
        Object3D.point(b).copyWith(documentId: 'b'),
        Object3D.point(midpoint).copyWith(documentId: 'm'),
        Object3D.line(midpoint, b).copyWith(documentId: 'segment'),
        Object3D.point(attached).copyWith(documentId: 'p'),
        Object3D.line(a, attached).copyWith(documentId: 'downstream'),
        Object3D.point(
          const Point3D(0, 1, 0),
          label: 'area',
        ).copyWith(documentId: 'area'),
        Object3D.point(const Point3D(0, 3, 0)).copyWith(documentId: 'c'),
        Object3D.curve(points: const [a, b, Point3D(0, 3, 0), a])
            .copyWith(documentId: 'curve'),
        Object3D.point(attached).copyWith(documentId: 'invalid-midpoint'),
      ]);
      ConstructionDependency dependency(
        String id,
        ConstructionTool tool,
        List<Point3D> points,
        List<String?> sources,
      ) => ConstructionDependency(
        objectId: id,
        tool: tool,
        inputPoints: points,
        sourcePointIds: sources,
        workingPlaneNormal: Vector3D.unitZ,
        polygonSides: 3,
      );
      state.restoreDocumentRelationships(
        pointAttachments: const [
          PointAttachment(pointId: 'p', targetId: 'segment'),
          PointAttachment(pointId: 'invalid-midpoint', targetId: 'segment'),
        ],
        // Intentionally reverse dependency order to exercise graph ordering.
        constructionDependencies: [
          dependency(
            'downstream',
            ConstructionTool.segment,
            [a, attached],
            ['a', 'p'],
          ),
          dependency(
            'segment',
            ConstructionTool.segment,
            [midpoint, b],
            ['m', 'b'],
          ),
          dependency('m', ConstructionTool.midpoint, [a, b], ['a', 'b']),
          dependency(
            'invalid-midpoint',
            ConstructionTool.midpoint,
            [a, a],
            ['a', 'a'],
          ),
          dependency(
            'curve',
            ConstructionTool.polyline,
            [a, b, const Point3D(0, 3, 0), a],
            ['a', 'b', 'c', null],
          ),
          dependency(
            'area',
            ConstructionTool.area,
            [a, b, const Point3D(0, 3, 0)],
            ['a', 'b', 'c'],
          ),
        ],
      );
      final document = MathDrawingDocument(
        name: 'chain',
        drawing: MathDrawingSnapshot(
          formulas: const [],
          parameters: const {},
          activeView: ViewMode.mode3D,
          activeTool: ConstructionTool.move,
          viewport2D: Viewport.defaultViewport(),
          camera3D: state.camera,
          projection3D: state.projectionType,
          scene3D: state.objects,
          pointAttachments3D: state.documentPointAttachments,
          constructionDependencies3D: state.documentConstructionDependencies,
        ),
      );
      final snapshot = MathDrawingDocument.decode(document.encode()).drawing;
      final reopened = await setup(tester);
      reopened.setObjects(snapshot.scene3D);
      reopened.restoreDocumentRelationships(
        pointAttachments: snapshot.pointAttachments3D,
        constructionDependencies: snapshot.constructionDependencies3D,
      );
      reopened.setTool(ConstructionTool.move);
      await tester.pump();
      await tester.dragFrom(screen(reopened, a), const Offset(-45, 24));
      await tester.pump();

      final movedA = reopened.objects[0].point;
      final movedMidpoint = reopened.objects[2].point;
      final movedAttached = reopened.objects[4].point;
      expect(movedA.distanceTo(a), greaterThan(0.1));
      expect(movedMidpoint, movedA.midpoint(b));
      expect(reopened.objects[3].pointA, movedMidpoint);
      expect(movedAttached.distanceTo(attached), greaterThan(0.001));
      expect(reopened.objects[5].pointA, movedA);
      expect(reopened.objects[5].pointB, movedAttached);
      expect(reopened.objects[6].label, startsWith('面积 '));
      expect(reopened.objects[8].vertices.first, movedA);
      expect(reopened.objects[8].vertices.last, movedA);
      expect(reopened.objects[9].point, movedAttached);
    },
  );
  testWidgets('attachment rejects targets constructed from the point', (
    tester,
  ) async {
    final state = await setup(tester);
    const a = Point3D(-2, 0, 0);
    const b = Point3D(2, 0, 0);
    state.setObjects([
      Object3D.point(a).copyWith(documentId: 'a'),
      Object3D.point(b).copyWith(documentId: 'b'),
      Object3D.line(a, b).copyWith(documentId: 'line'),
    ]);
    state.restoreDocumentRelationships(
      pointAttachments: const [],
      constructionDependencies: [
        ConstructionDependency(
          objectId: 'line',
          tool: ConstructionTool.line,
          inputPoints: [a, b],
          sourcePointIds: ['a', 'b'],
          workingPlaneNormal: Vector3D.unitZ,
          polygonSides: 3,
        ),
      ],
    );
    state.setTool(ConstructionTool.attachDetachPoint);
    await tester.pump();
    await tester.tapAt(screen(state, a));
    await tester.pump();
    await tester.tapAt(screen(state, Point3D.origin));
    await tester.pump();
    expect(state.documentPointAttachments, isEmpty);
  });

  testWidgets('cyclic construction relationships terminate on drag', (
    tester,
  ) async {
    final state = await setup(tester);
    const a = Point3D(-2, 0, 0);
    const b = Point3D(2, 0, 0);
    state.setObjects([
      Object3D.point(a).copyWith(documentId: 'a'),
      Object3D.point(b).copyWith(documentId: 'b'),
      Object3D.point(Point3D.origin).copyWith(documentId: 'm'),
    ]);
    ConstructionDependency midpoint(
      String id,
      List<Point3D> points,
      List<String> sources,
    ) => ConstructionDependency(
      objectId: id,
      tool: ConstructionTool.midpoint,
      inputPoints: points,
      sourcePointIds: sources,
      workingPlaneNormal: Vector3D.unitZ,
      polygonSides: 3,
    );
    state.restoreDocumentRelationships(
      pointAttachments: const [],
      constructionDependencies: [
        midpoint('m', [a, b], ['a', 'b']),
        midpoint('a', [Point3D.origin, b], ['m', 'b']),
      ],
    );
    state.setTool(ConstructionTool.move);
    await tester.pump();
    await tester.dragFrom(screen(state, a), const Offset(-45, 24));
    await tester.pump();
    expect(state.objects[0].point.distanceTo(a), greaterThan(0.1));
    expect(state.objects[2].point, state.objects[0].point.midpoint(b));
  });

  testWidgets('area follows its source vertices before and after reopening', (
    tester,
  ) async {
    final original = await setup(tester);
    const vertices = [Point3D(-2, 0, 0), Point3D(0, 0, 0), Point3D(0, 2, 0)];
    original.setObjects([for (final point in vertices) Object3D.point(point)]);
    original.setTool(ConstructionTool.area);
    await tester.pump();
    for (final point in [...vertices, vertices.first]) {
      await tester.tapAt(screen(original, point));
      await tester.pump();
    }
    expect(original.objects, hasLength(4));
    expect(original.objects.last.label, '面积 2.000');

    Future<void> moveAndCheck(MathCanvas3DState state) async {
      state.setTool(ConstructionTool.move);
      await tester.pump();
      final oldPoint = state.objects.first.point;
      final oldArea = state.objects.last;
      await tester.dragFrom(screen(state, oldPoint), const Offset(-45, 24));
      await tester.pump();
      expect(state.objects.first.point.distanceTo(oldPoint), greaterThan(0.1));
      expect(
        state.objects.last.point.distanceTo(oldArea.point),
        greaterThan(0.01),
      );
      expect(state.objects.last.label, isNot(oldArea.label));
    }

    await moveAndCheck(original);
    original.ensureDocumentIds();
    final document = MathDrawingDocument(
      name: 'area',
      drawing: MathDrawingSnapshot(
        formulas: const [],
        parameters: const {},
        activeView: ViewMode.mode3D,
        activeTool: ConstructionTool.move,
        viewport2D: Viewport.defaultViewport(),
        camera3D: original.camera,
        projection3D: original.projectionType,
        scene3D: original.objects,
        constructionDependencies3D: original.documentConstructionDependencies,
      ),
    );
    final snapshot = MathDrawingDocument.decode(document.encode()).drawing;
    final reopened = await setup(tester);
    reopened.setObjects(snapshot.scene3D);
    reopened.restoreDocumentRelationships(
      pointAttachments: snapshot.pointAttachments3D,
      constructionDependencies: snapshot.constructionDependencies3D,
    );
    await moveAndCheck(reopened);
  });

  testWidgets('replot keeps the source of a construction in progress', (
    tester,
  ) async {
    final state = await setup(tester);
    const point = Point3D(-2, 0, 0);
    state.setObjects([
      Object3D.surface(
        vertices: const [],
        indices: const [],
      ).copyWith(documentId: 'plot:1', formulaRowId: 'row'),
      Object3D.point(point).copyWith(documentId: 'p'),
    ]);
    state.setTool(ConstructionTool.segment);
    await tester.pump();
    await tester.tapAt(screen(state, point));
    await tester.pump();
    expect(state.constructionState!.points, [point]);
    state.replaceFormulaObjects([
      Object3D.surface(
        vertices: const [],
        indices: const [],
      ).copyWith(documentId: 'plot:1', formulaRowId: 'row'),
    ]);
    await tester.pump();
    await tester.tapAt(screen(state, const Point3D(2, 2, 0)));
    await tester.pump();
    expect(
      state.documentConstructionDependencies.single.sourcePointIds.first,
      'p',
    );
  });

  testWidgets('replot updates a moved source in an active construction', (
    tester,
  ) async {
    final state = await setup(tester);
    Object3D surface(double z) => Object3D.surface(
      vertices: [Point3D(-5, -5, z), Point3D(5, -5, z), Point3D(0, 5, z)],
      indices: const [0, 1, 2],
    ).copyWith(documentId: 'plot', formulaRowId: 'row');
    state.setObjects([
      surface(0),
      Object3D.point(Point3D.origin).copyWith(documentId: 'p'),
    ]);
    state.restoreDocumentRelationships(
      pointAttachments: const [PointAttachment(pointId: 'p', targetId: 'plot')],
      constructionDependencies: const [],
    );
    state.setTool(ConstructionTool.segment);
    await tester.pump();
    await tester.tapAt(screen(state, Point3D.origin));
    await tester.pump();
    state.replaceFormulaObjects([surface(1)]);
    await tester.pump();
    expect(
      state.objects.singleWhere((o) => o.documentId == 'p').point.z,
      closeTo(1, 1e-9),
    );
    expect(state.constructionState!.points.first.z, closeTo(1, 1e-9));
    await tester.tapAt(screen(state, const Point3D(2, 2, 0)));
    await tester.pump();
    final segment = state.objects.singleWhere(
      (o) => o.type == Object3DType.line,
    );
    expect(segment.pointA.z, closeTo(1, 1e-9));
  });

  testWidgets('a snapped solid vertex can begin a later construction', (
    tester,
  ) async {
    final state = await setup(tester);
    const vertex = Point3D(-2, 0, 0);
    state.setObjects([
      Object3D.polyhedron(
        vertices: const [
          vertex,
          Point3D(-1, 0, 0),
          Point3D(-2, 1, 0),
          Point3D(-2, 0, 1),
        ],
        indices: const [0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3],
      ),
    ]);
    state.setTool(ConstructionTool.segment);
    await tester.pump();

    await tester.tapAt(screen(state, vertex));
    await tester.pump();
    expect(state.constructionState!.points, [vertex]);

    const endpoint = Point3D(2, 2, 0);
    await tester.tapAt(screen(state, endpoint));
    await tester.pump();

    final segment = state.objects.singleWhere(
      (object) => object.type == Object3DType.line,
    );
    expect([segment.pointA, segment.pointB], contains(vertex));
  });

  testWidgets('clipped perspective points cannot intercept selection', (
    tester,
  ) async {
    final state = await setup(tester);
    state.setCamera(const Camera3D(theta: 0, phi: 0));
    state.setProjectionType(ProjectionType.perspective);
    state.setObjects([const Object3D.point(Point3D(0, 9.95, 0))]);
    state.setTool(ConstructionTool.move);
    await tester.pump();
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(state.selectedPoint, isNull);

    state.setTool(ConstructionTool.pointOnObject);
    await tester.pump();
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(state.objects, hasLength(1));
  });

  testWidgets('construction does not snap to a clipped point', (tester) async {
    final state = await setup(tester);
    state.setCamera(const Camera3D(theta: 0, phi: 0));
    state.setProjectionType(ProjectionType.perspective);
    const clipped = Point3D(0.001, 9.95, 0);
    state.setObjects([const Object3D.point(clipped)]);
    state.setTool(ConstructionTool.segment);
    await tester.pump();
    await tester.tapAt(screen(state, clipped));
    await tester.pump();
    await tester.tapAt(const Offset(500, 300));
    await tester.pump();
    final segment = state.objects.singleWhere(
      (object) => object.type == Object3DType.line,
    );
    expect(segment.pointA.distanceTo(clipped), greaterThan(0.1));
  });

  testWidgets('visible points beyond the parallel camera remain editable', (
    tester,
  ) async {
    final state = await setup(tester);
    state.setObjects([const Object3D.point(Point3D(0, 0, 12))]);
    await tester.pump();
    await tester.tap(find.byTooltip('3D 视图设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('俯视 xOy'));
    await tester.pumpAndSettle();
    final initial = state.objects.single.point;
    await tester.tapAt(screen(state, initial));
    await tester.pump();
    expect(state.objects, hasLength(1));
    expect(state.selectedPoint, isNotNull);
    await tester.dragFrom(screen(state, initial), const Offset(0, -40));
    await tester.pump();
    final moved = state.objects.single.point;
    expect(moved.z, initial.z);
    expect(moved.distanceTo(initial), greaterThan(0.1));
    await tester.tapAt(screen(state, moved));
    await tester.pump();
    await tester.dragFrom(screen(state, moved), const Offset(0, -40));
    await tester.pump();
    expect(state.objects.single.point.z, greaterThan(initial.z));
  });

  testWidgets('height dragging works at close and shallow perspective depths', (
    tester,
  ) async {
    final state = await setup(tester);
    state.setProjectionType(ProjectionType.perspective);
    while (state.camera.distance > 0.25) {
      state.zoomIn();
    }
    final forward = (state.camera.target - state.camera.position).normalized();
    for (final depth in [0.25, 0.12]) {
      final initial = state.camera.position + forward * depth;
      state.setObjects([Object3D.point(initial)]);
      await tester.pump();
      await tester.tapAt(screen(state, initial));
      await tester.pump();
      await tester.tapAt(screen(state, initial));
      await tester.pump();
      expect(state.pointDragMode, PointDragMode.height);
      await tester.dragFrom(screen(state, initial), const Offset(0, -40));
      await tester.pump();
      final raised = state.objects.single.point;
      expect(raised.z, greaterThan(initial.z), reason: 'depth=$depth');
      expect(raised.x, initial.x);
      expect(raised.y, initial.y);
      await tester.dragFrom(screen(state, raised), const Offset(0, 80));
      await tester.pump();
      expect(state.objects.single.point.z, lessThan(raised.z));
    }
  });

  for (final projection in ProjectionType.values) {
    testWidgets('point toggles height and current plane in $projection', (
      tester,
    ) async {
      final state = await setup(tester);
      state.setProjectionType(projection);
      await tester.pump();
      await tester.tapAt(const Offset(340, 330));
      await tester.pump();
      final initial = state.objects.single.point;
      final camera = state.camera;
      await tester.dragFrom(screen(state, initial), const Offset(18, -60));
      await tester.pump();
      final raised = state.objects.single.point;
      expect(raised.x, closeTo(initial.x, 1e-8));
      expect(raised.y, closeTo(initial.y, 1e-8));
      expect(raised.z, greaterThan(0));
      expect(state.camera.theta, camera.theta);
      expect(state.pointDragMode, PointDragMode.height);

      await tester.tapAt(screen(state, raised));
      await tester.pump();
      expect(state.pointDragMode, PointDragMode.plane);
      await tester.dragFrom(screen(state, raised), const Offset(70, 20));
      await tester.pump();
      final moved = state.objects.single.point;
      expect(moved.z, closeTo(raised.z, 1e-8));
      expect(moved.distanceTo(raised), greaterThan(0.1));
      expect(state.objects, hasLength(1));
    });
  }

  testWidgets('deselected point can be selected and dragged with a mouse', (
    tester,
  ) async {
    final state = await setup(tester);
    state.setTool(ConstructionTool.move);
    state.setObjects([const Object3D.point(Point3D(1, 1, 2), label: 'A')]);
    await tester.pump();
    await tester.tapAt(screen(state, state.objects.single.point));
    await tester.pump();
    expect(state.selectedPoint?.label, 'A');
    await tester.tapAt(screen(state, state.objects.single.point));
    await tester.pump();
    final start = state.objects.single.point;
    final pointer = await tester.startGesture(
      screen(state, start),
      kind: PointerDeviceKind.mouse,
    );
    await pointer.moveBy(const Offset(0, -70));
    await pointer.up();
    await tester.pump();
    expect(state.objects.single.point.z, greaterThan(start.z));
    expect(state.objects.single.point.x, start.x);
    expect(state.objects.single.point.y, start.y);
    await tester.tapAt(const Offset(100, 500));
    await tester.pump();
    expect(state.selectedPoint, isNull);
    await tester.tapAt(screen(state, state.objects.single.point));
    await tester.pump();
    expect(state.selectedPoint, isNotNull);
  });

  testWidgets(
    'floating controls do not create points and created labels are unique',
    (tester) async {
      final state = await setup(tester);
      await tester.tapAt(const Offset(340, 330));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('point-drag-mode')));
      await tester.pump();
      expect(state.pointDragMode, PointDragMode.plane);
      expect(state.objects, hasLength(1));
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(state.objects, hasLength(1));
      await tester.tapAt(const Offset(230, 410));
      await tester.pump();
      expect(state.objects, hasLength(2));
      expect(state.objects.map((object) => object.label).toSet(), hasLength(2));
    },
  );

  testWidgets('committing a point drag publishes the moved scene', (
    tester,
  ) async {
    final published = <Point3D>[];
    final state = await setup(
      tester,
      captureScene: (state) => published.add(state.objects.single.point),
    );
    state.setObjects([const Object3D.point(Point3D(1, 1, 2))]);
    await tester.pump();
    final initial = state.objects.single.point;
    published.clear();
    final pointer = await tester.startGesture(screen(state, initial));
    await pointer.moveBy(const Offset(70, 20));
    await tester.pump();
    expect(published, isEmpty);
    await pointer.up();
    await tester.pump();
    expect(state.objects.single.point.distanceTo(initial), greaterThan(0.1));
    expect(published, [state.objects.single.point]);
  });

  testWidgets('cancelling a point drag restores it without creating objects', (
    tester,
  ) async {
    var sceneChanges = 0;
    final state = await setup(tester, onSceneChanged: () => sceneChanges++);
    await tester.tapAt(const Offset(340, 330));
    await tester.pump();
    final beforeCancel = sceneChanges;
    final initial = state.objects.single;
    final pointer = await tester.startGesture(screen(state, initial.point));
    await pointer.moveBy(const Offset(0, -80));
    await tester.pump();
    await pointer.cancel();
    await tester.pump();
    expect(state.objects, [initial]);
    expect(sceneChanges, beforeCancel + 1);

    final beforeToolChange = sceneChanges;
    final interrupted = await tester.startGesture(screen(state, initial.point));
    await interrupted.moveBy(const Offset(0, -80));
    await tester.pump();
    state.setTool(ConstructionTool.move);
    await tester.pump();
    expect(state.objects.single.point, initial.point);
    expect(sceneChanges, beforeToolChange + 1);
    await interrupted.cancel();
    await tester.pump();
  });

  testWidgets(
    'planar drag arrows follow projected axes in parallel and perspective views',
    (tester) async {
      await _expectPlanarArrowsFollowAxes(
        tester,
        camera: const Camera3D(theta: 0.9, phi: 0.8),
        projectionType: ProjectionType.parallel,
        point: Point3D.origin,
      );

      const camera = Camera3D(theta: 0.9, phi: 0.8);
      final forward = (camera.target - camera.position).normalized();
      final point = camera.position + forward * 0.2;
      await _expectPlanarArrowsFollowAxes(
        tester,
        camera: camera,
        projectionType: ProjectionType.perspective,
        point: point,
      );
    },
  );

  testWidgets('two fingers navigate without moving or creating a point', (
    tester,
  ) async {
    final state = await setup(tester);
    await tester.tapAt(const Offset(340, 330));
    await tester.pump();
    final initial = state.objects.single;
    final position = screen(state, initial.point);
    final first = await tester.startGesture(position, pointer: 1);
    final second = await tester.startGesture(
      position + const Offset(80, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await first.up();
    await second.up();
    await tester.pump();
    expect(state.objects, [initial]);
    expect(state.camera.distance, lessThan(10));
  });
}
