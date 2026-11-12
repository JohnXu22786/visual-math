import 'dart:math' as dart_math;

/// A 3D point with x, y, z coordinates.
class Point3D {
  final double x;
  final double y;
  final double z;

  const Point3D(this.x, this.y, this.z);

  /// Origin at (0, 0, 0).
  static const origin = Point3D(0, 0, 0);

  /// Subtract another point to get a vector.
  Vector3D operator -(Point3D other) =>
      Vector3D(x - other.x, y - other.y, z - other.z);

  /// Add a vector to get a new point.
  Point3D operator +(Vector3D v) => Point3D(x + v.x, y + v.y, z + v.z);

  /// Euclidean distance to another point.
  double distanceTo(Point3D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return dart_math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Midpoint between this and another point.
  Point3D midpoint(Point3D other) =>
      Point3D((x + other.x) / 2, (y + other.y) / 2, (z + other.z) / 2);

  /// Convert to a position vector (from origin).
  Vector3D toVector() => Vector3D(x, y, z);

  @override
  bool operator ==(Object other) =>
      other is Point3D && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}

/// A 3D vector with x, y, z components.
class Vector3D {
  final double x;
  final double y;
  final double z;

  const Vector3D(this.x, this.y, this.z);

  /// Zero vector.
  static const zero = Vector3D(0, 0, 0);

  /// Unit vector along X axis.
  static const unitX = Vector3D(1, 0, 0);

  /// Unit vector along Y axis.
  static const unitY = Vector3D(0, 1, 0);

  /// Unit vector along Z axis.
  static const unitZ = Vector3D(0, 0, 1);

  /// Magnitude (length) of this vector.
  double get magnitude => dart_math.sqrt(x * x + y * y + z * z);

  /// Returns a unit vector in the same direction.
  /// Returns zero vector if magnitude is zero.
  Vector3D normalized() {
    final scale = dart_math.max(x.abs(), dart_math.max(y.abs(), z.abs()));
    if (scale == 0) return Vector3D.zero;
    if (!scale.isFinite) {
      final mag = magnitude;
      return Vector3D(x / mag, y / mag, z / mag);
    }
    final sx = x / scale;
    final sy = y / scale;
    final sz = z / scale;
    final mag = dart_math.sqrt(sx * sx + sy * sy + sz * sz);
    return Vector3D(sx / mag, sy / mag, sz / mag);
  }

  /// Dot product with another vector.
  double dot(Vector3D other) => x * other.x + y * other.y + z * other.z;

  /// Cross product with another vector.
  Vector3D cross(Vector3D other) => Vector3D(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  Vector3D operator +(Vector3D other) =>
      Vector3D(x + other.x, y + other.y, z + other.z);

  Vector3D operator -(Vector3D other) =>
      Vector3D(x - other.x, y - other.y, z - other.z);

  Vector3D operator *(double scalar) =>
      Vector3D(x * scalar, y * scalar, z * scalar);

  Vector3D operator -() => Vector3D(-x, -y, -z);

  @override
  bool operator ==(Object other) =>
      other is Vector3D && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '[$x, $y, $z]';
}

/// Implicit conic equation in the local plane coordinates:
/// `quadraticX*x² + quadraticXY*x*y + quadraticY*y² +`
/// `linearX*x + linearY*y + constant = 0`.
class Conic3D {
  final Point3D origin;
  final Vector3D axisU;
  final Vector3D axisV;
  final double quadraticX;
  final double quadraticXY;
  final double quadraticY;
  final double linearX;
  final double linearY;
  final double constant;

