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
    final requestedDistance = distance / factor;
    final maxDistance =
        distance > 1000 &&
            requestedDistance > 1000 &&
            requestedDistance.isFinite
        ? requestedDistance
        : 1000.0;
    final newDistance = requestedDistance.clamp(0.1, maxDistance).toDouble();
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
    final depthScale = dart_math.max(far.abs(), near.abs());
    final normalizedFar = far / depthScale;
    final normalizedNear = near / depthScale;
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
      (normalizedFar + normalizedNear) / (normalizedNear - normalizedFar),
      -1,
      0,
      0,
      2 * near * (far / (near - far)),
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
    var meanX = 0.0, meanY = 0.0, meanZ = 0.0;
    var sumX = 0.0, sumY = 0.0, sumZ = 0.0;
    var hasNonFinitePoint = false;
    var count = 0;

    double updateMean(double mean, double value) {
      if (count == 1) return value;
      return mean + (value / count - mean / count);
    }

    void addPoint(Point3D p) {
      count++;
      sumX += p.x;
      sumY += p.y;
      sumZ += p.z;
      hasNonFinitePoint |= !p.x.isFinite || !p.y.isFinite || !p.z.isFinite;
      meanX = updateMean(meanX, p.x);
      meanY = updateMean(meanY, p.y);
      meanZ = updateMean(meanZ, p.z);
    }

    void addPlaneOrigin(Object3D plane) {
      final a = plane.planeA;
      final b = plane.planeB;
      final c = plane.planeC;
      final d = plane.planeD;
      if (![a, b, c, d].every((value) => value.isFinite)) return;

      final scale = [
        a.abs(),
        b.abs(),
        c.abs(),
      ].reduce((first, second) => first > second ? first : second);
      if (scale == 0) return;

      final scaledA = a / scale;
      final scaledB = b / scale;
      final scaledC = c / scale;
      final normalLengthSquared =
          scaledA * scaledA + scaledB * scaledB + scaledC * scaledC;
      final scaledOffset = d / scale;
      double coordinate(double scaledCoefficient) {
        if (scaledOffset.isFinite) {
          return (scaledOffset / normalLengthSquared) * scaledCoefficient;
        }
        return ((d * scaledCoefficient) / normalLengthSquared) / scale;
      }

      final point = Point3D(
        coordinate(scaledA),
        coordinate(scaledB),
        coordinate(scaledC),
      );
      if (![point.x, point.y, point.z].every((value) => value.isFinite)) {
        return;
      }
      addPoint(point);
    }

    for (final obj in _objects) {
      switch (obj.type) {
        case Object3DType.point:
          addPoint(obj.point);
        case Object3DType.line:
          addPoint(obj.pointA);
          addPoint(obj.pointB);
        case Object3DType.plane:
          // Use the point on the plane closest to the scene origin.
          addPlaneOrigin(obj);
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
    if (hasNonFinitePoint) {
      return Point3D(sumX / count, sumY / count, sumZ / count);
    }
    double average(double sum, double mean) =>
        sum.isFinite ? sum / count : mean;
    return Point3D(
      average(sumX, meanX),
      average(sumY, meanY),
      average(sumZ, meanZ),
    );
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

    double midpoint(double min, double max) {
      // Subtracting is safe for same-sign values; splitting the operands avoids
      // overflowing their sum when they have opposite signs.
      return min.sign == max.sign ? min + (max - min) / 2 : min / 2 + max / 2;
    }

    double finiteExtent(double min, double max) {
      final extent = max - min;
      return extent.isFinite ? extent : double.maxFinite;
    }

    final center = Point3D(
      midpoint(minX, maxX),
      midpoint(minY, maxY),
      midpoint(minZ, maxZ),
    );
    final extentX = finiteExtent(minX, maxX);
    final extentY = finiteExtent(minY, maxY);
    final extentZ = finiteExtent(minZ, maxZ);
    final maxExtent = dart_math.max(dart_math.max(extentX, extentY), extentZ);
    camera = camera.copyWith(target: center);
    var fittedProjection = projection;
    final maxScalableExtent = double.maxFinite / 1.35;
    var fittedDistance = maxExtent > maxScalableExtent
        ? double.maxFinite
        : dart_math.max(4, maxExtent * 1.35).toDouble();
    if (projection?.type == ProjectionType.perspective &&
        maxExtent > double.maxFinite / 1.35) {
      // Put the camera along the least-extended axis so an unrepresentably
      // wide span contributes to screen size instead of far-plane depth.
      final theta = extentY <= extentX && extentY <= extentZ
          ? 0.0
          : dart_math.pi / 2;
      final phi = extentZ < extentX && extentZ < extentY
          ? dart_math.pi * 0.49
          : 0.0;
      camera = camera.copyWith(theta: theta, phi: phi);
    }
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
        final viewZAxis = Vector3D(
          viewMatrix[2],
          viewMatrix[6],
          viewMatrix[10],
        );
        final focalScale = 1 / tangent;
        double finiteProduct(double left, double right) {
          final product = left * right;
          return product.isFinite ? product : double.maxFinite;
        }

        var requiredDistance = 0.0;
        for (final point in points) {
          final offset = point - center;
          final depthOffset = offset.dot(viewZAxis);
          final minimumDepth = dart_math.max(
            dart_math.max(
              finiteProduct(offset.dot(right).abs() / aspect, focalScale),
              finiteProduct(offset.dot(up).abs(), focalScale),
            ),
            projection.near,
          );
          final pointDistance = minimumDepth + depthOffset;
          requiredDistance = dart_math.max(
            requiredDistance,
            pointDistance.isFinite ? pointDistance : double.maxFinite,
          );
        }
        if (requiredDistance.isFinite) {
          final scaledDistance = requiredDistance > double.maxFinite / 1.1
              ? double.maxFinite
              : requiredDistance * 1.1;
          fittedDistance = dart_math.max(4, scaledDistance).toDouble();
        }
      }
    }

    var theta = camera.theta;
    var phi = camera.phi.clamp(-dart_math.pi * 0.49, dart_math.pi * 0.49);
    double maxPositionSafeDistance(double coordinate, double direction) {
      if (direction == 0) return double.infinity;
      final headroom = direction > 0
          ? (coordinate > 0 ? double.maxFinite - coordinate : double.maxFinite)
          : (coordinate < 0 ? double.maxFinite + coordinate : double.maxFinite);
      final distance = headroom / direction.abs();
      return distance.isFinite ? distance : double.maxFinite;
    }

    double distanceToMoveCoordinate(double coordinate, double direction) {
      if (direction == 0) return double.infinity;
      if (coordinate == 0) return 0;
      // Several ULPs ensure adding the camera offset changes a large target.
      return coordinate.abs() * 8.881784197001252e-16 / direction.abs();
    }

    double minDistinctDistance(double theta, double phi) {
      final cosPhi = dart_math.cos(phi);
      return dart_math.min(
        dart_math.min(
          distanceToMoveCoordinate(center.x, cosPhi * dart_math.sin(theta)),
          distanceToMoveCoordinate(center.y, cosPhi * dart_math.cos(theta)),
        ),
        distanceToMoveCoordinate(center.z, dart_math.sin(phi)),
      );
    }

    double positionSafeDistance(double theta, double phi) {
      final cosPhi = dart_math.cos(phi);
      return dart_math.min(
        dart_math.min(
          maxPositionSafeDistance(center.x, cosPhi * dart_math.sin(theta)),
          maxPositionSafeDistance(center.y, cosPhi * dart_math.cos(theta)),
        ),
        maxPositionSafeDistance(center.z, dart_math.sin(phi)),
      );
    }

    var maxPositionSafeDistanceForTarget = positionSafeDistance(theta, phi);
    var distinctDistance = minDistinctDistance(theta, phi);
    final needsInwardDirection =
        maxPositionSafeDistanceForTarget < dart_math.max(4, distinctDistance);
    if (needsInwardDirection) {
      final cosPhi = dart_math.cos(phi);
      final directionX = cosPhi * dart_math.sin(theta);
      final directionY = cosPhi * dart_math.cos(theta);
      var inwardX = center.x > 0
          ? -directionX.abs()
          : center.x < 0
          ? directionX.abs()
          : directionX;
      var inwardY = center.y > 0
          ? -directionY.abs()
          : center.y < 0
          ? directionY.abs()
          : directionY;
      final directionZ = dart_math.sin(phi);
      var inwardZ = center.z > 0
          ? -directionZ.abs()
          : center.z < 0
          ? directionZ.abs()
          : directionZ;
      final centerScale = dart_math.max(
        dart_math.max(center.x.abs(), center.y.abs()),
        center.z.abs(),
      );
      if (centerScale > 0) {
        final normalizedCenterX = center.x / centerScale;
        final normalizedCenterY = center.y / centerScale;
        final normalizedCenterZ = center.z / centerScale;
        final centerLengthRatio = dart_math.sqrt(
          normalizedCenterX * normalizedCenterX +
              normalizedCenterY * normalizedCenterY +
              normalizedCenterZ * normalizedCenterZ,
        );
        if (centerLengthRatio > double.maxFinite / centerScale) {
          // The absolute camera translation also needs to remain representable.
          // Moving back along the target vector keeps its magnitude finite.
          inwardX = -normalizedCenterX / centerLengthRatio;
          inwardY = -normalizedCenterY / centerLengthRatio;
          inwardZ = -normalizedCenterZ / centerLengthRatio;
          fittedDistance = double.maxFinite;
        }
      }
      theta = dart_math.atan2(inwardX, inwardY);
      phi = dart_math.asin(inwardZ.clamp(-1.0, 1.0));
      maxPositionSafeDistanceForTarget = positionSafeDistance(theta, phi);
      distinctDistance = minDistinctDistance(theta, phi);
    }
    fittedDistance = dart_math
        .min(
          dart_math.max(fittedDistance, distinctDistance),
          maxPositionSafeDistanceForTarget,
        )
        .toDouble();
    camera = camera.copyWith(
      target: center,
      distance: fittedDistance,
      theta: theta,
      phi: phi,
    );
    if (projection?.type == ProjectionType.perspective &&
        fittedProjection?.type == ProjectionType.perspective) {
      final viewMatrix = camera.viewMatrix();
      final viewZAxis = Vector3D(viewMatrix[2], viewMatrix[6], viewMatrix[10]);
      var minimumDepthOffset = double.infinity;
      for (final point in points) {
        minimumDepthOffset = dart_math.min(
          minimumDepthOffset,
          (point - center).dot(viewZAxis),
        );
      }
      final depthSum = fittedDistance - minimumDepthOffset;
      final maxFar = double.maxFinite;
      final requiredFar = !depthSum.isFinite
          ? (depthSum.isNegative ? -maxFar : maxFar)
          : depthSum > maxFar / 1.1
          ? maxFar
          : depthSum < -maxFar / 1.1
          ? -maxFar
          : depthSum * 1.1;
      final farPlane = dart_math
          .min(maxFar, dart_math.max(fittedProjection!.far, requiredFar))
          .toDouble();
      fittedProjection = Projection3D.perspective(
        width: projection!.width,
        height: projection.height,
        fov: projection.fov,
        near: dart_math.min(projection.near, farPlane * 0.1).toDouble(),
        far: farPlane,
      );
    }
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
  final pointA = object.pointA;
  final pointB = object.pointB;
  if (!pointA.x.isFinite ||
      !pointA.y.isFinite ||
      !pointA.z.isFinite ||
      !pointB.x.isFinite ||
      !pointB.y.isFinite ||
      !pointB.z.isFinite) {
    return const [];
  }
  final view = camera.viewMatrix();
  final edge = pointB - pointA;
  var clipOrigin = pointA;
  var centeredSegment = false;
  var edgeScale = dart_math.max(
    edge.x.abs(),
    dart_math.max(edge.y.abs(), edge.z.abs()),
  );
  Vector3D unitEdge;
  if (edgeScale.isFinite) {
    unitEdge = edgeScale == 0
        ? edge
        : Vector3D(edge.x / edgeScale, edge.y / edgeScale, edge.z / edgeScale);
  } else {
    // Subtracting finite endpoints can overflow when they lie on opposite
    // sides of the number range. Scale before subtracting to preserve the
    // direction; the true segment extent is then beyond any finite parameter.
    if (object.lineKind == Line3DKind.segment) {
      // Center the parameterization so intersections near the middle of an
      // extreme segment don't require subtracting nearly equal max doubles.
      clipOrigin = Point3D(
        pointA.x / 2 + pointB.x / 2,
        pointA.y / 2 + pointB.y / 2,
        pointA.z / 2 + pointB.z / 2,
      );
      centeredSegment = true;
      final halfEdge = Vector3D(
        pointB.x / 2 - pointA.x / 2,
        pointB.y / 2 - pointA.y / 2,
        pointB.z / 2 - pointA.z / 2,
      );
      edgeScale = dart_math.max(
        halfEdge.x.abs(),
        dart_math.max(halfEdge.y.abs(), halfEdge.z.abs()),
      );
      if (edgeScale == 0 || !edgeScale.isFinite) return const [];
      unitEdge = Vector3D(
        halfEdge.x / edgeScale,
        halfEdge.y / edgeScale,
        halfEdge.z / edgeScale,
      );
    } else {
      final pointScale = dart_math.max(
        dart_math.max(pointA.x.abs(), pointB.x.abs()),
        dart_math.max(
          dart_math.max(pointA.y.abs(), pointB.y.abs()),
          dart_math.max(pointA.z.abs(), pointB.z.abs()),
        ),
      );
      final scaledEdge = Vector3D(
        pointB.x / pointScale - pointA.x / pointScale,
        pointB.y / pointScale - pointA.y / pointScale,
        pointB.z / pointScale - pointA.z / pointScale,
      );
      final scaledEdgeScale = dart_math.max(
        scaledEdge.x.abs(),
        dart_math.max(scaledEdge.y.abs(), scaledEdge.z.abs()),
      );
      if (scaledEdgeScale == 0 || !scaledEdgeScale.isFinite) return const [];
      unitEdge = Vector3D(
        scaledEdge.x / scaledEdgeScale,
        scaledEdge.y / scaledEdgeScale,
        scaledEdge.z / scaledEdgeScale,
      );
      edgeScale = double.infinity;
    }
  }
  final a = _transformPoint(view, clipOrigin);
  if (!a.x.isFinite || !a.y.isFinite || !a.z.isFinite) return const [];
  // Directions must not include the view translation: subtracting transformed
  // points can lose a short edge when it is added to the camera position.
  final direction = Point3D(
    view[0] * unitEdge.x + view[4] * unitEdge.y + view[8] * unitEdge.z,
    view[1] * unitEdge.x + view[5] * unitEdge.y + view[9] * unitEdge.z,
    view[2] * unitEdge.x + view[6] * unitEdge.y + view[10] * unitEdge.z,
  );
  if (!direction.x.isFinite || !direction.y.isFinite || !direction.z.isFinite) {
    return const [];
  }
  var lower = object.lineKind == Line3DKind.line
      ? double.negativeInfinity
      : centeredSegment
      ? -edgeScale
      : 0.0;
  var upper = object.lineKind == Line3DKind.segment
      ? edgeScale
      : double.infinity;

  bool clip(double value, double slope) {
    if (!value.isFinite || !slope.isFinite) return false;
    if (slope == 0) return value >= 0;
    final rawBound = -value / slope;
    // A crossing can be just beyond the largest representable parameter even
    // when its clipped world coordinate is finite (for example, a segment
    // spanning both signs of double.maxFinite). Saturate that bound so later
    // clipping planes can still narrow it to the visible interval.
    final bound = rawBound.isInfinite
        ? (rawBound.isNegative ? -double.maxFinite : double.maxFinite)
        : rawBound;
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
  return [clipOrigin + unitEdge * lower, clipOrigin + unitEdge * upper];
}
