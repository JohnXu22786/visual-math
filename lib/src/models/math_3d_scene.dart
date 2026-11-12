import 'dart:math' as dart_math;

import 'math_3d_object.dart';

// ======================================================================
// ScreenPoint: 2D screen coordinates with depth
// ======================================================================

/// A projected 2D screen point with depth (for z-sorting).
class ScreenPoint {
  final double x;
  final double y;
  final double z;

  const ScreenPoint(this.x, this.y, this.z);

  @override
  String toString() => 'Screen($x, $y, z=$z)';
}

/// A ray in world space, used by the construction tools to turn a screen
/// gesture into a point on a working plane.
class Ray3D {
  final Point3D origin;
  final Vector3D direction;

  const Ray3D(this.origin, this.direction);

  Point3D pointAt(double distance) => origin + direction * distance;
}

/// Intersect a world-space ray with an infinite plane.
///
/// Returns null when the ray is parallel to the plane or the hit is behind
/// the ray origin, unless [allowBehind] is enabled for parallel projection.
/// Keeping this in scene math makes construction input testable without a canvas.
Point3D? intersectRayPlane(
  Ray3D ray, {
  required Point3D point,
  required Vector3D normal,
  bool allowBehind = false,
}) {
  Vector3D? unitVector(Vector3D vector) {
    if (!vector.x.isFinite || !vector.y.isFinite || !vector.z.isFinite) {
      return null;
    }
    final scale = dart_math.max(
      dart_math.max(vector.x.abs(), vector.y.abs()),
      vector.z.abs(),
    );
    if (scale == 0) return null;
    final x = vector.x / scale;
    final y = vector.y / scale;
    final z = vector.z / scale;
    final magnitude = dart_math.sqrt(x * x + y * y + z * z);
    return Vector3D(x / magnitude, y / magnitude, z / magnitude);
  }

  final direction = unitVector(ray.direction);
  final unitNormal = unitVector(normal);
  if (direction == null || unitNormal == null) return null;

  final denominator = direction.dot(unitNormal);
  if (denominator.abs() < 1e-10) return null;

  final distance = (point - ray.origin).dot(unitNormal) / denominator;
  if (!distance.isFinite || (!allowBehind && distance < 0)) return null;
  return ray.origin + direction * distance;
}

// ======================================================================
// Camera3D: Spherical-coordinate orbiting camera
// ======================================================================

/// A 3D camera controlled via spherical coordinates around a target point.
///
/// GeoGebra-style coordinates are used throughout: xOy is the ground plane
/// and Z is the vertical axis.
///
/// theta: azimuthal angle (rotation around Z axis)
/// phi: polar angle (elevation from horizontal)
/// distance: distance from camera to target
class Camera3D {
  final Point3D target;
  final double distance;
  final double theta;
  final double phi;

  const Camera3D({
    this.target = Point3D.origin,
    this.distance = 10,
    this.theta = dart_math.pi * 0.75,
    this.phi = dart_math.pi / 6, // 30 degrees above the xOy plane
  });

  /// Compute the camera position in world space from spherical coords.
  Point3D get position {
    // Clamp phi to avoid gimbal lock at poles
    final clampedPhi = phi.clamp(-dart_math.pi * 0.49, dart_math.pi * 0.49);
    final cosPhi = dart_math.cos(clampedPhi);
    final sinPhi = dart_math.sin(clampedPhi);
    final cosTheta = dart_math.cos(theta);
    final sinTheta = dart_math.sin(theta);

    return Point3D(
      target.x + distance * cosPhi * sinTheta,
      target.y + distance * cosPhi * cosTheta,
      target.z + distance * sinPhi,
    );
  }

  /// Orbit the camera around the target.
  ///
  /// [deltaTheta] changes the azimuthal angle (left/right).
  /// [deltaPhi] changes the polar angle (up/down).
  Camera3D orbit({required double deltaTheta, required double deltaPhi}) {
    return Camera3D(
      target: target,
      distance: distance,
      theta: theta + deltaTheta,
      phi: (phi + deltaPhi).clamp(-dart_math.pi * 0.49, dart_math.pi * 0.49),
    );
  }

  /// Zoom the camera by a factor.
  ///
  /// factor > 1 moves camera closer, factor < 1 moves farther.
  Camera3D zoom({required double factor}) {
    final newDistance = (distance / factor).clamp(0.1, 1000).toDouble();
    return Camera3D(
      target: target,
      distance: newDistance,
      theta: theta,
      phi: phi,
    );
  }

