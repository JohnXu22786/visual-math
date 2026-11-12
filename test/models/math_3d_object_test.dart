import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('Point3D', () {
    test('subtracts two points to get a vector', () {
      final a = Point3D(3, 4, 5);
      final b = Point3D(1, 2, 3);
      final v = a - b;
      expect(v.x, closeTo(2, 1e-10));
      expect(v.y, closeTo(2, 1e-10));
      expect(v.z, closeTo(2, 1e-10));
    });

    test('adds a vector to a point', () {
      final p = Point3D(1, 2, 3);
      final v = Vector3D(10, 20, 30);
      final result = p + v;
      expect(result.x, closeTo(11, 1e-10));
      expect(result.y, closeTo(22, 1e-10));
      expect(result.z, closeTo(33, 1e-10));
    });

    test('distanceTo calculates Euclidean distance', () {
      final a = Point3D(0, 0, 0);
      final b = Point3D(3, 4, 0);
      expect(a.distanceTo(b), closeTo(5, 1e-10));
    });

    test('distanceTo handles 3D distance', () {
      final a = Point3D(0, 0, 0);
      final b = Point3D(1, 2, 3);
      expect(a.distanceTo(b), closeTo(3.741657, 1e-5));
    });

    test('midpoint calculates correct center between two points', () {
      final a = Point3D(0, 0, 0);
      final b = Point3D(2, 4, 6);
      final m = a.midpoint(b);
      expect(m.x, closeTo(1, 1e-10));
      expect(m.y, closeTo(2, 1e-10));
      expect(m.z, closeTo(3, 1e-10));
    });

    test('midpoint preserves finite extremes and subnormal coordinates', () {
      const tiny = 5e-324;
      const a = Point3D(1e308, -1e308, tiny);
      const b = Point3D(1.1e308, -1.1e308, tiny);
      final midpoint = a.midpoint(b);
      expect(midpoint.x, closeTo(1.05e308, 1e293));
      expect(midpoint.y, closeTo(-1.05e308, 1e293));
      expect(midpoint.z, tiny);
      expect(
        const Point3D(1e308, 0, 0).midpoint(const Point3D(-1e308, 0, 0)).x,
        0,
      );
    });

    test('equality works by value', () {
      expect(Point3D(1, 2, 3), equals(Point3D(1, 2, 3)));
      expect(Point3D(1, 2, 3), isNot(equals(Point3D(1, 2, 4))));
    });
  });

  group('Vector3D', () {
    test('magnitude returns correct length', () {
      expect(Vector3D(3, 4, 0).magnitude, closeTo(5, 1e-10));
      expect(Vector3D(1, 2, 3).magnitude, closeTo(3.741657, 1e-5));
    });

    test('normalized returns unit vector', () {
      final v = Vector3D(3, 0, 0);
      final n = v.normalized();
      expect(n.x, closeTo(1, 1e-10));
      expect(n.y, closeTo(0, 1e-10));
      expect(n.z, closeTo(0, 1e-10));
      expect(n.magnitude, closeTo(1, 1e-10));
    });

    test('normalized preserves direction across finite scales', () {
      for (final scale in [1e-16, 1e-300, 1e300]) {
        final n = Vector3D(scale, -scale, 0).normalized();
        expect(n.x, closeTo(0.7071067811865476, 1e-10));
        expect(n.y, closeTo(-0.7071067811865476, 1e-10));
        expect(n.z, 0);
        expect(n.magnitude, closeTo(1, 1e-10));
      }
    });

    test('normalized handles zero vector gracefully', () {
      final v = Vector3D(0, 0, 0);
      final n = v.normalized();
      expect(n.x, 0);
      expect(n.y, 0);
      expect(n.z, 0);
    });

    test('dot product calculates correctly', () {
      final a = Vector3D(1, 0, 0);
      final b = Vector3D(0, 1, 0);
      expect(a.dot(b), closeTo(0, 1e-10));
      expect(a.dot(a), closeTo(1, 1e-10));
    });

    test('cross product calculates correctly', () {
      final x = Vector3D(1, 0, 0);
      final y = Vector3D(0, 1, 0);
      final z = x.cross(y);
      expect(z.x, closeTo(0, 1e-10));
      expect(z.y, closeTo(0, 1e-10));
      expect(z.z, closeTo(1, 1e-10));
    });

    test('addition and subtraction work', () {
      final a = Vector3D(1, 2, 3);
      final b = Vector3D(10, 20, 30);
      expect((a + b), equals(Vector3D(11, 22, 33)));
      expect((a - b), equals(Vector3D(-9, -18, -27)));
    });

    test('scalar multiplication works', () {
      final v = Vector3D(1, 2, 3);
      final scaled = v * 3;
      expect(scaled, equals(Vector3D(3, 6, 9)));
    });

    test('negation works', () {
      final v = Vector3D(1, -2, 3);
      expect(-v, equals(Vector3D(-1, 2, -3)));
    });
  });

  group('SurfaceMesh utility', () {
    test('rejects empty grid dimensions', () {
      expect(
        () => SurfaceMesh.fromFunction(
          xMin: -1,
          xMax: 1,
          yMin: -1,
          yMax: 1,
          gridX: 0,
          gridY: 1,
          f: (x, y) => x + y,
        ),
        throwsArgumentError,
      );
    });

    test('rejects inverted or non-finite bounds', () {
      expect(
        () => SurfaceMesh.fromFunction(
          xMin: 1,
          xMax: -1,
          yMin: -1,
          yMax: 1,
          gridX: 1,
          gridY: 1,
          f: (x, y) => x + y,
        ),
        throwsArgumentError,
      );
    });

    test('rejects finite bounds whose span overflows before sampling', () {
      for (final overflowX in [true, false]) {
        var sampled = false;
        expect(
          () => SurfaceMesh.fromFunction(
            xMin: overflowX ? -1e308 : -1,
            xMax: overflowX ? 1e308 : 1,
            yMin: overflowX ? -1 : -1e308,
            yMax: overflowX ? 1 : 1e308,
            gridX: 2,
            gridY: 2,
            f: (x, y) {
              sampled = true;
              return 0;
            },
          ),
          throwsArgumentError,
        );
        expect(sampled, isFalse);
      }
    });

    test('creates grid mesh for z = f(x,y) function', () {
      final mesh = SurfaceMesh.fromFunction(
        xMin: -1,
        xMax: 1,
        yMin: -1,
        yMax: 1,
        gridX: 2,
        gridY: 2,
        f: (x, y) => x * x + y * y,
      );
      // 3x3 grid = 9 vertices
      // 2x2 cells × 2 triangles per cell = 8 triangles = 24 indices
      expect(mesh.vertices.length, 9);
      expect(mesh.indices.length, 24);
      // Center point (0,0) should have z = 0
      expect(mesh.vertices[4].z, closeTo(0, 1e-10));
    });

    test('computes vertex normals for lighting', () {
      final mesh = SurfaceMesh.fromFunction(
        xMin: -1,
        xMax: 1,
        yMin: -1,
        yMax: 1,
        gridX: 2,
        gridY: 2,
        f: (x, y) => 0, // flat plane
      );
      expect(mesh.normals.length, 9);
      // All normals should point up
      for (final n in mesh.normals) {
        expect(n.z, greaterThan(0));
      }
    });

    test('computes bounding box', () {
      final mesh = SurfaceMesh.fromFunction(
        xMin: -2,
        xMax: 2,
        yMin: -3,
        yMax: 3,
        gridX: 4,
        gridY: 6,
        f: (x, y) => x + y,
      );
      expect(mesh.boundingBoxMin.x, closeTo(-2, 1e-10));
      expect(mesh.boundingBoxMax.x, closeTo(2, 1e-10));
      expect(mesh.boundingBoxMin.y, closeTo(-3, 1e-10));
      expect(mesh.boundingBoxMax.y, closeTo(3, 1e-10));
    });
  });
}