  const Conic3D({
    required this.origin,
    required this.axisU,
    required this.axisV,
    required this.quadraticX,
    required this.quadraticXY,
    required this.quadraticY,
    required this.linearX,
    required this.linearY,
    required this.constant,
  });
}

/// Types of 3D objects that can be rendered.
enum Object3DType {
  point,
  line,
  plane,
  surface,
  sphere,
  polyhedron,
  vector,
  curve,
}

const double maxSolidEdgeWidth = 6;

enum Line3DKind { segment, line, ray }

/// A 3D object in the scene.
///
/// Uses a tagged-union pattern with constructors for each type.
/// The type determines which fields are relevant.
class Object3D {
  final Object3DType type;

  /// Stable identity used by portable documents and scene relationships.
  final String documentId;

  /// Formula row that generated this plot, or null for constructed objects.
  final String? formulaRowId;

  // Point fields
  final Point3D? _point;
  Point3D get point => _point ?? Point3D.origin;

  final Line3DKind lineKind;

  // Line fields
  final Point3D? _pointA;
  Point3D get pointA => _pointA ?? Point3D.origin;
  final Point3D? _pointB;
  Point3D get pointB => _pointB ?? Point3D.origin;

  // Plane fields: ax + by + cz = d
  final double? _planeA;
  double get planeA => _planeA ?? 0;
  final double? _planeB;
  double get planeB => _planeB ?? 0;
  final double? _planeC;
  double get planeC => _planeC ?? 1;
  final double? _planeD;
  double get planeD => _planeD ?? 0;

  // Surface / mesh fields
  final List<Point3D>? _vertices;
  List<Point3D> get vertices => _vertices ?? const [];
  final List<int>? _indices;
  List<int> get indices => _indices ?? const [];
  final List<Vector3D>? _normals;
  List<Vector3D> get normals => _normals ?? const [];

  /// Vertex indexes that begin new disconnected paths in a curve.
  final List<int> curveStarts;
  final Conic3D? conic;

  // Sphere fields
  final Point3D? _sphereCenter;
  Point3D get sphereCenter => _sphereCenter ?? Point3D.origin;
  final double? _sphereRadius;
  double get sphereRadius => _sphereRadius ?? 1;

  // Vector fields
  final Vector3D? _vector;
  Vector3D get vector => _vector ?? Vector3D.zero;

  // Visual properties
  final int color;
  final double opacity;
  final double edgeWidth;
  final bool showEdges;
  final String? label;
  final bool transformOrigin;
  final bool visible;

  /// Render this point's text independently from geometric point labels.
  final bool isTextAnnotation;

  const Object3D._({
    required this.type,
    this.documentId = '',
    this.formulaRowId,
    this.lineKind = Line3DKind.segment,
    Point3D? point,
    Point3D? pointA,
    Point3D? pointB,
    double? planeA,
    double? planeB,
    double? planeC,
    double? planeD,
    List<Point3D>? vertices,
    List<int>? indices,
    List<Vector3D>? normals,
    this.curveStarts = const [],
    this.conic,
    Point3D? sphereCenter,
    double? sphereRadius,
    Vector3D? vector,
    this.color = 0xFFAAAAAA,
    this.opacity = 1.0,
    this.edgeWidth = 1.5,
    this.showEdges = true,
    this.label,
    this.transformOrigin = false,
    this.visible = true,
    this.isTextAnnotation = false,
  }) : _point = point,
       _pointA = pointA,
       _pointB = pointB,
       _planeA = planeA,
       _planeB = planeB,
       _planeC = planeC,
       _planeD = planeD,
       _vertices = vertices,
       _indices = indices,
       _normals = normals,
       _sphereCenter = sphereCenter,
       _sphereRadius = sphereRadius,
       _vector = vector;