  /// Pan the camera: move target parallel to the view plane.
  ///
  /// [deltaX] and [deltaY] are in screen-space units. When a projection is
  /// supplied, the target plane follows the drag in pixels.
  Camera3D pan({
    required double deltaX,
    required double deltaY,
    Projection3D? projection,
  }) {
    // Build right and up vectors from current view direction
    final pos = position;
    final forward = (target - pos).normalized();
    final worldUp = Vector3D(0, 0, 1);

    // Right vector: cross(forward, worldUp)
    var right = forward.cross(worldUp);
    if (right.magnitude < 1e-10) {
      // Looking straight up/down, use Y as reference.
      right = forward.cross(Vector3D(0, 1, 0));
    }
    right = right.normalized();

    // Up vector: cross(right, forward)
    final up = right.cross(forward).normalized();

    final scale = projection == null || projection.height <= 0
        ? distance * 0.002
        : projection.type == ProjectionType.parallel
        ? 2 * projection.scale / projection.height
        : 2 *
              distance *
              dart_math.tan(projection.fov * dart_math.pi / 360) /
              projection.height;

    final newTarget = Point3D(
      target.x + (-deltaX * right.x + deltaY * up.x) * scale,
      target.y + (-deltaX * right.y + deltaY * up.y) * scale,
      target.z + (-deltaX * right.z + deltaY * up.z) * scale,
    );

    return Camera3D(
      target: newTarget,
      distance: distance,
      theta: theta,
      phi: phi,
    );
  }

  /// Build a view matrix (4x4 column-major) for this camera.
  ///
  /// Uses a lookAt convention: maps world to camera space.
  List<double> viewMatrix() {
    final pos = position;
    final f = (target - pos).normalized();
    final worldUp = Vector3D(0, 0, 1);
    var r = f.cross(worldUp).normalized();
    if (r.magnitude < 1e-10) {
      r = f.cross(Vector3D(0, 1, 0)).normalized();
    }
    final u = r.cross(f).normalized();

    // 4x4 lookAt matrix
    return [
      r.x,
      u.x,
      -f.x,
      0,
      r.y,
      u.y,
      -f.y,
      0,
      r.z,
      u.z,
      -f.z,
      0,
      -(r.dot(pos.toVector())),
      -(u.dot(pos.toVector())),
      f.dot(pos.toVector()),
      1,
    ];
  }

  Camera3D copyWith({
    Point3D? target,
    double? distance,
    double? theta,
    double? phi,
  }) {
    return Camera3D(
      target: target ?? this.target,
      distance: distance ?? this.distance,
      theta: theta ?? this.theta,
      phi: phi ?? this.phi,
    );
  }
}

// ======================================================================
// Projection
// ======================================================================

/// Type of 3D projection.
enum ProjectionType {
  /// Orthographic (parallel) projection — no foreshortening.
  parallel,

  /// Perspective projection with foreshortening.
  perspective,
}

/// A 3D projection that maps world coordinates to screen coordinates.
class Projection3D {
  final ProjectionType type;
  final double width;
  final double height;
  final double scale; // for parallel
  final double fov; // for perspective (degrees)
  final double near;
  final double far;

  const Projection3D._({
    required this.type,
    required this.width,
    required this.height,
    this.scale = 50,
    this.fov = 60,
    this.near = 0.1,
    this.far = 1000,
  });

  /// Create a parallel (orthographic) projection.
  factory Projection3D.parallel({
    double width = 800,
    double height = 600,
    double scale = 50,
  }) {
    return Projection3D._(
      type: ProjectionType.parallel,
      width: width,
      height: height,
      scale: scale,
    );
  }

  /// Create a perspective projection.
  factory Projection3D.perspective({
    double width = 800,
    double height = 600,
    double fov = 60,
    double near = 0.1,
    double far = 1000,
  }) {
    return Projection3D._(
      type: ProjectionType.perspective,
      width: width,
      height: height,
      fov: fov,
      near: near,
      far: far,
    );
  }

  /// Build a 4x4 column-major projection matrix.
  List<double> projectionMatrix() {
    if (type == ProjectionType.parallel) {
      return _orthographicMatrix();
    } else {
      return _perspectiveMatrix();
    }
  }

  List<double> _orthographicMatrix() {
    final aspect = width / height;
    final halfW = scale * aspect;
    final halfH = scale;
    // Orthographic: left=-halfW, right=halfW, bottom=-halfH, top=halfH
    return [
      1 / halfW,
      0,
      0,
      0,
      0,
      1 / halfH,
      0,
      0,
      0,
      0,
      -2 / (far - near),
      0,
      0,
      0,
      -(far + near) / (far - near),
      1,
    ];
  }

