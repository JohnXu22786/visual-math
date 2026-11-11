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
  }) async {
    final key = GlobalKey<MathCanvas3DState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathCanvas3D(
            key: key,
            currentTool: ConstructionTool.point,
            onSceneChanged: onSceneChanged,
            onObjectCreated: (object) {
              key.currentState!.setObjects([
                ...key.currentState!.objects,
                object,
              ]);
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
    for (final depth in [0.25, 0.02]) {
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