  /// Preserve geometry and appearance when naming or moving an object.
  Object3D copyWith({
    String? documentId,
    String? formulaRowId,
    Point3D? point,
    String? label,
    int? color,
    double? opacity,
    double? edgeWidth,
    bool? showEdges,
    bool? visible,
    bool? transformOrigin,
  }) => Object3D._(
    type: type,
    documentId: documentId ?? this.documentId,
    formulaRowId: formulaRowId ?? this.formulaRowId,
    lineKind: lineKind,
    point: point ?? _point,
    pointA: _pointA,
    pointB: _pointB,
    planeA: _planeA,
    planeB: _planeB,
    planeC: _planeC,
    planeD: _planeD,
    vertices: _vertices,
    indices: _indices,
    normals: _normals,
    curveStarts: curveStarts,
    conic: conic,
    sphereCenter: _sphereCenter,
    sphereRadius: _sphereRadius,
    vector: _vector,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    edgeWidth: edgeWidth == null
        ? this.edgeWidth
        : edgeWidth.clamp(0, maxSolidEdgeWidth).toDouble(),
    showEdges: showEdges ?? this.showEdges,
    label: label ?? this.label,
    transformOrigin: transformOrigin ?? this.transformOrigin,
    visible: visible ?? this.visible,
    isTextAnnotation: isTextAnnotation,
  );

  /// Copy this object with independent, unmodifiable geometry collections.
  Object3D immutableCopy() => Object3D._(
    type: type,
    documentId: documentId,
    formulaRowId: formulaRowId,
    lineKind: lineKind,
    point: _point,
    pointA: _pointA,
    pointB: _pointB,
    planeA: _planeA,
    planeB: _planeB,
    planeC: _planeC,
    planeD: _planeD,
    vertices: _vertices == null ? null : List.unmodifiable(_vertices),
    indices: _indices == null ? null : List.unmodifiable(_indices),
    normals: _normals == null ? null : List.unmodifiable(_normals),
    curveStarts: List.unmodifiable(curveStarts),
    conic: conic,
    sphereCenter: _sphereCenter,
    sphereRadius: _sphereRadius,
    vector: _vector,
    color: color,
    opacity: opacity,
    edgeWidth: edgeWidth,
    showEdges: showEdges,
    label: label,
    transformOrigin: transformOrigin,
    visible: visible,
    isTextAnnotation: isTextAnnotation,
  );

  // ==================================================================
  // Factory constructors
  // ==================================================================

  const factory Object3D.point(
    Point3D point, {
    int color,
    double opacity,
    String? label,
  }) = _Object3DPoint;

  const factory Object3D.text(
    Point3D point, {
    required String text,
    int color,
    double opacity,
  }) = _Object3DText;

  const factory Object3D.line(
    Point3D a,
    Point3D b, {
    Line3DKind lineKind,
    int color,
    double opacity,
    String? label,
  }) = _Object3DLine;

  const factory Object3D.plane({
    double a,
    double b,
    double c,
    double d,
    int color,
    double opacity,
    String? label,
  }) = _Object3DPlane;

  const factory Object3D.surface({
    required List<Point3D> vertices,
    required List<int> indices,
    List<Vector3D>? normals,
    int color,
    double opacity,
    double edgeWidth,
    bool showEdges,
    String? label,
  }) = _Object3DSurface;

  const factory Object3D.sphere({
    Point3D center,
    double radius,
    int color,
    double opacity,
    String? label,
  }) = _Object3DSphere;

  const factory Object3D.polyhedron({
    required List<Point3D> vertices,
    required List<int> indices,
    int color,
    double opacity,
    double edgeWidth,
    bool showEdges,
    String? label,
  }) = _Object3DPolyhedron;

  const factory Object3D.vectorObj({
    required Vector3D vector,
    Point3D? origin,
    int color,
    double opacity,
    String? label,
  }) = _Object3DVector;