  List<double> _perspectiveMatrix() {
    final aspect = width / height;
    final fovRad = fov * dart_math.pi / 180;
    final f = 1 / dart_math.tan(fovRad / 2);
    return [
      f / aspect,
      0,
      0,
      0,
      0,
      f,
      0,
      0,
      0,
      0,
      (far + near) / (near - far),
      -1,
      0,
      0,
      2 * far * near / (near - far),
      0,
    ];
  }

  /// Project a 3D world point to 2D screen coordinates.
  ///
  /// Returns a [ScreenPoint] with (x, y) in pixel coordinates
  /// and z as depth (for z-sorting).
  ScreenPoint project(Point3D worldPoint) {
    final aspect = width / height;
    final depth = -worldPoint.z;

    if (type == ProjectionType.perspective) {
      final fovRad = fov * dart_math.pi / 180;
      final focalScale = 1 / dart_math.tan(fovRad / 2);
      // Camera space looks down -Z. Keep values finite for points on or
      // behind the eye plane; clipping is handled by the painter.
      final safeDepth = depth.abs() < 1e-9
          ? (depth.isNegative ? -1e-9 : 1e-9)
          : depth;
      final ndcX = worldPoint.x * focalScale / (aspect * safeDepth);
      final ndcY = worldPoint.y * focalScale / safeDepth;
      return ScreenPoint(
        (ndcX + 1) * width / 2,
        (1 - ndcY) * height / 2,
        depth,
      );
    }

    final halfW = scale * aspect;
    final ndcX = worldPoint.x / halfW;
    final ndcY = worldPoint.y / scale;
    return ScreenPoint((ndcX + 1) * width / 2, (1 - ndcY) * height / 2, depth);
  }
}

// ======================================================================
// Scene3D
// ======================================================================

/// A 3D scene containing objects, a camera, and projection settings.
class Scene3D {
  Camera3D camera;
  final List<Object3D> _objects = [];

  Scene3D({Camera3D? camera}) : camera = camera ?? Camera3D();

  /// Unmodifiable view of the objects in the scene.
  List<Object3D> get objects => List.unmodifiable(_objects);

  /// The center of the scene (average of object positions).
  Point3D get sceneCenter {
    if (_objects.isEmpty) return camera.target;
    var sumX = 0.0, sumY = 0.0, sumZ = 0.0;
    var count = 0;

    void addPoint(Point3D p) {
      sumX += p.x;
      sumY += p.y;
      sumZ += p.z;
      count++;
    }

    for (final obj in _objects) {
      switch (obj.type) {
        case Object3DType.point:
          addPoint(obj.point);
        case Object3DType.line:
          addPoint(obj.pointA);
          addPoint(obj.pointB);
        case Object3DType.plane:
          // Use plane origin on the plane closest to scene origin
          break;
        case Object3DType.surface:
        case Object3DType.polyhedron:
          for (final v in obj.vertices) {
            addPoint(v);
          }
        case Object3DType.sphere:
          addPoint(obj.sphereCenter);
        case Object3DType.vector:
          addPoint(obj.point);
          addPoint(obj.point + obj.vector);
        case Object3DType.curve:
          for (final v in obj.vertices) {
            addPoint(v);
          }
      }
    }

    if (count == 0) return camera.target;
    return Point3D(sumX / count, sumY / count, sumZ / count);
  }

  /// Add an object to the scene.
  void add(Object3D object) {
    _objects.add(object);
  }

  /// Remove an object from the scene.
  void remove(Object3D object) {
    _objects.remove(object);
  }

  /// Remove all objects from the scene.
  void clear() {
    _objects.clear();
  }

