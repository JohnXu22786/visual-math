import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

const _solid = Object3D.polyhedron(
  vertices: [
    Point3D(-2, -1, 0),
    Point3D(2, -1, 0),
    Point3D(0, 2, 0),
    Point3D(0, 0, 2),
  ],
  indices: [0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3],
  label: '四面体',
  color: 0xFF2196F3,
);

Future<MathCanvas3DState> _setupCanvas(WidgetTester tester) async {
  final key = GlobalKey<MathCanvas3DState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: MathCanvas3D(key: key, currentTool: ConstructionTool.move),
        ),
      ),
    ),
  );
  await tester.pump();
  key.currentState!.setObjects([_solid]);
  await tester.pump();
  final state = key.currentState!;
  final projection = Projection3D.parallel(
    width: 400,
    height: 400,
    scale: state.camera.distance * 0.6,
  );
  final faceCenter = worldToScreen(Point3D.origin, state.camera, projection);
  await tester.tapAt(Offset(faceCenter.x, faceCenter.y));
  await tester.pump();
  return state;
}

Future<List<int>> _paintSolid(Object3D solid) async {
  const size = Size(400, 400);
  final painter = MathCanvas3DPainter(
    cameraDistance: 7,
    showAxes: false,
    showPlane: false,
    showGrid: false,
    showLabels: false,
    objects: [solid],
    canvasWidth: size.width,
    canvasHeight: size.height,
  );
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(400, 400);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  image.dispose();
  return bytes;
}

class _PaintEvent {
  final String kind;
  final ui.Path? path;
  final Offset? start;
  final Offset? end;
  final ui.Paint paint;

  const _PaintEvent({
    required this.kind,
    required this.paint,
    this.path,
    this.start,
    this.end,
  });
}

class _RecordingCanvas extends Fake implements ui.Canvas {
  final events = <_PaintEvent>[];

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {}

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    events.add(_PaintEvent(kind: 'path', path: path, paint: paint));
  }

  @override
  void drawLine(Offset start, Offset end, ui.Paint paint) {
    events.add(_PaintEvent(kind: 'line', start: start, end: end, paint: paint));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selecting a solid exposes editing and delete controls', (
    tester,
  ) async {
    final state = await _setupCanvas(tester);

    final controls = find.byKey(const ValueKey('solid-style-controls'));
    expect(controls, findsOneWidget);
    expect(
      find.descendant(of: controls, matching: find.text('四面体')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('solid-fill-color')), findsOneWidget);
    expect(find.byKey(const ValueKey('solid-delete')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('solid-delete')));
    await tester.pump();
    expect(state.objects, isEmpty);
  });

  testWidgets('solid style edits color, width, and edge visibility', (
    tester,
  ) async {
    final state = await _setupCanvas(tester);

    await tester.tap(find.byKey(const ValueKey('solid-fill-color')));
    await tester.pumpAndSettle();
    expect(find.text('选择颜色'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('solid-color-1')));
    await tester.pumpAndSettle();
    expect(state.objects.single.color, 0xFFF44336);

    final widthField = find.byKey(const ValueKey('solid-edge-width'));
    await tester.enterText(widthField, '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(state.objects.single.edgeWidth, 6);
    expect(tester.widget<TextField>(widthField).controller!.text, '6');

    await tester.enterText(widthField, '-2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(state.objects.single.edgeWidth, 0);
    expect(tester.widget<TextField>(widthField).controller!.text, '0');

    final edgeVisibility = find.byKey(const ValueKey('solid-show-edges'));
    expect(tester.widget<Checkbox>(edgeVisibility).value, isTrue);
    await tester.tap(edgeVisibility);
    await tester.pump();
    expect(state.objects.single.showEdges, isFalse);
    expect(tester.widget<Checkbox>(edgeVisibility).value, isFalse);
  });

  test('polyhedron edge style changes rendered output and keeps fill color context', () async {
    final visiblePixels = await _paintSolid(_solid);
    final hiddenPixels = await _paintSolid(_solid.copyWith(showEdges: false));
    final zeroWidthPixels = await _paintSolid(_solid.copyWith(edgeWidth: 0));

    expect(visiblePixels, isNot(equals(hiddenPixels)));
    expect(hiddenPixels, equals(zeroWidthPixels));

    final edge = solidEdgeContrastColor(const Color(0xFF2196F3));
    expect(edge, isNot(const Color(0xFF2196F3)));
    expect(edge, isNot(Colors.black));
    expect(edge, isNot(Colors.white));
    expect(edge.b, greaterThan(edge.r));
    expect(edge.b, greaterThan(edge.g));
  });

  test('surface outline respects color alpha and object opacity', () {
    const size = Size(400, 400);
    for (final (color, opacity) in [
      (0xFF2196F3, 0.0),
      (0x002196F3, 1.0),
      (0x802196F3, 0.5),
      (0xFF2196F3, 1.0),
    ]) {
      final canvas = _RecordingCanvas();
      final painter = MathCanvas3DPainter(
        cameraDistance: 7,
        showAxes: false,
        showPlane: false,
        showGrid: false,
        showLabels: false,
        objects: [
          Object3D.surface(
            vertices: const [
              Point3D(-2, -1, 0),
              Point3D(2, -1, 0),
              Point3D(0, 2, 0),
            ],
            indices: const [0, 1, 2],
            color: color,
            opacity: opacity,
          ),
        ],
        canvasWidth: size.width,
        canvasHeight: size.height,
      );
      painter.paint(canvas, size);
      final strokes = canvas.events.where(
        (event) =>
            event.kind == 'path' && event.paint.style == PaintingStyle.stroke,
      );
      expect(strokes, hasLength(1));
      expect(
        strokes.single.paint.color.a,
        closeTo(((color >> 24) & 0xFF) / 255 * opacity * 0.3, 0.00001),
      );
    }
  });

  test('polyhedron edge strokes render after an incident face fill', () {
    const size = Size(400, 400);
    final canvas = _RecordingCanvas();
    const solid = Object3D.polyhedron(
      vertices: [
        Point3D(-2, -1, 0),
        Point3D(2, -1, 0),
        Point3D(0, 2, 0),
        Point3D(0, 0, 2),
      ],
      indices: [0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3],
      color: 0xFF2196F3,
      edgeWidth: 3,
    );
    final painter = MathCanvas3DPainter(
      cameraDistance: 7,
      showAxes: false,
      showPlane: false,
      showGrid: false,
      showLabels: false,
      objects: [solid],
      canvasWidth: size.width,
      canvasHeight: size.height,
    );
    painter.paint(canvas, size);

    final edgeEvents = canvas.events.indexed.where(
      (entry) =>
          entry.$2.kind == 'line' &&
          entry.$2.paint.style == PaintingStyle.stroke,
    );
    expect(
      edgeEvents,
      isNotEmpty,
      reason: canvas.events
          .map(
            (event) =>
                '${event.kind}:${event.paint.color}/${event.paint.style}',
          )
          .join(', '),
    );

    for (final edgeEvent in edgeEvents) {
      final line = edgeEvent.$2;
      final incidentFaces = canvas.events.indexed.where((entry) {
        final event = entry.$2;
        if (event.kind != 'path' || event.paint.style != PaintingStyle.fill) {
          return false;
        }
        final bounds = event.path!.getBounds().inflate(0.1);
        return bounds.contains(line.start!) && bounds.contains(line.end!);
      });
      expect(incidentFaces, isNotEmpty);
      expect(
        incidentFaces.any((face) => face.$1 < edgeEvent.$1),
        isTrue,
        reason: 'An edge must paint after one of its incident faces.',
      );
    }
  });
}