  const factory Object3D.curve({
    required List<Point3D> points,
    List<int> curveStarts,
    Conic3D? conic,
    int color,
    double opacity,
    String? label,
  }) = _Object3DCurve;
}

// Private subclasses for const constructors
class _Object3DPoint extends Object3D {
  const _Object3DPoint(
    Point3D point, {
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.point,
         point: point,
         color: color,
         opacity: opacity,
         label: label,
       );
}

class _Object3DText extends Object3D {
  const _Object3DText(
    Point3D point, {
    required String text,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
  }) : super._(
         type: Object3DType.point,
         point: point,
         color: color,
         opacity: opacity,
         label: text,
         isTextAnnotation: true,
       );
}

class _Object3DLine extends Object3D {
  const _Object3DLine(
    Point3D a,
    Point3D b, {
    Line3DKind lineKind = Line3DKind.segment,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.line,
         lineKind: lineKind,
         pointA: a,
         pointB: b,
         color: color,
         opacity: opacity,
         label: label,
       );
}

class _Object3DPlane extends Object3D {
  const _Object3DPlane({
    double a = 0,
    double b = 0,
    double c = 1,
    double d = 0,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.plane,
         planeA: a,
         planeB: b,
         planeC: c,
         planeD: d,
         color: color,
         opacity: opacity,
         label: label,
       );
}

class _Object3DSurface extends Object3D {
  const _Object3DSurface({
    required List<Point3D> vertices,
    required List<int> indices,
    List<Vector3D>? normals,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    double edgeWidth = 1.5,
    bool showEdges = true,
    String? label,
  }) : super._(
         type: Object3DType.surface,
         vertices: vertices,
         indices: indices,
         normals: normals,
         color: color,
         opacity: opacity,
         edgeWidth: edgeWidth,
         showEdges: showEdges,
         label: label,
       );
}

class _Object3DSphere extends Object3D {
  const _Object3DSphere({
    Point3D center = Point3D.origin,
    double radius = 1,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.sphere,
         sphereCenter: center,
         sphereRadius: radius,
         color: color,
         opacity: opacity,
         label: label,
       );
}

class _Object3DPolyhedron extends Object3D {
  const _Object3DPolyhedron({
    required List<Point3D> vertices,
    required List<int> indices,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    double edgeWidth = 1.5,
    bool showEdges = true,
    String? label,
  }) : super._(
         type: Object3DType.polyhedron,
         vertices: vertices,
         indices: indices,
         color: color,
         opacity: opacity,
         edgeWidth: edgeWidth,
         showEdges: showEdges,
         label: label,
       );
}

class _Object3DVector extends Object3D {
  const _Object3DVector({
    required Vector3D vector,
    Point3D? origin,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.vector,
         point: origin ?? Point3D.origin,
         vector: vector,
         color: color,
         opacity: opacity,
         label: label,
       );
}

class _Object3DCurve extends Object3D {
  const _Object3DCurve({
    required List<Point3D> points,
    List<int> curveStarts = const [],
    Conic3D? conic,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
    String? label,
  }) : super._(
         type: Object3DType.curve,
         vertices: points,
         curveStarts: curveStarts,
         conic: conic,
         color: color,
         opacity: opacity,
         label: label,
       );
}

// ======================================================================
// SurfaceMesh — utility for creating mesh geometry
// ======================================================================

/// A triangle mesh representing a surface.
///
/// Contains vertices, triangle indices, and optionally normals.
/// Created by sampling a function z = f(x, y) over a grid.
class SurfaceMesh {
  final List<Point3D> vertices;
  final List<int> indices;
  final List<Vector3D> normals;
  final Point3D boundingBoxMin;
  final Point3D boundingBoxMax;

  const SurfaceMesh({
    required this.vertices,
    required this.indices,
    this.normals = const [],
    this.boundingBoxMin = Point3D.origin,
    this.boundingBoxMax = Point3D.origin,
  });