  /// Adjust the camera to encompass all objects.
  ///
  /// Returns an updated projection when needed to frame the scene. Callers
  /// should use the returned projection, especially after parallel fitting.
  Projection3D? fitToView({Projection3D? projection}) {
    if (_objects.isEmpty) return projection;

    final points = <Point3D>[];
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    void checkPoint(Point3D p) {
      if (!p.x.isFinite || !p.y.isFinite || !p.z.isFinite) return;
      points.add(p);
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (final obj in _objects) {
      switch (obj.type) {
        case Object3DType.point:
          checkPoint(obj.point);
        case Object3DType.line:
          checkPoint(obj.pointA);
          checkPoint(obj.pointB);
        case Object3DType.plane:
          break;
        case Object3DType.surface:
        case Object3DType.polyhedron:
          for (final v in obj.vertices) {
            checkPoint(v);
          }
        case Object3DType.sphere:
          final c = obj.sphereCenter;
          final r = obj.sphereRadius.abs();
          for (final dx in [-r, r]) {
            for (final dy in [-r, r]) {
              for (final dz in [-r, r]) {
                checkPoint(Point3D(c.x + dx, c.y + dy, c.z + dz));
              }
            }
          }
        case Object3DType.vector:
          checkPoint(obj.point);
          checkPoint(obj.point + obj.vector);
        case Object3DType.curve:
          for (final v in obj.vertices) {
            checkPoint(v);
          }
      }
    }

    if (!minX.isFinite) return projection;

    final center = Point3D(
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2,
    );
    final maxExtent = dart_math.max(
      dart_math.max(maxX - minX, maxY - minY),
      maxZ - minZ,
    );
    camera = camera.copyWith(target: center);
    var fittedProjection = projection;
    var fittedDistance = dart_math.max(4, maxExtent * 1.35).toDouble();
    if (projection?.type == ProjectionType.parallel) {
      final aspect = projection!.width / projection.height;
      final viewMatrix = camera.viewMatrix();
      final right = Vector3D(viewMatrix[0], viewMatrix[4], viewMatrix[8]);
      final up = Vector3D(viewMatrix[1], viewMatrix[5], viewMatrix[9]);
      var minRight = double.infinity;
      var minUp = double.infinity;
      var maxRight = double.negativeInfinity;
      var maxUp = double.negativeInfinity;
      for (final point in points) {
        final offset = point - center;
        final projectedRight = offset.dot(right);
        final projectedUp = offset.dot(up);
        minRight = dart_math.min(minRight, projectedRight);
        maxRight = dart_math.max(maxRight, projectedRight);
        minUp = dart_math.min(minUp, projectedUp);
        maxUp = dart_math.max(maxUp, projectedUp);
      }
      if (aspect.isFinite && aspect > 0) {
        final halfWidth = dart_math.max(minRight.abs(), maxRight.abs());
        final halfHeight = dart_math.max(minUp.abs(), maxUp.abs());
        final requiredScale = dart_math.max(halfHeight, halfWidth / aspect);
        if (requiredScale.isFinite) {
          fittedProjection = Projection3D.parallel(
            width: projection.width,
            height: projection.height,
            scale: dart_math.max(1e-3, requiredScale * 1.1).toDouble(),
          );
        }
      }
    } else if (projection?.type == ProjectionType.perspective) {
      final aspect = projection!.width / projection.height;
      final halfFov = projection.fov * dart_math.pi / 360;
      final tangent = dart_math.tan(halfFov);
      if (aspect.isFinite && aspect > 0 && tangent.isFinite && tangent > 0) {
        final viewMatrix = camera.viewMatrix();
        final right = Vector3D(viewMatrix[0], viewMatrix[4], viewMatrix[8]);
        final up = Vector3D(viewMatrix[1], viewMatrix[5], viewMatrix[9]);
        final forward = Vector3D(
          -viewMatrix[2],
          -viewMatrix[6],
          -viewMatrix[10],
        );
        final focalScale = 1 / tangent;
        var requiredDistance = 0.0;
        var farthestDepthOffset = double.negativeInfinity;
        for (final point in points) {
          final offset = point - center;
          final depthOffset = offset.dot(forward);
          farthestDepthOffset = dart_math.max(farthestDepthOffset, depthOffset);
          final minimumDepth = dart_math.max(
            dart_math.max(
              offset.dot(right).abs() * focalScale / aspect,
              offset.dot(up).abs() * focalScale,
            ),
            projection.near,
          );
          requiredDistance = dart_math.max(
            requiredDistance,
            minimumDepth - depthOffset,
          );
        }
        if (requiredDistance.isFinite) {
          fittedDistance = dart_math.max(4, requiredDistance * 1.1).toDouble();
          final requiredFar = (fittedDistance + farthestDepthOffset) * 1.1;
          fittedProjection = Projection3D.perspective(
            width: projection.width,
            height: projection.height,
            fov: projection.fov,
            near: projection.near,
            far: dart_math.max(projection.far, requiredFar).toDouble(),
          );
        }
      }
    }
    camera = camera.copyWith(target: center, distance: fittedDistance);
    return fittedProjection;
  }
}

// ======================================================================
// Matrix4 utilities (minimal implementation for 3D pipeline)
// ======================================================================

/// Identity 4x4 matrix (column-major).
List<double> identityMatrix4() {
  return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
}

/// Translation 4x4 matrix (column-major).
List<double> translateMatrix4(double tx, double ty, double tz) {
  return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, tx, ty, tz, 1];
}

