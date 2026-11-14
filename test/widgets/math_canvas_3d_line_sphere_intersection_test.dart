import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  testWidgets('line intersections remain finite for a very large sphere', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvas3DState>();
    String? instruction;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: MathCanvas3D(
              key: key,
              currentTool: ConstructionTool.intersectionPoint,
              onToolInstruction: (value) => instruction = value,
            ),
          ),
        ),
      ),
    );

    final state = key.currentState!;
    Offset screen(Point3D point) {
      final projected = worldToScreen(
        point,
        state.camera,
        Projection3D.parallel(
          width: 800,
          height: 600,
          scale: state.camera.distance * 0.6,
        ),
      );
      return Offset(projected.x, projected.y);
    }

    Future<List<Object3D>> intersect(
      Object3D line,
      Object3D sphere,
      Point3D lineTap,
      Offset sphereTap,
    ) async {
      state.setObjects([line]);
      await tester.pump();
      await tester.tapAt(screen(lineTap));
      await tester.pump();
      expect(instruction, '再点击第二个相交对象');

      state.setObjects([line, sphere]);
      await tester.pump();
      await tester.tapAt(sphereTap);
      await tester.pump();
      return state.objects
          .where((object) => object.type == Object3DType.point)
          .toList();
    }

    const line = Object3D.line(
      Point3D(0, 0, 0),
      Point3D(1, 0, 0),
      lineKind: Line3DKind.line,
    );
    final ordinary = await intersect(
      line,
      const Object3D.sphere(center: Point3D.origin, radius: 2),
      const Point3D(0.5, 0, 0),
      screen(Point3D.origin),
    );
    expect(ordinary, hasLength(2));
    expect(ordinary.map((object) => object.point.x), [-2, 2]);

    final large = await intersect(
      line,
      const Object3D.sphere(center: Point3D.origin, radius: 1e155),
      const Point3D(0.5, 0, 0),
      const Offset(20, 20),
    );
    expect(large, hasLength(2));
    expect(large.map((object) => object.point.x), [-1e155, 1e155]);
    for (final point in large.map((object) => object.point)) {
      expect(point.x.isFinite, isTrue);
      expect(point.y.isFinite, isTrue);
      expect(point.z.isFinite, isTrue);
    }
  });
}
