import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/src/geometry/sphere_intersection_curve.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('sphere intersection curves', () {
    test('large finite sphere-plane intersection stays finite', () {
      final curve = spherePlaneIntersectionCurve(
        const Object3D.sphere(radius: 1e155),
        const Object3D.plane(c: 1),
      );

      expect(curve, isNotNull);
      expect(curve!.type, Object3DType.curve);
      expect(curve.vertices, hasLength(65));
      for (final point in curve.vertices) {
        expect(
          [point.x, point.y, point.z].every((value) => value.isFinite),
          isTrue,
        );
      }
      expect(curve.conic, isNull);

      final offCenter = spherePlaneIntersectionCurve(
        const Object3D.sphere(
          center: Point3D(1.3e308, 1.3e308, 0),
          radius: 1.5e308,
        ),
        const Object3D.plane(a: 1, b: 1, d: 0.65e308),
      );
      expect(offCenter, isNotNull);
      expect(
        offCenter!.vertices.every(
          (point) =>
              [point.x, point.y, point.z].every((value) => value.isFinite),
        ),
        isTrue,
      );

      final tinyNormal = spherePlaneIntersectionCurve(
        const Object3D.sphere(
          center: Point3D(1.59e308, 1.59e308, 1.59e308),
          radius: 1.6e308,
        ),
        const Object3D.plane(a: 1e-308, b: 1e-308, c: 1e-308, d: 2),
      );
      expect(tinyNormal, isNotNull);
      expect(
        tinyNormal!.vertices.every(
          (point) =>
              [point.x, point.y, point.z].every((value) => value.isFinite),
        ),
        isTrue,
      );

      final subnormalCoordinates = spherePlaneIntersectionCurve(
        const Object3D.sphere(center: Point3D(5e-324, 0, 0), radius: 1e-308),
        const Object3D.plane(a: 1e308, d: 0.5),
      );
      expect(subnormalCoordinates, isNotNull);
      expect(
        subnormalCoordinates!.vertices.every(
          (point) =>
              [point.x, point.y, point.z].every((value) => value.isFinite),
        ),
        isTrue,
      );
    });

    test('large finite sphere-sphere intersection stays finite', () {
      final curve = sphereSphereIntersectionCurve(
        const Object3D.sphere(radius: 1e155),
        const Object3D.sphere(center: Point3D(1e155, 0, 0), radius: 1e155),
      );

      expect(curve, isNotNull);
      expect(curve!.type, Object3DType.curve);
      expect(curve.vertices, hasLength(65));
      for (final point in curve.vertices) {
        expect(
          [point.x, point.y, point.z].every((value) => value.isFinite),
          isTrue,
        );
      }
      expect(curve.conic, isNull);

      final oppositeCenters = sphereSphereIntersectionCurve(
        const Object3D.sphere(center: Point3D(-1e308, 0, 0), radius: 1.5e308),
        const Object3D.sphere(center: Point3D(1e308, 0, 0), radius: 1.5e308),
      );
      expect(oppositeCenters, isNotNull);
      expect(
        oppositeCenters!.vertices.every(
          (point) =>
              [point.x, point.y, point.z].every((value) => value.isFinite),
        ),
        isTrue,
      );

      final tinyOffset = sphereSphereIntersectionCurve(
        const Object3D.sphere(radius: 1e308),
        const Object3D.sphere(center: Point3D(1e-100, 0, 0), radius: 1e308),
      );
      expect(tinyOffset, isNotNull);
      expect(tinyOffset!.vertices, hasLength(65));

      final smallestOffset = sphereSphereIntersectionCurve(
        const Object3D.sphere(radius: 1e308),
        const Object3D.sphere(center: Point3D(5e-324, 0, 0), radius: 1e308),
      );
      expect(smallestOffset, isNotNull);

      final translatedDisjoint = sphereSphereIntersectionCurve(
        const Object3D.sphere(center: Point3D(1e12, 0, 0), radius: 0.1),
        const Object3D.sphere(center: Point3D(1e12 + 1, 0, 0), radius: 0.1),
      );
      expect(translatedDisjoint, isNull);

      final coincidentSpheres = sphereSphereIntersectionCurve(
        const Object3D.sphere(center: Point3D(2, 3, 4), radius: 5),
        const Object3D.sphere(center: Point3D(2, 3, 4), radius: 5),
      );
      expect(coincidentSpheres, isNull);
    });

    test('unrepresentable circle vertices are rejected', () {
      final curve = spherePlaneIntersectionCurve(
        const Object3D.sphere(center: Point3D(1.7e308, 0, 0), radius: 1e308),
        const Object3D.plane(c: 1),
      );

      expect(curve, isNull);
    });

    test('large coordinate precision does not admit disjoint spheres', () {
      final spherePlaneMiss = spherePlaneIntersectionCurve(
        const Object3D.sphere(center: Point3D(1e308, 0, 0), radius: 1),
        const Object3D.plane(a: 1, d: 1e308 - 2e292),
      );
      final sphereSphereMiss = sphereSphereIntersectionCurve(
        const Object3D.sphere(center: Point3D(-1e308, 0, 0), radius: 1),
        const Object3D.sphere(center: Point3D(1e308, 0, 0), radius: 1),
      );
      expect(
        [spherePlaneMiss, sphereSphereMiss].every((result) => result == null),
        isTrue,
      );
    });
  });
}
