import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  testWidgets('near-parallel segment crossing respects plane and extent', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvas3DState>();
    String? instruction;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathCanvas3D(
            key: key,
            currentTool: ConstructionTool.intersectionPoint,
            onToolInstruction: (value) => instruction = value,
          ),
        ),
      ),
    );
    final state = key.currentState!;
    Offset screen(Point3D point) {
      final p = worldToScreen(
        point,
        state.camera,
        Projection3D.parallel(
          width: 800,
          height: 600,
          scale: state.camera.distance * 0.6,
        ),
      );
      return Offset(p.x, p.y);
    }

    Future<List<Object3D>> intersect(
      Object3D line, {
      Object3D plane = const Object3D.plane(c: 1, d: 0),
      Point3D lineTap = const Point3D(0.5, 0, 0),
      Point3D planeTap = const Point3D(0, 2, 0),
    }) async {
      state.setObjects([line]);
      await tester.pump();
      await tester.tapAt(screen(lineTap));
      await tester.pump();
      expect(instruction, '再点击第二个相交对象');
      state.setObjects([line, plane]);
      await tester.pump();
      await tester.tapAt(screen(planeTap));
      await tester.pump();
      expect(instruction, isNot('再点击第二个相交对象'));
      return state.objects.where((o) => o.type == Object3DType.point).toList();
    }

    final crossing = await intersect(
      const Object3D.line(Point3D(0, 0, -1e-13), Point3D(1, 0, 1e-13)),
    );
    expect(crossing, hasLength(1));
    expect(crossing.single.point.x, closeTo(0.5, 1e-12));
    expect(crossing.single.point.z, closeTo(0, 1e-25));

    final parallel = await intersect(
      const Object3D.line(Point3D(0, 0, 1e-13), Point3D(1, 0, 1e-13)),
    );
    expect(parallel, isEmpty);
    final outside = await intersect(
      const Object3D.line(Point3D(0, 0, 1e-13), Point3D(1, 0, 2e-13)),
    );
    expect(outside, isEmpty);
    final coplanar = await intersect(
      const Object3D.line(Point3D(0, 0, 0), Point3D(-1, 3, -1)),
      plane: const Object3D.plane(a: 1, b: 2, c: 5, d: 0),
      lineTap: const Point3D(-0.5, 1.5, -0.5),
      planeTap: const Point3D(2, -1, 0),
    );
    expect(coplanar, isEmpty);
    final scaledCrossing = await intersect(
      const Object3D.line(Point3D(0, 0, -1e-13), Point3D(1, 0, 1e-13)),
      plane: const Object3D.plane(c: 1e-320, d: 0),
    );
    expect(scaledCrossing, hasLength(1));
    state.setCamera(
      Camera3D(
        theta: 0.5,
        phi: state.camera.phi,
        distance: state.camera.distance,
        target: state.camera.target,
      ),
    );
    final endpointCoplanar = await intersect(
      const Object3D.line(
        Point3D(1, 5.551115123125783e-17, -1),
        Point3D(5.551115123125783e-17, 0, 0),
      ),
      plane: const Object3D.plane(a: 1, b: 1, c: 1, d: 5.551115123125783e-17),
      lineTap: const Point3D(0.5, 0, -0.5),
      planeTap: const Point3D(1, -1, 0),
    );
    expect(endpointCoplanar, isEmpty);
    final roundedCoplanar = await intersect(
      const Object3D.line(Point3D(0, 0, 0), Point3D(3, 3, 1)),
      plane: const Object3D.plane(
        a: 10000000000000002,
        b: -10000000000000000,
        c: -6,
        d: 0,
      ),
      lineTap: const Point3D(1.5, 1.5, 0.5),
      planeTap: const Point3D(1, 1, 2),
    );
    expect(roundedCoplanar, isEmpty);
    final cancellingCrossing = await intersect(
      const Object3D.line(
        Point3D(-0.5, 0.4999999999999999, 0),
        Point3D(0.5, -0.4999999999999999, 0),
      ),
      plane: const Object3D.plane(a: 1, b: 1, c: 0, d: 0),
      lineTap: const Point3D(0, 0, 0),
      planeTap: const Point3D(1, -1, 2),
    );
    expect(cancellingCrossing, hasLength(1));
    expect(cancellingCrossing.single.point.x, closeTo(0, 1e-12));
    for (final kind in [Line3DKind.segment, Line3DKind.ray, Line3DKind.line]) {
      final endpoint = await intersect(
        Object3D.line(
          const Point3D(0, 0, 0),
          const Point3D(1, -0.9999999999999999, 0),
          lineKind: kind,
        ),
        plane: const Object3D.plane(a: 1, b: 1, c: 0, d: 0),
        lineTap: const Point3D(0.5, -0.5, 0),
        planeTap: const Point3D(1, -1, 2),
      );
      expect(
        endpoint,
        hasLength(1),
        reason: '$kind should include the endpoint',
      );
    }
  });
}
