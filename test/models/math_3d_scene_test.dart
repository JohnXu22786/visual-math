import 'dart:math' as dart_math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('Camera3D', () {
    test('position is derived from spherical coordinates', () {
      // Use phi=0 so camera is on the horizon (no clamping issues)
      final cam = Camera3D(
        target: Point3D(0, 0, 0),
        distance: 10,
        theta: 0,
        phi: 0,
      );
      final pos = cam.position;
      // GeoGebra coordinates are Z-up. At theta=0 the camera is on +Y.
      expect(pos.x, closeTo(0, 1e-10));
      expect(pos.y, closeTo(10, 1e-10));
      expect(pos.z, closeTo(0, 1e-10));
    });

    test('phi is clamped during orbit operation', () {
      // Constructor doesn't clamp (const), but orbit does
      final cam = Camera3D().orbit(deltaTheta: 0, deltaPhi: dart_math.pi * 6);
      expect(cam.phi, lessThanOrEqualTo(dart_math.pi * 0.49));
      expect(cam.phi, greaterThanOrEqualTo(-dart_math.pi * 0.49));
    });

    test('distance is clamped during zoom operation', () {
      // Constructor doesn't clamp (const), but zoom does
      final cam = Camera3D(distance: 10).zoom(factor: 0.001);
      expect(cam.distance, greaterThanOrEqualTo(0.1));
    });

    test('orbit rotation updates theta', () {
      final cam = Camera3D();
      final updated = cam.orbit(deltaTheta: 0.5, deltaPhi: 0);
      expect(updated.theta, closeTo(dart_math.pi * 0.75 + 0.5, 1e-10));
      expect(updated.phi, closeTo(dart_math.pi / 6, 1e-10));
    });

    test('orbit rotation updates phi', () {
      final cam = Camera3D();
      final updated = cam.orbit(deltaTheta: 0, deltaPhi: 0.3);
      expect(updated.phi, closeTo(dart_math.pi / 6 + 0.3, 1e-10));
    });

    test('zoom changes distance by factor', () {
      final cam = Camera3D(distance: 10);
      final updated = cam.zoom(factor: 2);
      expect(updated.distance, closeTo(5, 1e-10)); // zoom in: distance / factor
    });

    test(
      'pan tracks pointer at the target for each projection and viewport',
      () {
        const camera = Camera3D(distance: 10);
        for (final height in [300.0, 1200.0]) {
          for (final projection in [
            Projection3D.parallel(width: 800, height: height, scale: 6),
            Projection3D.perspective(width: 800, height: height, fov: 60),
          ]) {
            final before = worldToScreen(camera.target, camera, projection);
            final panned = camera.pan(
              deltaX: 100,
              deltaY: -50,
              projection: projection,
            );
            final after = worldToScreen(camera.target, panned, projection);
            expect(after.x - before.x, closeTo(100, 1e-8));
            expect(after.y - before.y, closeTo(-50, 1e-8));
          }
        }
      },
    );

    test('pan moves target parallel to view plane', () {
      final cam = Camera3D(
        target: Point3D(0, 0, 0),
        distance: 10,
        theta: 0,
        phi: 0, // looking along the horizontal -Y direction
      );
      final updated = cam.pan(deltaX: 100, deltaY: 200);
      // Pan sensitivity: distance * 0.002. Horizontal drag follows the
      // camera-right basis, while vertical drag follows world Z here.
      expect(updated.target.x, closeTo(2, 1e-10));
      expect(updated.target.y, closeTo(0, 1e-10));
      expect(updated.target.z, closeTo(4, 1e-10));
    });
  });

  group('Projection3D', () {
    test('project transforms 3D point to 2D screen coordinates', () {
      final proj = Projection3D.parallel(width: 800, height: 600, scale: 50);
      // Origin should project to center of screen
      final screen = proj.project(Point3D(0, 0, 0));
      expect(screen.x, closeTo(400, 1));
      expect(screen.y, closeTo(300, 1));
      // z is depth (for sorting) — finite
      expect(screen.z.isFinite, isTrue);
    });

    test('project maps positive x to the right', () {
      final proj = Projection3D.parallel(width: 800, height: 600, scale: 50);
      final screen = proj.project(Point3D(1, 0, 0));
      expect(screen.x, greaterThan(400)); // right of center
    });

    test('project maps positive y upward (screen y decreases)', () {
      final proj = Projection3D.parallel(width: 800, height: 600, scale: 50);
      final screen = proj.project(Point3D(0, 1, 0));
      expect(screen.y, lessThan(300)); // higher on screen
    });

    test('perspective projection produces different results from parallel', () {
      final parallel = Projection3D.parallel(
        width: 800,
        height: 600,
        scale: 50,
      );
      final perspective = Projection3D.perspective(
        width: 800,
        height: 600,
        fov: 60,
        near: 0.1,
        far: 1000,
      );
      final p1 = parallel.project(Point3D(1, 0, 5));
      final p2 = perspective.project(Point3D(1, 0, 5));
      // They differ (perspective has foreshortening)
      expect(p1.x, isNot(equals(p2.x)));
    });
  });

  group('Scene3D', () {
    test('scene center is at target if no objects', () {
      final scene = Scene3D();
      expect(scene.sceneCenter, equals(Point3D(0, 0, 0)));
    });

    test('parallel fit keeps asymmetric projected bounds in the viewport', () {
      final scene = Scene3D();
      const points = [Point3D(0, 0, 0), Point3D(10, 0, 0), Point3D(0, 10, 0)];
      for (final point in points) {
        scene.add(Object3D.point(point));
      }
      final projection = scene.fitToView(
        projection: Projection3D.parallel(width: 600, height: 600),
      )!;

      for (final point in points) {
        final screen = worldToScreen(point, scene.camera, projection);
        expect(screen.x, inInclusiveRange(0, 600));
        expect(screen.y, inInclusiveRange(0, 600));
      }
    });

    test('perspective fit keeps asymmetric scene inside the far plane', () {
      final scene = Scene3D();
      const points = [
        Point3D(0, 0, 0),
        Point3D(1e6, 1e6, 0),
        Point3D(1e6, 0, 0),
      ];
      for (final point in points) {
        scene.add(Object3D.point(point));
      }

      final projection = scene.fitToView(
        projection: Projection3D.perspective(),
      )!;
      final view = scene.camera.viewMatrix();
      final viewZAxis = Vector3D(view[2], view[6], view[10]);
      var minimumDepthOffset = double.infinity;
      for (final point in points) {
        final depthOffset = (point - scene.camera.target).dot(viewZAxis);
        minimumDepthOffset = dart_math.min(minimumDepthOffset, depthOffset);
        final cameraDepth =
            -(view[2] * point.x +
                view[6] * point.y +
                view[10] * point.z +
                view[14]);
        expect(cameraDepth, lessThanOrEqualTo(projection.far));
      }
      expect(
        projection.far,
        greaterThanOrEqualTo(scene.camera.distance - minimumDepthOffset),
      );

      final positiveOffsetScene = Scene3D();
      const positiveOffsetPoints = [
        Point3D(0, 0, 0),
        Point3D(1e6, 1e6, 0),
        Point3D(0, 1e6, 0),
      ];
      for (final point in positiveOffsetPoints) {
        positiveOffsetScene.add(Object3D.point(point));
      }
      final positiveOffsetProjection = positiveOffsetScene.fitToView(
        projection: Projection3D.perspective(),
      )!;
      final positiveOffsetView = positiveOffsetScene.camera.viewMatrix();
      for (final point in positiveOffsetPoints) {
        final cameraDepth =
            -(positiveOffsetView[2] * point.x +
                positiveOffsetView[6] * point.y +
                positiveOffsetView[10] * point.z +
                positiveOffsetView[14]);
        expect(cameraDepth, lessThanOrEqualTo(positiveOffsetProjection.far));
      }
    });

    test('perspective far plane follows the final safe camera direction', () {
      final scene = Scene3D();
      const points = [Point3D(1.6e308, 0, 0), Point3D(1.79e308, 0, 0)];
      for (final point in points) {
        scene.add(Object3D.point(point));
      }

      final projection = scene.fitToView(
        projection: Projection3D.perspective(),
      )!;
      final view = scene.camera.viewMatrix();
      final viewZAxis = Vector3D(view[2], view[6], view[10]);
      var minimumDepthOffset = double.infinity;
      for (final point in points) {
        final depthOffset = (point - scene.camera.target).dot(viewZAxis);
        minimumDepthOffset = dart_math.min(minimumDepthOffset, depthOffset);
      }

      expect(
        projection.far,
        greaterThanOrEqualTo(scene.camera.distance - minimumDepthOffset),
      );
    });

    test('fitToView updates the camera around finite objects', () {
      final scene = Scene3D();
      scene.add(Object3D.point(const Point3D(10, 20, 30)));
      scene.add(Object3D.point(const Point3D(14, 24, 34)));

      scene.fitToView();

      expect(scene.camera.target, equals(const Point3D(12, 22, 32)));
      expect(scene.camera.distance, closeTo(5.4, 1e-10));
    });

    test(
      'fitToView computes a finite center for large same-sign coordinates',
      () {
        final scene = Scene3D();
        scene.add(Object3D.point(const Point3D(1e308, 0, 0)));
        scene.add(Object3D.point(const Point3D(1.1e308, 0, 0)));

        scene.fitToView();

        expect(scene.camera.target.x, closeTo(1.05e308, 1e293));
        expect(scene.camera.target.x.isFinite, isTrue);
        expect(scene.camera.position.x.isFinite, isTrue);
        expect(scene.camera.position.y.isFinite, isTrue);
        expect(scene.camera.position.z.isFinite, isTrue);
        expect(
          scene.camera.viewMatrix().every((value) => value.isFinite),
          isTrue,
        );

        scene
          ..clear()
          ..add(Object3D.point(const Point3D(1e100, 1e100, 1e100)));
        scene.fitToView();

        expect(scene.camera.position, isNot(scene.camera.target));
        expect(
          scene.camera.viewMatrix().every((value) => value.isFinite),
          isTrue,
        );

        scene
          ..clear()
          ..add(Object3D.point(const Point3D(1.7e308, 0, 0)))
          ..add(Object3D.point(const Point3D(1.79e308, 0, 0)));
        scene.fitToView();

        expect(scene.camera.target.x.isFinite, isTrue);
        expect(scene.camera.distance.isFinite, isTrue);
        expect(scene.camera.position.x.isFinite, isTrue);
        expect(scene.camera.position.y.isFinite, isTrue);
        expect(scene.camera.position.z.isFinite, isTrue);
        expect(
          scene.camera.viewMatrix().every((value) => value.isFinite),
          isTrue,
        );

        scene
          ..clear()
          ..add(
            Object3D.point(
              const Point3D(
                double.maxFinite,
                double.maxFinite,
                double.maxFinite,
              ),
            ),
          );
        scene.fitToView();

        expect(scene.camera.distance, greaterThan(0));
        expect(scene.camera.position, isNot(scene.camera.target));
        expect(
          scene.camera.viewMatrix().every((value) => value.isFinite),
          isTrue,
        );
      },
    );

    test(
      'fitToView keeps distance finite when the extent exceeds double range',
      () {
        final scene = Scene3D();
        scene.add(Object3D.point(const Point3D(-double.maxFinite, 0, 0)));
        scene.add(Object3D.point(const Point3D(double.maxFinite, 0, 0)));

        scene.fitToView();

        expect(scene.camera.distance.isFinite, isTrue);
        expect(scene.camera.position.x.isFinite, isTrue);
        expect(scene.camera.position.y.isFinite, isTrue);
        expect(scene.camera.position.z.isFinite, isTrue);

        final perspectiveScene = Scene3D();
        perspectiveScene
          ..add(Object3D.point(const Point3D(-1.1e308, 0, 0)))
          ..add(Object3D.point(const Point3D(1.1e308, 0, 0)));
        final projection = perspectiveScene.fitToView(
          projection: Projection3D.perspective(),
        )!;

        expect(perspectiveScene.camera.distance.isFinite, isTrue);
        expect(perspectiveScene.camera.position.x.isFinite, isTrue);
        expect(perspectiveScene.camera.position.y.isFinite, isTrue);
        expect(perspectiveScene.camera.position.z.isFinite, isTrue);
        expect(
          perspectiveScene.camera.viewMatrix().every((value) => value.isFinite),
          isTrue,
        );
        expect(projection.far.isFinite, isTrue);
        expect(projection.far, greaterThan(perspectiveScene.camera.distance));
        expect(
          projection.projectionMatrix().every((value) => value.isFinite),
          isTrue,
        );

        final wideNearScene = Scene3D();
        wideNearScene
          ..add(Object3D.point(const Point3D(-1.1e308, 0, 0)))
          ..add(Object3D.point(const Point3D(1.1e308, 0, 0)));
        final wideNearProjection = wideNearScene.fitToView(
          projection: Projection3D.perspective(near: 7e307, far: 1e308),
        )!;

        expect(
          wideNearProjection.projectionMatrix().every(
            (value) => value.isFinite,
          ),
          isTrue,
        );
      },
    );

    test(
      'zooming out preserves fitted camera distances above the zoom cap',
      () {
        final scene = Scene3D();
        scene.add(Object3D.point(const Point3D(-1000, 0, 0)));
        scene.add(Object3D.point(const Point3D(1000, 0, 0)));

        scene.fitToView();
        final fittedDistance = scene.camera.distance;
        final zoomedOut = scene.camera.zoom(factor: 0.5);

        expect(fittedDistance, greaterThan(1000));
        expect(zoomedOut.distance, closeTo(fittedDistance * 2, 1e-10));
        expect(Camera3D(distance: 10).zoom(factor: 0.001).distance, 1000);
        expect(Camera3D(distance: 2000).zoom(factor: -1).distance, 0.1);
        expect(
          Camera3D(distance: 3000).zoom(factor: 0.5).distance,
          closeTo(6000, 1e-10),
        );
        expect(
          Camera3D(distance: 3000).zoom(factor: 1.1).distance,
          closeTo(3000 / 1.1, 1e-10),
        );
      },
    );
  });

  group('3D to 2D pipeline', () {
    test('worldToScreen transforms through camera and projection', () {
      final cam = Camera3D(
        target: Point3D(0, 0, 0),
        distance: 10,
        theta: dart_math.pi,
        phi: 0,
      );
      final proj = Projection3D.parallel(width: 800, height: 600, scale: 50);
      final screen = worldToScreen(Point3D(0, 0, 0), cam, proj);
      expect(screen.x, closeTo(400, 5));
      expect(screen.y, closeTo(300, 5));
    });

    test('worldToScreen preserves relative positions', () {
      final cam = Camera3D(
        target: Point3D(0, 0, 0),
        distance: 10,
        theta: dart_math.pi,
        phi: 0,
      );
      final proj = Projection3D.parallel(width: 800, height: 600, scale: 50);
      final left = worldToScreen(Point3D(-1, 0, 0), cam, proj);
      final right = worldToScreen(Point3D(1, 0, 0), cam, proj);
      expect(left.x, lessThan(right.x));
    });

    test('worldToScreen handles object behind camera', () {
      final cam = Camera3D(
        target: Point3D(0, 0, 0),
        distance: 5,
        theta: 0,
        phi: 0,
      );
      final proj = Projection3D.perspective(width: 800, height: 600, fov: 60);
      // Point behind the camera
      final screen = worldToScreen(Point3D(0, 0, 20), cam, proj);
      // Should not crash, might return invalid coordinates
      expect(screen, isNotNull);
    });
  });

  group('Matrix4 utilities', () {
    test('matrix multiplication produces correct result', () {
      // A = translate(1,2,3), B = scale(2,2,2)
      // A * B means "scale then translate" — translation is unchanged
      final a = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1];
      final b = scaleMatrix4(2, 2, 2);
      final result = multiplyMatrix4(a, b);
      // Scale part should be [2, 2, 2]
      expect(result[0], closeTo(2, 1e-10)); // scale x
      expect(result[5], closeTo(2, 1e-10)); // scale y
      expect(result[10], closeTo(2, 1e-10)); // scale z
      // Translation remains unchanged (scale then translate)
      expect(result[12], closeTo(1, 1e-10));
      expect(result[13], closeTo(2, 1e-10));
      expect(result[14], closeTo(3, 1e-10));
    });
  });
}
