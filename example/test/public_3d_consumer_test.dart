import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  testWidgets('public 3D canvas accepts host scene and camera updates', (
    tester,
  ) async {
    final canvasKey = GlobalKey<MathCanvas3DState>();
    final initialObject = Object3D.point(
      const Point3D(1, 2, 3),
      label: 'Initial point',
    );
    final updatedObject = Object3D.point(
      const Point3D(4, 5, 6),
      label: 'Host point',
    );
    final initialCamera = const Camera3D(distance: 12);
    final updatedCamera = const Camera3D(
      target: Point3D(3, 2, 1),
      distance: 20,
    );
    List<Object3D>? reportedScene;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathCanvas3D(
            key: canvasKey,
            initialObjects: [initialObject],
            initialCamera: initialCamera,
            onSceneUpdated: (objects) => reportedScene = objects,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(canvasKey.currentState!.objects.single.point, initialObject.point);
    expect(canvasKey.currentState!.camera.distance, initialCamera.distance);

    canvasKey.currentState!
      ..setObjects([updatedObject])
      ..setCamera(updatedCamera);
    await tester.pump();

    expect(canvasKey.currentState!.objects.single.point, updatedObject.point);
    expect(canvasKey.currentState!.camera.target, updatedCamera.target);
    expect(canvasKey.currentState!.camera.distance, updatedCamera.distance);
    expect(reportedScene!.single.point, updatedObject.point);
    expect(tester.takeException(), isNull);
  });
}
