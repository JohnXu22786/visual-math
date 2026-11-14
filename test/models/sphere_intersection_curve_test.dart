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

    test(
      'large translation does not admit a locally disjoint sphere-plane',
      () {
        final spherePlaneMiss = spherePlaneIntersectionCurve(
          const Object3D.sphere(center: Point3D(1e12, 0, 0), radius: 0.1),
          const Object3D.plane(a: 1, c: 0, d: 1e12 + 0.101),
        );
        expect(spherePlaneMiss, isNull);

        final cancellationMiss = spherePlaneIntersectionCurve(
          const Object3D.sphere(
            center: Point3D(5555486306855.723, -15685294125593.885, 0),
            radius: 0.01,
          ),
          const Object3D.plane(
            a: 1.2828829657394891,
            b: 0.4543771186180646,
            c: 0,
            d: 0,
          ),
        );
        expect(cancellationMiss, isNull);

        final roundedTangentMiss = spherePlaneIntersectionCurve(
          const Object3D.sphere(
            center: Point3D(2419547362792.136, 5553949237801.048, 0),
            radius: 6055285271199.417,
          ),
          const Object3D.plane(
            a: 0.6800216525596731,
            b: 1.4394832013892558,
            c: 0,
            d: 0,
          ),
        );
        expect(roundedTangentMiss, isNull);

        final roundedEqualityMiss = spherePlaneIntersectionCurve(
          const Object3D.sphere(
            center: Point3D(2419547362792.136, 5553949237801.048, 0),
            radius: 6055285271199.418,
          ),
          const Object3D.plane(
            a: 0.6800216525596731,
            b: 1.4394832013892558,
            c: 0,
            d: 0,
          ),
        );
        expect(roundedEqualityMiss, isNull);

        final translatedTangent = spherePlaneIntersectionCurve(
          const Object3D.sphere(center: Point3D(1e12, 0, 0), radius: 0.125),
          const Object3D.plane(a: 1, c: 0, d: 1e12 + 0.125),
        );
        expect(translatedTangent?.type, Object3DType.point);

        final exactObliqueTangent = spherePlaneIntersectionCurve(
          const Object3D.sphere(center: Point3D(3, 4, 0), radius: 5),
          const Object3D.plane(a: 3, b: 4, c: 0, d: 0),
        );
        expect(exactObliqueTangent?.type, Object3DType.point);

        final roundedSubtractionMiss = spherePlaneIntersectionCurve(
          const Object3D.sphere(center: Point3D(1e16, 0, 0), radius: 1e16),
          const Object3D.plane(a: 1, c: 0, d: 1),
        );
        expect(roundedSubtractionMiss, isNull);
      },
    );

    test('large translation does not admit locally disjoint spheres', () {
      final sphereSphereMiss = sphereSphereIntersectionCurve(
        const Object3D.sphere(center: Point3D(1e12, 0, 0), radius: 0.5),
        const Object3D.sphere(center: Point3D(1e12 + 1.001, 0, 0), radius: 0.5),
      );

      expect(sphereSphereMiss, isNull);
    });
  });
}