/// Scale 4x4 matrix (column-major).
List<double> scaleMatrix4(double sx, double sy, double sz) {
  return [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, 0, 0, 0, 1];
}

/// Multiply two 4x4 column-major matrices: A * B.
List<double> multiplyMatrix4(List<double> a, List<double> b) {
  final result = List<double>.filled(16, 0);
  for (int col = 0; col < 4; col++) {
    for (int row = 0; row < 4; row++) {
      double sum = 0;
      for (int k = 0; k < 4; k++) {
        sum += a[k * 4 + row] * b[col * 4 + k];
      }
      result[col * 4 + row] = sum;
    }
  }
  return result;
}

/// Transform a 3D point by a 4x4 column-major matrix.
/// Returns the transformed point in homogeneous space (z is the w component
/// for perspective divide).
Point3D _transformPoint(List<double> matrix, Point3D point) {
  final x =
      matrix[0] * point.x +
      matrix[4] * point.y +
      matrix[8] * point.z +
      matrix[12];
  final y =
      matrix[1] * point.x +
      matrix[5] * point.y +
      matrix[9] * point.z +
      matrix[13];
  final z =
      matrix[2] * point.x +
      matrix[6] * point.y +
      matrix[10] * point.z +
      matrix[14];
  return Point3D(x, y, z);
}

// ======================================================================
// World-to-screen pipeline
// ======================================================================

/// Transform a world 3D point through camera view and projection to screen.
ScreenPoint worldToScreen(
  Point3D worldPoint,
  Camera3D camera,
  Projection3D projection,
) {
  // World → View (camera space)
  final viewMatrix = camera.viewMatrix();
  final viewPoint = _transformPoint(viewMatrix, worldPoint);

  // View → Projection (clip space → screen)
  return projection.project(viewPoint);
}

/// Clip a segment, ray or infinite line against the camera's viewing volume.
/// The returned world endpoints are shared by rendering and pointer snapping.
List<Point3D> clipLineToView(
  Object3D object,
  Camera3D camera,
  Projection3D projection,
) {
  final view = camera.viewMatrix();
  final a = _transformPoint(view, object.pointA);
  final edge = object.pointB - object.pointA;
  final edgeScale = dart_math.max(
    edge.x.abs(),
    dart_math.max(edge.y.abs(), edge.z.abs()),
  );
  final unitEdge = edgeScale == 0
      ? edge
      : Vector3D(edge.x / edgeScale, edge.y / edgeScale, edge.z / edgeScale);
  // Directions must not include the view translation: subtracting transformed
  // points can lose a short edge when it is added to the camera position.
  final direction = Point3D(
    view[0] * unitEdge.x + view[4] * unitEdge.y + view[8] * unitEdge.z,
    view[1] * unitEdge.x + view[5] * unitEdge.y + view[9] * unitEdge.z,
    view[2] * unitEdge.x + view[6] * unitEdge.y + view[10] * unitEdge.z,
  );
  var lower = object.lineKind == Line3DKind.line
      ? double.negativeInfinity
      : 0.0;
  var upper = object.lineKind == Line3DKind.segment
      ? edgeScale
      : double.infinity;

  bool clip(double value, double slope) {
    if (slope == 0) return value >= 0;
    final bound = -value / slope;
    if (slope > 0) {
      lower = dart_math.max(lower, bound);
    } else {
      upper = dart_math.min(upper, bound);
    }
    return lower <= upper;
  }

  // Parallel projection displays geometry on either side of the camera.
  if (projection.type == ProjectionType.perspective &&
      (!clip(-a.z - projection.near, -direction.z) ||
          !clip(projection.far + a.z, direction.z)))
    return const [];
  final aspect = projection.width / projection.height;
  if (projection.type == ProjectionType.parallel) {
    final width = projection.scale * aspect;
    if (!clip(width + a.x, direction.x) ||
        !clip(width - a.x, -direction.x) ||
        !clip(projection.scale + a.y, direction.y) ||
        !clip(projection.scale - a.y, -direction.y))
      return const [];
  } else {
    final height = dart_math.tan(projection.fov * dart_math.pi / 360);
    final width = height * aspect;
    if (!clip(-a.z * width + a.x, -direction.z * width + direction.x) ||
        !clip(-a.z * width - a.x, -direction.z * width - direction.x) ||
        !clip(-a.z * height + a.y, -direction.z * height + direction.y) ||
        !clip(-a.z * height - a.y, -direction.z * height - direction.y))
      return const [];
  }
  if (!lower.isFinite || !upper.isFinite) return const [];
  return [object.pointA + unitEdge * lower, object.pointA + unitEdge * upper];
}