  /// Create a grid mesh from a height function z = f(x, y).
  ///
  /// Samples [f] on a [gridX] × [gridY] grid spanning
  /// [xMin]..[xMax] × [yMin]..[yMax].
  /// Returns a triangulated mesh with vertex normals.
  static SurfaceMesh fromFunction({
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
    required int gridX,
    required int gridY,
    required double Function(double x, double y) f,
  }) {
    if (gridX < 1 || gridY < 1) {
      throw ArgumentError('gridX and gridY must be at least 1');
    }
    if (![xMin, xMax, yMin, yMax].every((value) => value.isFinite) ||
        xMin >= xMax ||
        yMin >= yMax) {
      throw ArgumentError('mesh bounds must be finite and increasing');
    }

    final cols = gridX + 1;
    final rows = gridY + 1;
    final vertices = <Point3D>[];
    final normals = <Vector3D>[];
    final indices = <int>[];

    final stepX = (xMax - xMin) / gridX;
    final stepY = (yMax - yMin) / gridY;

    // Evaluate f at each grid point
    final zValues = <List<double?>>[];
    for (int ix = 0; ix < cols; ix++) {
      final row = <double?>[];
      for (int iy = 0; iy < rows; iy++) {
        final x = xMin + ix * stepX;
        final y = yMin + iy * stepY;
        try {
          final z = f(x, y);
          row.add(z.isFinite ? z : null);
        } catch (_) {
          row.add(null);
        }
      }
      zValues.add(row);
    }

    // Keep a grid-to-vertex map so invalid samples can be omitted while
    // triangles that touch them are left open.
    final gridVertexIndices = List.generate(
      cols,
      (_) => List<int?>.filled(rows, null),
    );
    for (int iy = 0; iy < rows; iy++) {
      for (int ix = 0; ix < cols; ix++) {
        final z = zValues[ix][iy];
        if (z == null) continue;
        final x = xMin + ix * stepX;
        final y = yMin + iy * stepY;
        gridVertexIndices[ix][iy] = vertices.length;
        vertices.add(Point3D(x, y, z));
      }
    }

    int? vertexAt(int x, int y) => gridVertexIndices[x][y];

    // Build triangle indices only when every referenced sample is finite.
    for (int iy = 0; iy < gridY; iy++) {
      for (int ix = 0; ix < gridX; ix++) {
        final i0 = vertexAt(ix, iy);
        final i1 = vertexAt(ix, iy + 1);
        final i2 = vertexAt(ix + 1, iy);
        final i3 = vertexAt(ix + 1, iy + 1);

        if (i0 != null && i1 != null && i2 != null) {
          indices.addAll([i0, i2, i1]);
        }
        if (i1 != null && i2 != null && i3 != null) {
          indices.addAll([i2, i3, i1]);
        }
      }
    }

    if (vertices.isEmpty) {
      return const SurfaceMesh(vertices: [], indices: []);
    }

    // Compute vertex normals (average of face normals)
    final faceNormals = <Vector3D>[];
    for (int i = 0; i < indices.length; i += 3) {
      final p0 = vertices[indices[i]];
      final p1 = vertices[indices[i + 1]];
      final p2 = vertices[indices[i + 2]];
      final e1 = p1 - p0;
      final e2 = p2 - p0;
      faceNormals.add(e1.cross(e2).normalized());
    }

    final vertexNormals = List<Vector3D>.filled(vertices.length, Vector3D.zero);
    for (int i = 0; i < indices.length; i += 3) {
      final fn = faceNormals[i ~/ 3];
      vertexNormals[indices[i]] = vertexNormals[indices[i]] + fn;
      vertexNormals[indices[i + 1]] = vertexNormals[indices[i + 1]] + fn;
      vertexNormals[indices[i + 2]] = vertexNormals[indices[i + 2]] + fn;
    }
    for (int i = 0; i < vertexNormals.length; i++) {
      vertexNormals[i] = vertexNormals[i].normalized();
    }
    normals.addAll(vertexNormals);

    // Compute bounding box
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.z < minZ) minZ = v.z;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
      if (v.z > maxZ) maxZ = v.z;
    }

    return SurfaceMesh(
      vertices: vertices,
      indices: indices,
      normals: normals,
      boundingBoxMin: Point3D(minX, minY, minZ),
      boundingBoxMax: Point3D(maxX, maxY, maxZ),
    );
  }
}
