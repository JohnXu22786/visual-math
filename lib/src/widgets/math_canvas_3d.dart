import 'dart:math' as dart_math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../models/math_3d_object.dart';
import '../models/formula_entry.dart';
import '../models/math_3d_scene.dart';
import '../models/math_3d_tool.dart';
import '../models/math_3d_relationship.dart';
import '../models/math_3d_construction.dart';
import 'math_ui_tokens.dart';

// Re-export so pages can use these without direct imports
export '../models/math_3d_scene.dart' show ProjectionType;
export '../models/math_3d_tool.dart' show ConstructionTool;

/// Callback types for canvas → parent communication.
typedef On3DReady = void Function();
typedef On3DViewportChange = void Function();
typedef On3DObjectCreated = void Function(Object3D object);
typedef On3DSceneChange = void Function();
typedef On3DSelectionChange = void Function(Object3D? object);
typedef On3DToolInstruction = void Function(String instruction);

const double _planeGridRange = 5.0;
const double _pointMarkerRadius = 4.0;

Color solidEdgeContrastColor(Color fillColor) {
  final target = fillColor.computeLuminance() < 0.5
      ? Colors.white
      : Colors.black;
  return Color.lerp(fillColor.withValues(alpha: 1), target, 0.45)!;
}

double _perspectiveFarPlane(
  List<Object3D> objects,
  Point3D target,
  double cameraDistance, {
  Object3D? preview,
  bool includeHidden = false,
}) {
  var furthestDistance = 0.0;
  void include(Point3D point, {double padding = 0}) {
    final distance = point.distanceTo(target) + padding;
    if (distance.isFinite) {
      furthestDistance = dart_math.max(furthestDistance, distance).toDouble();
    }
  }

  for (final object in [...objects, if (preview != null) preview]) {
    if (!includeHidden && !object.visible) continue;
    switch (object.type) {
      case Object3DType.point:
        include(object.point);
      case Object3DType.line:
        include(object.pointA);
        if (object.lineKind == Line3DKind.segment) include(object.pointB);
      case Object3DType.plane:
        final equation = _normalizedPlaneEquation(object);
        if (equation == null) break;
        final a = equation.normal.x;
        final b = equation.normal.y;
        final c = equation.normal.z;
        final d = equation.d;
        if (c.abs() >= a.abs() && c.abs() >= b.abs()) {
          for (final x in [-_planeGridRange, _planeGridRange]) {
            for (final y in [-_planeGridRange, _planeGridRange]) {
              include(Point3D(x, y, (d - a * x - b * y) / c));
            }
          }
        } else if (b.abs() >= a.abs()) {
          for (final x in [-_planeGridRange, _planeGridRange]) {
            for (final z in [-_planeGridRange, _planeGridRange]) {
              include(Point3D(x, (d - a * x - c * z) / b, z));
            }
          }
        } else {
          for (final y in [-_planeGridRange, _planeGridRange]) {
            for (final z in [-_planeGridRange, _planeGridRange]) {
              include(Point3D((d - b * y - c * z) / a, y, z));
            }
          }
        }
      case Object3DType.surface:
      case Object3DType.polyhedron:
      case Object3DType.curve:
        for (final point in object.vertices) {
          include(point);
        }
      case Object3DType.sphere:
        include(object.sphereCenter, padding: object.sphereRadius.abs());
      case Object3DType.vector:
        include(object.point);
        include(object.point + object.vector);
    }
  }

  final margin = dart_math.max(1.0, furthestDistance * 0.01).toDouble();
  final far = cameraDistance + furthestDistance + margin;
  if (!far.isFinite) return double.maxFinite;
  return dart_math.max(1000.0, far).toDouble();
}

List<Point3D> _clipPolygonToDepthRange(
  List<Point3D> polygon,
  Camera3D camera,
  Projection3D projection,
) {
  if (projection.type != ProjectionType.perspective || polygon.isEmpty) {
    return polygon;
  }

  List<Point3D> clipAgainst(
    List<Point3D> input,
    double boundary,
    bool keepGreater,
  ) {
    if (input.isEmpty) return input;
    final output = <Point3D>[];
    var previous = input.last;
    var previousDepth = worldToScreen(previous, camera, projection).z;
    var previousInside = keepGreater
        ? previousDepth >= boundary
        : previousDepth <= boundary;
    for (final current in input) {
      final currentDepth = worldToScreen(current, camera, projection).z;
      final currentInside = keepGreater
          ? currentDepth >= boundary
          : currentDepth <= boundary;
      if (currentInside != previousInside) {
        final fraction =
            (boundary - previousDepth) / (currentDepth - previousDepth);
        output.add(previous + (current - previous) * fraction);
      }
      if (currentInside) output.add(current);
      previous = current;
      previousDepth = currentDepth;
      previousInside = currentInside;
    }
    return output;
  }

  final nearClipped = clipAgainst(polygon, projection.near, true);
  return clipAgainst(nearClipped, projection.far, false);
}

({Vector3D normal, double d, double normalSquared, Point3D origin})?
_normalizedPlaneEquation(Object3D plane) {
  final a = plane.planeA;
  final b = plane.planeB;
  final c = plane.planeC;
  final d = plane.planeD;
  if (!a.isFinite || !b.isFinite || !c.isFinite || !d.isFinite) return null;
  final scale = dart_math
      .max(a.abs(), dart_math.max(b.abs(), c.abs()))
      .toDouble();
  if (scale == 0 || !scale.isFinite) return null;
  final normal = Vector3D(a / scale, b / scale, c / scale);
  final normalizedD = d / scale;
  final normalSquared = normal.dot(normal);
  if (!normalizedD.isFinite || !normalSquared.isFinite || normalSquared == 0) {
    return null;
  }
  return (
    normal: normal,
    d: normalizedD,
    normalSquared: normalSquared,
    origin: Point3D(
      normal.x * normalizedD / normalSquared,
      normal.y * normalizedD / normalSquared,
      normal.z * normalizedD / normalSquared,
    ),
  );
}

bool _withinRenderedPlaneGrid(Object3D plane, Point3D point) {
  const tolerance = 1e-9;
  final equation = _normalizedPlaneEquation(plane);
  if (equation == null) return false;
  final normal = equation.normal;
  if (normal.z.abs() >= normal.x.abs() && normal.z.abs() >= normal.y.abs()) {
    return point.x.abs() <= _planeGridRange + tolerance &&
        point.y.abs() <= _planeGridRange + tolerance;
  }
  if (normal.y.abs() >= normal.x.abs()) {
    return point.x.abs() <= _planeGridRange + tolerance &&
        point.z.abs() <= _planeGridRange + tolerance;
  }
  return point.y.abs() <= _planeGridRange + tolerance &&
      point.z.abs() <= _planeGridRange + tolerance;
}

bool _pointInTriangle3D(Point3D point, Point3D a, Point3D b, Point3D c) {
  final ab = b - a;
  final ac = c - a;
  final ap = point - a;
  final abLength = ab.magnitude;
  final acLength = ac.magnitude;
  if (!abLength.isFinite ||
      !acLength.isFinite ||
      abLength == 0 ||
      acLength == 0) {
    return false;
  }
  final unitAb = ab * (1 / abLength);
  final unitAc = ac * (1 / acLength);
  final sine = unitAb.cross(unitAc).magnitude;
  if (!sine.isFinite || sine < 1e-9) return false;
  final dot01 = unitAb.dot(unitAc);
  final dot20 = ap.dot(unitAb);
  final dot21 = ap.dot(unitAc);
  final denominator = sine * sine;
  final u = (dot20 - dot01 * dot21) / (denominator * abLength);
  final v = (dot21 - dot01 * dot20) / (denominator * acLength);
  return u >= -1e-8 && v >= -1e-8 && u + v <= 1 + 1e-8;
}

Vector3D? _normalizedTriangleNormal(Point3D a, Point3D b, Point3D c) {
  final ab = b - a;
  final ac = c - a;
  final abLength = ab.magnitude;
  final acLength = ac.magnitude;
  if (!abLength.isFinite ||
      !acLength.isFinite ||
      abLength == 0 ||
      acLength == 0) {
    return null;
  }
  final cross = (ab * (1 / abLength)).cross(ac * (1 / acLength));
  final sine = cross.magnitude;
  if (!sine.isFinite || sine < 1e-9) return null;
  return cross * (1 / sine);
}

enum PointDragMode { plane, height }

enum _NavigationGesture { none, orbit, pan }

class _SolidSourceDependency {
  final ConstructionTool tool;
  final List<Point3D> points;
  final List<int?> sourcePointIndices;
  final Vector3D workingPlaneNormal;
  final int polygonSides;

  _SolidSourceDependency({
    required this.tool,
    required List<Point3D> points,
    required List<int?> sourcePointIndices,
    required this.workingPlaneNormal,
    required this.polygonSides,
  }) : points = List.of(points),
       sourcePointIndices = List.of(sourcePointIndices);
}

enum _ViewAction {
  toggleAxes,
  togglePlane,
  toggleGrid,
  parallelProjection,
  perspectiveProjection,
  standardView,
  topView,
  frontView,
  sideView,
}

/// A 3D rendering canvas using Flutter's CustomPainter.
///
/// Renders a 3D scene with:
/// - Orbital camera controls (drag to rotate, scroll to zoom)
/// - Coordinate axes with labels
/// - Coordinate plane and optional grid on the xOy-plane
/// - Points, lines, planes, surfaces, spheres, polyhedra
/// - Parallel and perspective projection
///
/// Uses painter's algorithm (back-to-front sorting) for correct occlusion
/// since we don't have a depth buffer on 2D Canvas.
class MathCanvas3D extends StatefulWidget {
  final On3DReady? onReady;
  final On3DViewportChange? onViewportChange;
  final On3DObjectCreated? onObjectCreated;
  final On3DSceneChange? onSceneChanged;
  final On3DSelectionChange? onSelectionChanged;
  final On3DToolInstruction? onToolInstruction;
  final ConstructionTool currentTool;
  final int polygonSides;
  final bool allowTouchGestures;
  final bool allowMouseGestures;
  final String Function(String sourceText)? labelResolver;
  final Widget Function(BuildContext context, Widget dialog)? dialogBuilder;
  final Widget Function(BuildContext context, String message)? errorBuilder;

  const MathCanvas3D({
    super.key,
    this.onReady,
    this.onViewportChange,
    this.onObjectCreated,
    this.onSceneChanged,
    this.onSelectionChanged,
    this.onToolInstruction,
    this.currentTool = ConstructionTool.move,
    this.polygonSides = 6,
    this.allowTouchGestures = true,
    this.allowMouseGestures = true,
    this.labelResolver,
    this.dialogBuilder,
    this.errorBuilder,
  });

  @override
  State<MathCanvas3D> createState() => MathCanvas3DState();
}

/// The state class for [MathCanvas3D], exposing methods for parent control.
class MathCanvas3DState extends State<MathCanvas3D> {
  static const double _defaultDistance = 10;

  String _label(String source) => widget.labelResolver?.call(source) ?? source;

  Widget _dialog(BuildContext context, Widget child) =>
      widget.dialogBuilder?.call(context, child) ?? child;

  Widget _error(String message) =>
      widget.errorBuilder?.call(context, _label(message)) ??
      Text(_label(message));
  static const double _defaultTheta = dart_math.pi * 0.75;
  static const double _defaultPhi = dart_math.pi / 6;
  static const double _orthographicDistanceScale = 0.6;
  static const double _hitScreenDistanceTieTolerance = 8;
  static const double _hitDepthTieTolerance = 1e-6;

  // Camera state
  double _cameraDistance = _defaultDistance;
  double _cameraTheta = _defaultTheta;
  double _cameraPhi = _defaultPhi;
  Point3D _cameraTarget = Point3D.origin;

  // Visual state
  ProjectionType _projectionType = ProjectionType.parallel;
  bool _showAxes = true;
  bool _showPlane = true;
  bool _showGrid = false;
  bool _showLabels = true;

  // Scene objects
  final List<Object3D> _objects = [];
  int? _selectedObjectIndex;
  int _objectsVersion = 0;
  bool _completingConstruction = false;
  final Map<int, int> _pointAttachments = {};
  final Map<int, _SolidSourceDependency> _constructionDependencies = {};
  int _nextDocumentObjectId = 0;
  int? _styleSourceIndex;
  int? _intersectionSourceIndex;
  int? _pointIntersectionSourceIndex;
  int? _conicSourceIndex;
  int? _attachmentPointIndex;

  /// Get the list of objects (unmodifiable).
  List<Object3D> get objects => List.unmodifiable(_objects);

  String _newDocumentObjectId(Set<String> used) {
    String id;
    do {
      id = 'object-${_nextDocumentObjectId++}';
    } while (used.contains(id));
    return id;
  }

  void ensureDocumentIds() {
    final used = _objects
        .map((object) => object.documentId)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (var i = 0; i < _objects.length; i++) {
      if (_objects[i].documentId.isNotEmpty) continue;
      final id = _newDocumentObjectId(used);
      used.add(id);
      _objects[i] = _objects[i].copyWith(documentId: id);
    }
  }

  List<PointAttachment> get documentPointAttachments {
    ensureDocumentIds();
    return [
      for (final entry in _pointAttachments.entries)
        if (entry.key < _objects.length && entry.value < _objects.length)
          PointAttachment(
            pointId: _objects[entry.key].documentId,
            targetId: _objects[entry.value].documentId,
          ),
    ];
  }

  List<ConstructionDependency> get documentConstructionDependencies {
    ensureDocumentIds();
    return [
      for (final entry in _constructionDependencies.entries)
        if (entry.key < _objects.length)
          ConstructionDependency(
            objectId: _objects[entry.key].documentId,
            tool: entry.value.tool,
            inputPoints: entry.value.points,
            sourcePointIds: [
              for (final index in entry.value.sourcePointIndices)
                index != null && index >= 0 && index < _objects.length
                    ? _objects[index].documentId
                    : null,
            ],
            workingPlaneNormal: entry.value.workingPlaneNormal,
            polygonSides: entry.value.polygonSides,
          ),
    ];
  }

  void restoreDocumentRelationships({
    required List<PointAttachment> pointAttachments,
    required List<ConstructionDependency> constructionDependencies,
  }) {
    ensureDocumentIds();
    final indexById = {
      for (var i = 0; i < _objects.length; i++) _objects[i].documentId: i,
    };
    _pointAttachments
      ..clear()
      ..addEntries(
        pointAttachments.map(
          (relation) => MapEntry(
            indexById[relation.pointId]!,
            indexById[relation.targetId]!,
          ),
        ),
      );
    _constructionDependencies
      ..clear()
      ..addEntries(
        constructionDependencies.map(
          (dependency) => MapEntry(
            indexById[dependency.objectId]!,
            _SolidSourceDependency(
              tool: dependency.tool,
              points: dependency.inputPoints,
              sourcePointIndices: [
                for (final id in dependency.sourcePointIds)
                  id == null ? null : indexById[id],
              ],
              workingPlaneNormal: dependency.workingPlaneNormal,
              polygonSides: dependency.polygonSides,
            ),
          ),
        ),
      );
  }

  // Construction state
  ConstructionState? _construction;
  Object3D? _constructionPreview;
  final List<int?> _constructionPointSources = [];
  ConstructionTool _currentTool = ConstructionTool.move;

  // Construction gesture tracking (for 3D point placement with height)
  Point3D? _constGroundPos; // ground (z=0) position during construction
  double _constHeight = 0; // height offset from ground during drag
  Offset? _constStartPoint; // screen position where point gesture started
  Vector3D? _constPlaneNormal; // stable working-plane normal for this gesture
  bool _constPointPlaced = false; // whether the point was committed

  // Point editing uses the original pointer-down position, avoiding gesture
  // slop offsets and keeping mouse and touch behavior identical.
  int? _selectedPointIndex;
  PointDragMode _pointDragMode = PointDragMode.plane;
  int? _pointEditPointer;
  Object3D? _pointBeforeDrag;
  Offset? _pointerDownPosition;
  bool _pointWasSelected = false;
  bool _pointMoved = false;
  bool _objectActionGestureMoved = false;
  bool _suppressScale = false;
  bool _multiTouch = false;
  final Set<int> _activePointers = {};

  Object3D? get selectedPoint =>
      _selectedPointIndex == null ? null : _objects[_selectedPointIndex!];
  Object3D? get selectedObject =>
      _selectedObjectIndex == null ? null : _objects[_selectedObjectIndex!];
  PointDragMode get pointDragMode => _pointDragMode;

  void updateSelectedObjectStyle({
    int? color,
    double? edgeWidth,
    bool? showEdges,
  }) {
    final index = _selectedObjectIndex;
    if (index == null || index < 0 || index >= _objects.length) return;
    setState(() {
      _objects[index] = _objects[index].copyWith(
        color: color,
        edgeWidth: edgeWidth,
        showEdges: showEdges,
      );
      _objectsVersion++;
    });
    widget.onSceneChanged?.call();
  }

  void deleteSelectedObject() {
    final index = _selectedObjectIndex;
    if (index == null || index < 0 || index >= _objects.length) return;
    _removeObjectAt(index);
  }

  // Gesture state
  Offset? _lastFocalPoint;
  double?
  _initialScaleDistance; // camera distance at gesture start (for stable zoom)
  final FocusNode _focusNode = FocusNode(debugLabel: 'MathCanvas3D');
  int? _mousePointer;
  Offset? _lastMousePosition;
  _NavigationGesture _mouseGesture = _NavigationGesture.none;
  double? _panZoomInitialDistance;
  bool _isReady = false;

  // Canvas size
  double _canvasWidth = 1;
  double _canvasHeight = 1;

  // ==================================================================
  // Public API
  // ==================================================================

  /// Get the current camera state.
  Camera3D get camera => Camera3D(
    target: _cameraTarget,
    distance: _cameraDistance,
    theta: _cameraTheta,
    phi: _cameraPhi,
  );

  /// Replace the current camera state.
  void setCamera(Camera3D camera) {
    if (!camera.distance.isFinite ||
        camera.distance <= 0 ||
        !camera.theta.isFinite ||
        !camera.phi.isFinite ||
        !camera.target.x.isFinite ||
        !camera.target.y.isFinite ||
        !camera.target.z.isFinite) {
      return;
    }
    setState(() {
      _cameraTarget = camera.target;
      _cameraDistance = camera.distance.clamp(0.1, 1000).toDouble();
      _cameraTheta = camera.theta;
      _cameraPhi = camera.phi.clamp(-dart_math.pi * 0.49, dart_math.pi * 0.49);
    });
    widget.onViewportChange?.call();
  }

  /// Get the current projection type.
  ProjectionType get projectionType => _projectionType;

  /// Whether axes are visible.
  bool get showAxes => _showAxes;

  /// Whether grid is visible.
  bool get showGrid => _showGrid;

  /// Whether the xOy coordinate plane is visible.
  bool get showPlane => _showPlane;

  bool get showLabels => _showLabels;

  /// Restore persisted canvas display toggles.
  void setDisplaySettings({
    required bool showAxes,
    required bool showPlane,
    required bool showGrid,
    required bool showLabels,
  }) {
    setState(() {
      _showAxes = showAxes;
      _showPlane = showPlane;
      _showGrid = showGrid;
      _showLabels = showLabels;
    });
  }

  /// Number of objects in the scene.
  int get objectCount => _objects.length;

  /// Set the projection type.
  void setProjectionType(ProjectionType type) {
    setState(() {
      _projectionType = type;
    });
    widget.onViewportChange?.call();
  }

  /// Toggle axis visibility.
  void toggleAxes() {
    setState(() {
      _showAxes = !_showAxes;
    });
    widget.onViewportChange?.call();
  }

  /// Toggle grid visibility.
  void toggleGrid() {
    setState(() {
      _showGrid = !_showGrid;
    });
    widget.onViewportChange?.call();
  }

  /// Toggle xOy-plane visibility.
  void togglePlane() {
    setState(() {
      _showPlane = !_showPlane;
    });
    widget.onViewportChange?.call();
  }

  /// Run a toolbox command that does not need a canvas click.
  void performToolCommand(ConstructionTool tool) {
    switch (tool) {
      case ConstructionTool.showHideLabels:
        setState(() => _showLabels = !_showLabels);
      case ConstructionTool.viewDirection:
        _chooseViewDirection();
      default:
        break;
    }
    widget.onSceneChanged?.call();
  }

  Future<void> _chooseViewDirection() async {
    final action = await showDialog<_ViewAction>(
      context: context,
      builder: (dialogContext) => _dialog(
        dialogContext,
        SimpleDialog(
          title: Text(_label('视图方向')),
          children: [
            _viewDirectionOption(
              dialogContext,
              _ViewAction.standardView,
              '标准视图',
            ),
            _viewDirectionOption(dialogContext, _ViewAction.topView, '俯视 xOy'),
            _viewDirectionOption(
              dialogContext,
              _ViewAction.frontView,
              '正视 xOz',
            ),
            _viewDirectionOption(dialogContext, _ViewAction.sideView, '侧视 yOz'),
          ],
        ),
      ),
    );
    if (action != null && mounted) _handleViewAction(action);
  }

  Widget _viewDirectionOption(
    BuildContext dialogContext,
    _ViewAction action,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(dialogContext).pop(action),
      child: Text(_label(label)),
    );
  }

  /// Reset the camera to the default view.
  void resetView() {
    setState(() {
      _cameraDistance = _defaultDistance;
      _cameraTheta = _defaultTheta;
      _cameraPhi = _defaultPhi;
      _cameraTarget = Point3D.origin;
    });
    widget.onViewportChange?.call();
  }

  /// Zoom in by one GeoGebra-style toolbar step.
  void zoomIn() => _zoomBy(1.2);

  /// Zoom out by one GeoGebra-style toolbar step.
  void zoomOut() => _zoomBy(1 / 1.2);

  /// Fit finite scene objects into the current viewport.
  void fitToView() {
    final points = <Point3D>[];
    for (final object in _objects) {
      if (!object.visible) continue;
      switch (object.type) {
        case Object3DType.point:
          points.add(object.point);
        case Object3DType.line:
          if (object.lineKind == Line3DKind.segment) {
            points.addAll([object.pointA, object.pointB]);
          } else {
            // The second point defines direction for a ray or infinite line;
            // using it as a bound would make fit depend on that direction's
            // arbitrary magnitude.
            points.add(object.pointA);
          }
        case Object3DType.plane:
          final equation = _normalizedPlaneEquation(object);
          if (equation == null) break;
          final a = equation.normal.x;
          final b = equation.normal.y;
          final c = equation.normal.z;
          final d = equation.d;
          if (c.abs() >= a.abs() && c.abs() >= b.abs()) {
            for (final x in [-_planeGridRange, _planeGridRange]) {
              for (final y in [-_planeGridRange, _planeGridRange]) {
                points.add(Point3D(x, y, (d - a * x - b * y) / c));
              }
            }
          } else if (b.abs() >= a.abs()) {
            for (final x in [-_planeGridRange, _planeGridRange]) {
              for (final z in [-_planeGridRange, _planeGridRange]) {
                points.add(Point3D(x, (d - a * x - c * z) / b, z));
              }
            }
          } else {
            for (final y in [-_planeGridRange, _planeGridRange]) {
              for (final z in [-_planeGridRange, _planeGridRange]) {
                points.add(Point3D((d - b * y - c * z) / a, y, z));
              }
            }
          }
        case Object3DType.surface:
        case Object3DType.polyhedron:
        case Object3DType.curve:
          points.addAll(object.vertices);
        case Object3DType.sphere:
          final c = object.sphereCenter;
          final r = object.sphereRadius.abs();
          points.addAll([
            for (final x in [-r, r])
              for (final y in [-r, r])
                for (final z in [-r, r]) Point3D(c.x + x, c.y + y, c.z + z),
          ]);
        case Object3DType.vector:
          points.addAll([object.point, object.point + object.vector]);
      }
    }

    if (points.isEmpty) {
      resetView();
      return;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final point in points) {
      if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) continue;
      minX = dart_math.min(minX, point.x);
      minY = dart_math.min(minY, point.y);
      minZ = dart_math.min(minZ, point.z);
      maxX = dart_math.max(maxX, point.x);
      maxY = dart_math.max(maxY, point.y);
      maxZ = dart_math.max(maxZ, point.z);
    }
    if (!minX.isFinite) return;

    final maxExtent = dart_math.max(
      dart_math.max(maxX - minX, maxY - minY),
      maxZ - minZ,
    );
    var target = Point3D(
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2,
    );
    var cameraDistance = dart_math.max(4.0, maxExtent * 1.35).toDouble();
    if (_canvasWidth > 0 && _canvasHeight > 0) {
      final viewMatrix = camera.viewMatrix();
      final right = Vector3D(viewMatrix[0], viewMatrix[4], viewMatrix[8]);
      final up = Vector3D(viewMatrix[1], viewMatrix[5], viewMatrix[9]);
      final forward = (camera.target - camera.position).normalized();
      var minRight = double.infinity;
      var minUp = double.infinity;
      var maxRight = double.negativeInfinity;
      var maxUp = double.negativeInfinity;
      for (final point in points) {
        if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
          continue;
        }
        final offset = point - target;
        final projectedRight = offset.dot(right);
        final projectedUp = offset.dot(up);
        if (!projectedRight.isFinite || !projectedUp.isFinite) continue;
        minRight = dart_math.min(minRight, projectedRight);
        maxRight = dart_math.max(maxRight, projectedRight);
        minUp = dart_math.min(minUp, projectedUp);
        maxUp = dart_math.max(maxUp, projectedUp);
      }
      if (minRight.isFinite && minUp.isFinite) {
        final aspect = _canvasWidth / _canvasHeight;
        final halfWidth = (maxRight - minRight) / 2;
        final halfHeight = (maxUp - minUp) / 2;
        final centerRight = (minRight + maxRight) / 2;
        final centerUp = (minUp + maxUp) / 2;
        target = target + right * centerRight + up * centerUp;
        if (_projectionType == ProjectionType.parallel) {
          final requiredScale = dart_math.max(halfHeight, halfWidth / aspect);
          cameraDistance = dart_math
              .max(4.0, requiredScale * 1.1 / _orthographicDistanceScale)
              .toDouble();
        } else {
          const fitMargin = 0.9;
          final tanHalfFov = dart_math.tan(dart_math.pi / 6);
          var requiredDistance = 4.0;
          for (final point in points) {
            if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
              continue;
            }
            final offset = point - target;
            final forwardOffset = offset.dot(forward);
            final projectedRight = offset.dot(right).abs();
            final projectedUp = offset.dot(up).abs();
            requiredDistance = dart_math
                .max(
                  requiredDistance,
                  projectedRight / (fitMargin * tanHalfFov * aspect) -
                      forwardOffset,
                )
                .toDouble();
            requiredDistance = dart_math
                .max(
                  requiredDistance,
                  projectedUp / (fitMargin * tanHalfFov) - forwardOffset,
                )
                .toDouble();
            requiredDistance = dart_math
                .max(requiredDistance, 0.1 - forwardOffset)
                .toDouble();
          }
          cameraDistance = requiredDistance;
        }
      }
    }
    setState(() {
      _cameraTarget = target;
      _cameraDistance = cameraDistance;
    });
    widget.onViewportChange?.call();
  }

  /// Set the objects to render.
  void setObjects(List<Object3D> objects, {bool notify = true}) {
    final hadSelection =
        _selectedObjectIndex != null || _selectedPointIndex != null;
    final preservesExistingObjects =
        objects.length >= _objects.length &&
        List.generate(
          _objects.length,
          (index) => index,
        ).every((index) => identical(objects[index], _objects[index]));
    setState(() {
      _selectedPointIndex = null;
      _pointEditPointer = null;
      if (!preservesExistingObjects ||
          _selectedObjectIndex == null ||
          _selectedObjectIndex! >= objects.length) {
        _selectedObjectIndex = null;
      }
      if (!preservesExistingObjects) {
        _pointAttachments.clear();
        _constructionDependencies.clear();
        _attachmentPointIndex = null;
        _styleSourceIndex = null;
        _intersectionSourceIndex = null;
        _pointIntersectionSourceIndex = null;
        _conicSourceIndex = null;
      }
      _objects
        ..clear()
        ..addAll(objects);
      _objectsVersion++;
    });
    if (notify && !_completingConstruction) widget.onSceneChanged?.call();
    if (notify &&
        hadSelection &&
        _selectedObjectIndex == null &&
        _selectedPointIndex == null) {
      widget.onSelectionChanged?.call(null);
    }
  }

  /// Replace plotted objects while retaining constructed objects and their
  /// relationships. Remove from the end so construction indices stay valid.
  void replaceFormulaObjects(List<Object3D> objects) {
    final hadSelection =
        _selectedObjectIndex != null || _selectedPointIndex != null;
    final attachments = documentPointAttachments;
    final dependencies = documentConstructionDependencies;
    for (var i = _objects.length - 1; i >= 0; i--) {
      if (_objects[i].formulaRowId != null) {
        _removeObjectAt(i, notify: false);
      }
    }
    setObjects([..._objects, ...objects], notify: false);
    final ids = _objects.map((object) => object.documentId).toSet();
    restoreDocumentRelationships(
      pointAttachments: attachments
          .where(
            (attachment) =>
                ids.contains(attachment.pointId) &&
                ids.contains(attachment.targetId),
          )
          .toList(),
      constructionDependencies: [
        for (final dependency in dependencies)
          if (ids.contains(dependency.objectId))
            ConstructionDependency(
              objectId: dependency.objectId,
              tool: dependency.tool,
              inputPoints: dependency.inputPoints,
              sourcePointIds: [
                for (final id in dependency.sourcePointIds)
                  if (id == null || ids.contains(id)) id else null,
              ],
              workingPlaneNormal: dependency.workingPlaneNormal,
              polygonSides: dependency.polygonSides,
            ),
      ],
    );
    for (var i = 0; i < _objects.length; i++) {
      if (objects.any(
        (object) => object.documentId == _objects[i].documentId,
      )) {
        _propagateConstructionAndAttachmentMoves(i);
      }
    }
    final construction = _construction;
    if (construction != null) {
      for (var i = 0; i < _constructionPointSources.length; i++) {
        final source = _constructionPointSources[i];
        if (source != null &&
            source >= 0 &&
            source < _objects.length &&
            _objects[source].type == Object3DType.point) {
          construction.updatePoint(i, _objects[source].point);
        }
      }
      _constructionPreview = null;
    }
    if (hadSelection &&
        _selectedPointIndex == null &&
        _selectedObjectIndex == null) {
      widget.onSelectionChanged?.call(null);
    }
    widget.onSceneChanged?.call();
  }

  /// Clear all objects.
  void clearObjects() {
    final hadSelection =
        _selectedObjectIndex != null || _selectedPointIndex != null;
    setState(() {
      _selectedPointIndex = null;
      _selectedObjectIndex = null;
      _pointEditPointer = null;
      _pointAttachments.clear();
      _constructionDependencies.clear();
      _attachmentPointIndex = null;
      _styleSourceIndex = null;
      _intersectionSourceIndex = null;
      _pointIntersectionSourceIndex = null;
      _conicSourceIndex = null;
      _objects.clear();
      _objectsVersion++;
    });
    widget.onSceneChanged?.call();
    if (hadSelection) widget.onSelectionChanged?.call(null);
  }

  /// Add a surface mesh to the scene.
  void setSurface({
    required List<Point3D> vertices,
    required List<int> indices,
    List<Vector3D>? normals,
    int color = 0xFFAAAAAA,
    double opacity = 1.0,
  }) {
    setState(() {
      _objects.add(
        Object3D.surface(
          vertices: vertices,
          indices: indices,
          normals: normals,
          color: color,
          opacity: opacity,
        ),
      );
      _objectsVersion++;
    });
    widget.onSceneChanged?.call();
  }

  /// Get the current construction state (null if no tool is active).
  ConstructionState? get constructionState => _construction;

  /// Get the transient object shown while the active tool awaits input.
  Object3D? get constructionPreview => _constructionPreview;

  /// Get the active construction tool.
  ConstructionTool get activeTool => _currentTool;

  /// Get the current construction instruction.
  String? get constructionInstruction => _construction?.currentInstruction;

  /// Set the active construction tool.
  void setTool(ConstructionTool tool, {bool notifyInstruction = true}) {
    var sceneRolledBack = false;
    setState(() {
      sceneRolledBack = _cancelPointDrag();
      _selectedPointIndex = null;
      _selectedObjectIndex = null;
      _currentTool = tool;
      _styleSourceIndex = null;
      _intersectionSourceIndex = null;
      _pointIntersectionSourceIndex = null;
      _conicSourceIndex = null;
      _attachmentPointIndex = null;
      if (ToolInfo.all[tool]!.behavior != ToolBehavior.construction) {
        _construction = null;
        _constructionPreview = null;
        _constructionPointSources.clear();
      } else {
        _construction = ConstructionState(
          tool: tool,
          polygonSides: widget.polygonSides,
        );
        _constructionPreview = null;
        _constructionPointSources.clear();
      }
      _constPointPlaced = false;
      _constGroundPos = null;
      _constStartPoint = null;
      _constPlaneNormal = null;
      _constructionPreview = null;
    });
    if (sceneRolledBack) widget.onSceneChanged?.call();
    if (notifyInstruction) {
      widget.onToolInstruction?.call(
        _construction?.currentInstruction ?? ToolInfo.all[tool]!.tooltip,
      );
    }
    widget.onSelectionChanged?.call(null);
  }

  @override
  void initState() {
    super.initState();
    // Initialize tool from widget, which also creates construction state
    _currentTool = widget.currentTool;
    if (ToolInfo.all[_currentTool]!.behavior == ToolBehavior.construction) {
      _construction = ConstructionState(
        tool: _currentTool,
        polygonSides: widget.polygonSides,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isReady) {
        setState(() => _isReady = true);
        widget.onReady?.call();
      }
    });
  }

  @override
  void didUpdateWidget(MathCanvas3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTool != oldWidget.currentTool) {
      setTool(widget.currentTool, notifyInstruction: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onToolInstruction?.call(
            _construction?.currentInstruction ?? '',
          );
        }
      });
    } else if (widget.polygonSides != oldWidget.polygonSides &&
        widget.currentTool == ConstructionTool.regularPolygon) {
      setTool(widget.currentTool, notifyInstruction: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onToolInstruction?.call(
            _construction?.currentInstruction ?? '',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _construction = null;
    _focusNode.dispose();
    super.dispose();
  }

  // ==================================================================
  // Gesture handling
  // ==================================================================

  bool get _panModifierPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  double _pointSelectionDistance(
    Object3D object,
    Offset position,
    Offset anchor,
  ) {
    final label = object.label;
    if (!object.isTextAnnotation || label == null) {
      return (anchor - position).distance;
    }
    final painter = TextPainter(
      text: TextSpan(text: label, style: const TextStyle(fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    final bounds = Rect.fromLTWH(
      anchor.dx,
      anchor.dy,
      painter.width,
      painter.height,
    );
    final closestPoint = Offset(
      position.dx.clamp(bounds.left, bounds.right).toDouble(),
      position.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
    return (closestPoint - position).distance;
  }

  int? _hitPoint(Offset position) {
    int? nearest;
    var distance = 20.0;
    var nearestDepth = double.infinity;
    final projection = _currentProjection();
    for (var i = _objects.length - 1; i >= 0; i--) {
      final object = _objects[i];
      if (!object.visible ||
          object.type != Object3DType.point ||
          object.opacity <= 0 ||
          ((object.color >> 24) & 0xFF) == 0)
        continue;
      final screen = worldToScreen(object.point, camera, projection);
      if (!screen.x.isFinite || !screen.y.isFinite || !screen.z.isFinite) {
        continue;
      }
      if (_projectionType == ProjectionType.perspective &&
          (screen.z < projection.near || screen.z > projection.far)) {
        continue;
      }
      if (_projectionType == ProjectionType.perspective &&
          (object.point - camera.position).dot(
                (_cameraTarget - camera.position).normalized(),
              ) <=
              0)
        continue;
      final gap = _pointSelectionDistance(
        object,
        position,
        Offset(screen.x, screen.y),
      );
      if (gap >= 20 ||
          _isPointOccludedByOpaqueSurface(
            object.point,
            screenPosition: object.isTextAnnotation ? position : null,
          )) {
        continue;
      }
      final overlapsNearest =
          (gap - distance).abs() <= _hitScreenDistanceTieTolerance;
      if (nearest == null ||
          gap < distance - _hitScreenDistanceTieTolerance ||
          (overlapsNearest &&
              (screen.z < nearestDepth ||
                  (screen.z == nearestDepth && gap < distance)))) {
        nearest = i;
        distance = gap;
        nearestDepth = screen.z;
      }
    }
    return nearest;
  }

  bool _isPointOccludedByOpaqueSurface(
    Point3D point, {
    Offset? screenPosition,
  }) {
    final projection = _currentProjection();
    final projectedPoint = worldToScreen(point, camera, projection);
    if (!projectedPoint.x.isFinite ||
        !projectedPoint.y.isFinite ||
        !projectedPoint.z.isFinite) {
      return false;
    }
    final ray = _screenRay(
      screenPosition?.dx ?? projectedPoint.x,
      screenPosition?.dy ?? projectedPoint.y,
    );

    for (final object in _objects) {
      if (!object.visible ||
          (object.type != Object3DType.surface &&
              object.type != Object3DType.polyhedron) ||
          (((object.color >> 24) & 0xFF) / 255.0) * object.opacity < 0.999) {
        continue;
      }
      for (var i = 0; i + 2 < object.indices.length; i += 3) {
        final ia = object.indices[i];
        final ib = object.indices[i + 1];
        final ic = object.indices[i + 2];
        if (ia < 0 ||
            ia >= object.vertices.length ||
            ib < 0 ||
            ib >= object.vertices.length ||
            ic < 0 ||
            ic >= object.vertices.length) {
          continue;
        }
        final a = object.vertices[ia];
        final b = object.vertices[ib];
        final c = object.vertices[ic];
        final normal = _normalizedTriangleNormal(a, b, c);
        if (normal == null) continue;
        final hit = intersectRayPlane(
          ray,
          point: a,
          normal: normal,
          allowBehind: projection.type == ProjectionType.parallel,
        );
        if (hit == null) {
          continue;
        }
        final hitDepth = worldToScreen(hit, camera, projection).z;
        if (!hitDepth.isFinite || hitDepth >= projectedPoint.z - 1e-8) {
          continue;
        }
        if (projection.type == ProjectionType.perspective &&
            (hitDepth < projection.near || hitDepth > projection.far)) {
          continue;
        }
        if (_pointInTriangle3D(hit, a, b, c)) return true;
      }
    }
    return false;
  }

  int? _hitObjectIndex(
    Offset position, {
    bool includeHidden = false,
    bool includeTransparent = false,
  }) {
    final projection = _currentProjection(includeHidden: includeHidden);
    final ray = _screenRay(position.dx, position.dy);
    var nearestIndex = -1;
    var nearestDistance = 24.0;
    var nearestDepth = double.infinity;

    Offset screen(Point3D point) {
      final projected = worldToScreen(point, camera, projection);
      return Offset(projected.x, projected.y);
    }

    double depthAt(Point3D point) => worldToScreen(point, camera, projection).z;

    double segmentDistance(Offset point, Offset a, Offset b) {
      final direction = b - a;
      final lengthSquared = direction.distanceSquared;
      if (lengthSquared < 1e-9) return (point - a).distance;
      final t =
          (((point - a).dx * direction.dx + (point - a).dy * direction.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      return (point - (a + direction * t)).distance;
    }

    double depthOnSegmentAtScreen(
      Offset point,
      Point3D start,
      Point3D end,
      double startDepth,
      double endDepth,
    ) {
      final screenStart = screen(start);
      final screenEnd = screen(end);
      final screenDirection = screenEnd - screenStart;
      final screenLengthSquared = screenDirection.distanceSquared;
      var fraction = screenLengthSquared < 1e-9
          ? 0.0
          : (((point - screenStart).dx * screenDirection.dx +
                        (point - screenStart).dy * screenDirection.dy) /
                    screenLengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
      if (projection.type == ProjectionType.perspective &&
          startDepth > 0 &&
          endDepth > 0) {
        fraction =
            fraction *
            startDepth /
            ((1 - fraction) * endDepth + fraction * startDepth);
      }
      return startDepth + (endDepth - startDepth) * fraction;
    }

    bool isVisibleDepth(double depth) =>
        depth.isFinite &&
        (projection.type == ProjectionType.parallel ||
            (depth >= projection.near && depth <= projection.far));

    bool insideTriangle(Offset point, Offset a, Offset b, Offset c) {
      final d1 =
          (point.dx - b.dx) * (a.dy - b.dy) + (a.dx - b.dx) * (point.dy - b.dy);
      final d2 =
          (point.dx - c.dx) * (b.dy - c.dy) + (b.dx - c.dx) * (point.dy - c.dy);
      final d3 =
          (point.dx - a.dx) * (c.dy - a.dy) + (c.dx - a.dx) * (point.dy - a.dy);
      final hasNegative = d1 < 0 || d2 < 0 || d3 < 0;
      final hasPositive = d1 > 0 || d2 > 0 || d3 > 0;
      return !(hasNegative && hasPositive);
    }

    for (var i = _objects.length - 1; i >= 0; i--) {
      final object = _objects[i];
      if ((!object.visible && !includeHidden) ||
          (!includeTransparent &&
              (object.opacity <= 0 || ((object.color >> 24) & 0xFF) == 0))) {
        continue;
      }
      var distance = double.infinity;
      var hitDepth = switch (object.type) {
        Object3DType.point => depthAt(object.point),
        Object3DType.line => depthAt(object.pointA.midpoint(object.pointB)),
        Object3DType.vector => depthAt(object.point + object.vector * 0.5),
        Object3DType.curve => double.infinity,
        Object3DType.surface || Object3DType.polyhedron => double.infinity,
        Object3DType.sphere => depthAt(object.sphereCenter),
        Object3DType.plane => double.infinity,
      };
      switch (object.type) {
        case Object3DType.point:
          distance =
              _isPointOccludedByOpaqueSurface(
                object.point,
                screenPosition: object.isTextAnnotation ? position : null,
              )
              ? double.infinity
              : _pointSelectionDistance(object, position, screen(object.point));
        case Object3DType.line:
          final clipped = clipLineToView(object, camera, projection);
          if (clipped.length == 2) {
            final startDepth = depthAt(clipped[0]);
            final endDepth = depthAt(clipped[1]);
            distance = segmentDistance(
              position,
              screen(clipped[0]),
              screen(clipped[1]),
            );
            hitDepth = depthOnSegmentAtScreen(
              position,
              clipped[0],
              clipped[1],
              startDepth,
              endDepth,
            );
          }
        case Object3DType.vector:
          final clipped = clipLineToView(
            Object3D.line(
              object.point,
              object.point + object.vector,
              lineKind: Line3DKind.segment,
            ),
            camera,
            projection,
          );
          if (clipped.length == 2) {
            final startDepth = depthAt(clipped[0]);
            final endDepth = depthAt(clipped[1]);
            distance = segmentDistance(
              position,
              screen(clipped[0]),
              screen(clipped[1]),
            );
            hitDepth = depthOnSegmentAtScreen(
              position,
              clipped[0],
              clipped[1],
              startDepth,
              endDepth,
            );
          }
        case Object3DType.curve:
          for (var j = 1; j < object.vertices.length; j++) {
            if (object.curveStarts.contains(j)) continue;
            final clipped = clipLineToView(
              Object3D.line(
                object.vertices[j - 1],
                object.vertices[j],
                lineKind: Line3DKind.segment,
              ),
              camera,
              projection,
            );
            if (clipped.length != 2) continue;
            final start = clipped[0];
            final end = clipped[1];
            final startProjection = worldToScreen(start, camera, projection);
            final endProjection = worldToScreen(end, camera, projection);
            if (!startProjection.x.isFinite ||
                !startProjection.y.isFinite ||
                !startProjection.z.isFinite ||
                !endProjection.x.isFinite ||
                !endProjection.y.isFinite ||
                !endProjection.z.isFinite) {
              continue;
            }
            final screenStart = Offset(startProjection.x, startProjection.y);
            final screenDirection = Offset(
              endProjection.x - startProjection.x,
              endProjection.y - startProjection.y,
            );
            final screenLengthSquared = screenDirection.distanceSquared;
            final screenOffset = position - screenStart;
            var fraction = screenLengthSquared < 1e-9
                ? 0.0
                : ((screenOffset.dx * screenDirection.dx +
                              screenOffset.dy * screenDirection.dy) /
                          screenLengthSquared)
                      .clamp(0.0, 1.0)
                      .toDouble();
            if (projection.type == ProjectionType.perspective &&
                startProjection.z > 0 &&
                endProjection.z > 0) {
              fraction =
                  fraction *
                  startProjection.z /
                  ((1 - fraction) * endProjection.z +
                      fraction * startProjection.z);
            }
            final candidate = start + (end - start) * fraction;
            final candidateDistance = (screen(candidate) - position).distance;
            final candidateDepth = depthAt(candidate);
            if (candidateDistance < distance ||
                ((candidateDistance - distance).abs() <=
                        _hitScreenDistanceTieTolerance &&
                    candidateDepth < hitDepth)) {
              distance = candidateDistance;
              hitDepth = candidateDepth;
            }
          }
        case Object3DType.surface:
        case Object3DType.polyhedron:
          for (var j = 0; j + 2 < object.indices.length; j += 3) {
            final ia = object.indices[j];
            final ib = object.indices[j + 1];
            final ic = object.indices[j + 2];
            if (ia >= 0 &&
                ib >= 0 &&
                ic >= 0 &&
                ia < object.vertices.length &&
                ib < object.vertices.length &&
                ic < object.vertices.length) {
              final a = object.vertices[ia];
              final b = object.vertices[ib];
              final c = object.vertices[ic];
              final normal = _normalizedTriangleNormal(a, b, c);
              if (normal == null) continue;
              final clipped = _clipPolygonToDepthRange(
                [a, b, c],
                camera,
                projection,
              );
              if (clipped.length < 3) continue;
              final projected = clipped.map(screen).toList();
              final projectedDepths = clipped.map(depthAt).toList();
              var insideClippedTriangle = false;
              for (var fan = 1; fan + 1 < projected.length; fan++) {
                if (insideTriangle(
                  position,
                  projected[0],
                  projected[fan],
                  projected[fan + 1],
                )) {
                  insideClippedTriangle = true;
                  break;
                }
              }
              if (insideClippedTriangle) {
                final hit = intersectRayPlane(
                  ray,
                  point: a,
                  normal: normal,
                  allowBehind: projection.type == ProjectionType.parallel,
                );
                if (hit != null && _pointInTriangle3D(hit, a, b, c)) {
                  final candidateDepth = depthAt(hit);
                  if (isVisibleDepth(candidateDepth)) {
                    distance = 0;
                    hitDepth = dart_math
                        .min(hitDepth, candidateDepth)
                        .toDouble();
                  }
                }
                continue;
              }
              for (var edge = 0; edge < projected.length; edge++) {
                final next = (edge + 1) % projected.length;
                final edgeDistance = segmentDistance(
                  position,
                  projected[edge],
                  projected[next],
                );
                final edgeDepth = depthOnSegmentAtScreen(
                  position,
                  clipped[edge],
                  clipped[next],
                  projectedDepths[edge],
                  projectedDepths[next],
                );
                if (edgeDistance < distance && isVisibleDepth(edgeDepth)) {
                  distance = edgeDistance;
                  hitDepth = edgeDepth;
                }
              }
            }
          }
        case Object3DType.sphere:
          final sphereHit = _sphereIntersectionAtScreen(
            object,
            position,
            projection,
          );
          if (sphereHit != null) {
            distance = 0;
            hitDepth = depthAt(sphereHit);
          } else {
            final center = screen(object.sphereCenter);
            final radius = object.sphereRadius.abs();
            final view = camera.viewMatrix();
            final right = Vector3D(view[0], view[4], view[8]);
            final up = Vector3D(view[1], view[5], view[9]);
            final horizontalRadius = dart_math.max(
              (screen(object.sphereCenter + right * radius) - center).distance,
              (screen(object.sphereCenter + right * -radius) - center).distance,
            );
            final verticalRadius = dart_math.max(
              (screen(object.sphereCenter + up * radius) - center).distance,
              (screen(object.sphereCenter + up * -radius) - center).distance,
            );
            final projectedRadius = dart_math.max(
              horizontalRadius,
              verticalRadius,
            );
            final centerDistance = (center - position).distance;
            hitDepth = depthAt(_pointOnSphereAtScreen(object, position));
            distance = centerDistance <= projectedRadius + 12
                ? dart_math
                      .max(0.0, centerDistance - projectedRadius)
                      .toDouble()
                : double.infinity;
          }
        case Object3DType.plane:
          final equation = _normalizedPlaneEquation(object);
          if (equation != null) {
            final hit = intersectRayPlane(
              ray,
              point: equation.origin,
              normal: equation.normal,
              allowBehind: projection.type == ProjectionType.parallel,
            );
            if (hit != null && _withinRenderedPlaneGrid(object, hit)) {
              distance = 0;
              hitDepth = depthAt(hit);
            }
          }
      }
      final overlapsNearest =
          (distance - nearestDistance).abs() <= _hitScreenDistanceTieTolerance;
      final pointWinsMarkerOverlap =
          nearestIndex >= 0 &&
          object.type == Object3DType.point &&
          _objects[nearestIndex].type != Object3DType.point &&
          distance <= _pointMarkerRadius &&
          (hitDepth - nearestDepth).abs() <= _hitDepthTieTolerance;
      final nearestPointWinsMarkerOverlap =
          nearestIndex >= 0 &&
          _objects[nearestIndex].type == Object3DType.point &&
          object.type != Object3DType.point &&
          nearestDistance <= _pointMarkerRadius &&
          (hitDepth - nearestDepth).abs() <= _hitDepthTieTolerance;
      if (distance < 24 &&
          isVisibleDepth(hitDepth) &&
          !nearestPointWinsMarkerOverlap &&
          (nearestIndex < 0 ||
              distance < nearestDistance - _hitScreenDistanceTieTolerance ||
              (overlapsNearest &&
                  (hitDepth < nearestDepth ||
                      (hitDepth == nearestDepth &&
                          distance < nearestDistance))) ||
              pointWinsMarkerOverlap)) {
        nearestDistance = distance;
        nearestDepth = hitDepth;
        nearestIndex = i;
      }
    }
    return nearestIndex < 0 ? null : nearestIndex;
  }

  Point3D? _sphereIntersectionAtScreen(
    Object3D sphere,
    Offset position,
    Projection3D projection,
  ) {
    final ray = _screenRay(position.dx, position.dy);
    final center = sphere.sphereCenter;
    final radius = sphere.sphereRadius.abs();
    if (!radius.isFinite) return null;
    final centerToRay = center - ray.origin;
    final alongRay = centerToRay.dot(ray.direction);
    final closest = ray.origin + ray.direction * alongRay;
    final radial = closest - center;
    final distanceToRay = radial.magnitude;
    if (!distanceToRay.isFinite || distanceToRay > radius) return null;
    final offset = dart_math.sqrt(
      dart_math.max(0.0, radius * radius - distanceToRay * distanceToRay),
    );
    Point3D? nearest;
    var nearestDepth = double.infinity;
    for (final rayDistance in [alongRay - offset, alongRay + offset]) {
      if (!rayDistance.isFinite ||
          (projection.type == ProjectionType.perspective && rayDistance < 0)) {
        continue;
      }
      final candidate = ray.pointAt(rayDistance);
      final depth = worldToScreen(candidate, camera, projection).z;
      if (!depth.isFinite ||
          (projection.type == ProjectionType.perspective &&
              (depth < projection.near || depth > projection.far))) {
        continue;
      }
      if (depth < nearestDepth) {
        nearest = candidate;
        nearestDepth = depth;
      }
    }
    return nearest;
  }

  Point3D _pointOnSphereAtScreen(Object3D sphere, Offset position) {
    final hit = _sphereIntersectionAtScreen(
      sphere,
      position,
      _currentProjection(),
    );
    if (hit != null) return hit;
    final ray = _screenRay(position.dx, position.dy);
    final center = sphere.sphereCenter;
    final radius = sphere.sphereRadius.abs();
    final centerToRay = center - ray.origin;
    final alongRay = centerToRay.dot(ray.direction);
    final closest = ray.origin + ray.direction * alongRay;
    final radial = closest - center;
    final distanceToRay = radial.magnitude;
    if (distanceToRay > 0) return center + radial * (radius / distanceToRay);
    return center + ray.direction * -radius;
  }

  Point3D? _pointOnMeshAtScreen(Object3D mesh, Offset position) {
    final ray = _screenRay(position.dx, position.dy);
    final projection = _currentProjection();
    Point3D? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
      final ia = mesh.indices[i];
      final ib = mesh.indices[i + 1];
      final ic = mesh.indices[i + 2];
      if (ia < 0 ||
          ia >= mesh.vertices.length ||
          ib < 0 ||
          ib >= mesh.vertices.length ||
          ic < 0 ||
          ic >= mesh.vertices.length) {
        continue;
      }
      final a = mesh.vertices[ia];
      final b = mesh.vertices[ib];
      final c = mesh.vertices[ic];
      final normal = _normalizedTriangleNormal(a, b, c);
      if (normal == null) continue;
      final hit = intersectRayPlane(
        ray,
        point: a,
        normal: normal,
        allowBehind: _projectionType == ProjectionType.parallel,
      );
      if (hit == null || !_pointInTriangle3D(hit, a, b, c)) continue;
      final hitDepth = worldToScreen(hit, camera, projection).z;
      if (!hitDepth.isFinite ||
          (projection.type == ProjectionType.perspective &&
              (hitDepth < projection.near || hitDepth > projection.far))) {
        continue;
      }
      final distance = (hit - ray.origin).dot(ray.direction);
      if ((_projectionType == ProjectionType.parallel || distance >= 0) &&
          distance < nearestDistance) {
        nearest = hit;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  Point3D _constrainPointToObject(Point3D point, Object3D object) {
    if (object.type == Object3DType.point) return object.point;
    if (object.type == Object3DType.sphere) {
      final direction = (point - object.sphereCenter).normalized();
      return object.sphereCenter +
          (direction.magnitude == 0 ? Vector3D.unitX : direction) *
              object.sphereRadius.abs();
    }
    if (object.type == Object3DType.plane) {
      final equation = _normalizedPlaneEquation(object);
      if (equation != null) {
        final signedOffset =
            (point - equation.origin).dot(equation.normal) /
            equation.normalSquared;
        return point + equation.normal * -signedOffset;
      }
    }
    if (object.type == Object3DType.line ||
        object.type == Object3DType.vector) {
      final a = object.type == Object3DType.vector
          ? object.point
          : object.pointA;
      final b = object.type == Object3DType.vector
          ? object.point + object.vector
          : object.pointB;
      final direction = b - a;
      final lengthSquared = direction.dot(direction);
      if (direction.x == 0 && direction.y == 0 && direction.z == 0) return a;
      var t = (point - a).dot(direction) / lengthSquared;
      if (object.type == Object3DType.vector ||
          object.lineKind == Line3DKind.segment) {
        t = t.clamp(0.0, 1.0).toDouble();
      } else if (object.lineKind == Line3DKind.ray) {
        t = dart_math.max(0.0, t).toDouble();
      }
      return a + direction * t;
    }
    if ((object.type == Object3DType.surface ||
            object.type == Object3DType.polyhedron) &&
        object.indices.length >= 3) {
      var nearest = point;
      var found = false;
      for (var i = 0; i + 2 < object.indices.length; i += 3) {
        final ia = object.indices[i];
        final ib = object.indices[i + 1];
        final ic = object.indices[i + 2];
        if (ia < 0 ||
            ib < 0 ||
            ic < 0 ||
            ia >= object.vertices.length ||
            ib >= object.vertices.length ||
            ic >= object.vertices.length)
          continue;
        final candidate = _closestPointOnTriangle(
          point,
          object.vertices[ia],
          object.vertices[ib],
          object.vertices[ic],
        );
        if (!candidate.x.isFinite ||
            !candidate.y.isFinite ||
            !candidate.z.isFinite) {
          continue;
        }
        if (!found || _isCloserTo(point, candidate, nearest)) {
          nearest = candidate;
          found = true;
        }
      }
      if (found) return nearest;
    }
    if (object.vertices.length >= 2) {
      var nearest = object.vertices.first;
      for (var i = 1; i < object.vertices.length; i++) {
        if (object.type == Object3DType.curve &&
            object.curveStarts.contains(i)) {
          continue;
        }
        final candidate = _closestPointOnSegment(
          point,
          object.vertices[i - 1],
          object.vertices[i],
        );
        if (_isCloserTo(point, candidate, nearest)) {
          nearest = candidate;
        }
      }
      if (object.type == Object3DType.curve && object.conic != null) {
        return _projectPointOntoConic(object.conic!, nearest) ?? nearest;
      }
      return nearest;
    }
    return point;
  }

  Point3D _pointOnObjectAtScreen(
    Object3D object,
    Offset position,
    Point3D fallbackPoint,
  ) {
    switch (object.type) {
      case Object3DType.point:
        return object.point;
      case Object3DType.sphere:
        return _pointOnSphereAtScreen(object, position);
      case Object3DType.surface:
      case Object3DType.polyhedron:
        return _pointOnMeshAtScreen(object, position) ??
            _constrainPointToObject(fallbackPoint, object);
      case Object3DType.plane:
        final equation = _normalizedPlaneEquation(object);
        if (equation != null) {
          final hit = intersectRayPlane(
            _screenRay(position.dx, position.dy),
            point: equation.origin,
            normal: equation.normal,
            allowBehind: _projectionType == ProjectionType.parallel,
          );
          if (hit != null) return hit;
        }
        return _constrainPointToObject(fallbackPoint, object);
      case Object3DType.line:
      case Object3DType.vector:
        return _pointOnLineAtScreen(object, position);
      case Object3DType.curve:
        return _pointOnCurveAtScreen(object, position) ??
            _constrainPointToObject(fallbackPoint, object);
    }
  }

  Point3D _pointOnLineAtScreen(Object3D object, Offset position) {
    final start = object.type == Object3DType.vector
        ? object.point
        : object.pointA;
    final direction = object.type == Object3DType.vector
        ? object.vector
        : object.pointB - object.pointA;
    final lengthSquared = direction.dot(direction);
    if (direction.x == 0 && direction.y == 0 && direction.z == 0) return start;

    final ray = _screenRay(position.dx, position.dy);
    final rayLengthSquared = ray.direction.dot(ray.direction);
    final directionDot = ray.direction.dot(direction);
    final offset = ray.origin - start;
    final rayOffset = ray.direction.dot(offset);
    final lineOffset = direction.dot(offset);
    final denominator =
        rayLengthSquared * lengthSquared - directionDot * directionDot;
    var parameter =
        denominator.abs() <= rayLengthSquared * lengthSquared * 1e-12
        ? lineOffset / lengthSquared
        : (rayLengthSquared * lineOffset - directionDot * rayOffset) /
              denominator;

    double clampToLine(double value) {
      if (object.type == Object3DType.vector ||
          object.lineKind == Line3DKind.segment) {
        return value.clamp(0.0, 1.0).toDouble();
      }
      if (object.lineKind == Line3DKind.ray) {
        return dart_math.max(0.0, value).toDouble();
      }
      return value;
    }

    parameter = clampToLine(parameter);
    final rayParameter =
        (directionDot * parameter - rayOffset) / rayLengthSquared;
    if (_projectionType == ProjectionType.perspective && rayParameter < 0) {
      parameter = clampToLine(lineOffset / lengthSquared);
    }
    return start + direction * parameter;
  }

  Point3D? _pointOnCurveAtScreen(Object3D object, Offset position) {
    final projection = _currentProjection();
    Point3D? nearest;
    var nearestDistance = double.infinity;
    var nearestDepth = double.infinity;
    for (var i = 1; i < object.vertices.length; i++) {
      if (object.curveStarts.contains(i)) continue;
      final clipped = clipLineToView(
        Object3D.line(
          object.vertices[i - 1],
          object.vertices[i],
          lineKind: Line3DKind.segment,
        ),
        camera,
        projection,
      );
      if (clipped.length != 2) continue;
      final start = clipped[0];
      final end = clipped[1];
      final startScreen = worldToScreen(start, camera, projection);
      final endScreen = worldToScreen(end, camera, projection);
      if (!startScreen.x.isFinite ||
          !startScreen.y.isFinite ||
          !startScreen.z.isFinite ||
          !endScreen.x.isFinite ||
          !endScreen.y.isFinite ||
          !endScreen.z.isFinite) {
        continue;
      }
      final screenDirection = Offset(
        endScreen.x - startScreen.x,
        endScreen.y - startScreen.y,
      );
      final screenLengthSquared = screenDirection.distanceSquared;
      final screenOffset = position - Offset(startScreen.x, startScreen.y);
      final fraction = screenLengthSquared < 1e-12
          ? 0.0
          : ((screenOffset.dx * screenDirection.dx +
                        screenOffset.dy * screenDirection.dy) /
                    screenLengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
      var worldFraction = fraction;
      if (projection.type == ProjectionType.perspective &&
          startScreen.z > 0 &&
          endScreen.z > 0) {
        worldFraction =
            fraction *
            startScreen.z /
            ((1 - fraction) * endScreen.z + fraction * startScreen.z);
      }
      final candidate = start + (end - start) * worldFraction;
      final pointOnCurve = object.conic == null
          ? candidate
          : _projectPointOntoConic(object.conic!, candidate) ?? candidate;
      final candidateScreen = worldToScreen(pointOnCurve, camera, projection);
      if (!candidateScreen.x.isFinite ||
          !candidateScreen.y.isFinite ||
          !candidateScreen.z.isFinite ||
          (projection.type == ProjectionType.perspective &&
              (candidateScreen.z < projection.near ||
                  candidateScreen.z > projection.far))) {
        continue;
      }
      final distance =
          (Offset(candidateScreen.x, candidateScreen.y) - position).distance;
      if (!distance.isFinite) continue;
      if (distance < nearestDistance - _hitScreenDistanceTieTolerance ||
          ((distance - nearestDistance).abs() <=
                  _hitScreenDistanceTieTolerance &&
              candidateScreen.z < nearestDepth)) {
        nearest = pointOnCurve;
        nearestDistance = distance;
        nearestDepth = candidateScreen.z;
      }
    }
    return nearest;
  }

  Point3D _closestPointOnSegment(Point3D point, Point3D a, Point3D b) {
    final direction = b - a;
    final scale = dart_math.max(
      direction.x.abs(),
      dart_math.max(direction.y.abs(), direction.z.abs()),
    );
    if (scale == 0) return a;
    final scaledDirection = Vector3D(
      direction.x / scale,
      direction.y / scale,
      direction.z / scale,
    );
    final offset = point - a;
    final t =
        (offset.dot(scaledDirection) /
                scale /
                scaledDirection.dot(scaledDirection))
            .clamp(0.0, 1.0)
            .toDouble();
    return a + direction * t;
  }

  double _projectionDistance(Point3D a, Point3D b) {
    final d = a - b;
    final scale = dart_math.max(d.x.abs(), dart_math.max(d.y.abs(), d.z.abs()));
    if (scale == 0 || !scale.isFinite) return scale;
    final x = d.x / scale;
    final y = d.y / scale;
    final z = d.z / scale;
    return scale * dart_math.sqrt(x * x + y * y + z * z);
  }

  bool _isCloserTo(Point3D point, Point3D candidate, Point3D nearest) {
    final candidateDistance = _projectionDistance(point, candidate);
    final nearestDistance = _projectionDistance(point, nearest);
    if (candidateDistance != nearestDistance) {
      return candidateDistance < nearestDistance;
    }
    final difference = candidate - nearest;
    final scale = dart_math.max(
      difference.x.abs(),
      dart_math.max(difference.y.abs(), difference.z.abs()),
    );
    if (scale == 0 || !scale.isFinite) return false;
    final fromCandidate = point - candidate;
    final fromNearest = point - nearest;
    final offsetScale = dart_math.max(
      dart_math.max(fromCandidate.x.abs(), fromNearest.x.abs()),
      dart_math.max(
        dart_math.max(fromCandidate.y.abs(), fromNearest.y.abs()),
        dart_math.max(fromCandidate.z.abs(), fromNearest.z.abs()),
      ),
    );
    final divisor = offsetScale > 8e307 ? 2.0 : 1.0;
    return (difference.x / scale) *
                (fromCandidate.x / divisor + fromNearest.x / divisor) +
            (difference.y / scale) *
                (fromCandidate.y / divisor + fromNearest.y / divisor) +
            (difference.z / scale) *
                (fromCandidate.z / divisor + fromNearest.z / divisor) >
        0;
  }

  Point3D _closestPointOnTriangle(
    Point3D point,
    Point3D a,
    Point3D b,
    Point3D c,
  ) {
    final ab = b - a;
    final ac = c - a;
    if (_normalizedTriangleNormal(a, b, c) == null) {
      final candidates = [
        a,
        b,
        c,
        _closestPointOnSegment(point, a, b),
        _closestPointOnSegment(point, b, c),
        _closestPointOnSegment(point, c, a),
      ];
      return candidates.reduce(
        (nearest, candidate) =>
            _isCloserTo(point, candidate, nearest) ? candidate : nearest,
      );
    }
    final ap = point - a;
    final d1 = ab.dot(ap);
    final d2 = ac.dot(ap);
    if (d1 <= 0 && d2 <= 0) return a;

    final bp = point - b;
    final d3 = ab.dot(bp);
    final d4 = ac.dot(bp);
    if (d3 >= 0 && d4 <= d3) return b;

    final vc = d1 * d4 - d3 * d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) {
      return a + ab * (d1 / (d1 - d3));
    }

    final cp = point - c;
    final d5 = ab.dot(cp);
    final d6 = ac.dot(cp);
    if (d6 >= 0 && d5 <= d6) return c;

    final vb = d5 * d2 - d1 * d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) {
      return a + ac * (d2 / (d2 - d6));
    }

    final va = d3 * d6 - d5 * d4;
    if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0) {
      final t = (d4 - d3) / (d4 - d3 + d5 - d6);
      return b + (c - b) * t;
    }

    final inverseSum = 1 / (va + vb + vc);
    final v = vb * inverseSum;
    final w = vc * inverseSum;
    return a + ab * v + ac * w;
  }

  void _performObjectAction(Offset position) {
    final tool = _currentTool;
    final index = _hitObjectIndex(
      position,
      includeHidden:
          tool == ConstructionTool.showHideObject ||
          tool == ConstructionTool.deleteObject,
      includeTransparent:
          tool == ConstructionTool.showHideObject ||
          tool == ConstructionTool.deleteObject,
    );
    if (index == null) return;
    switch (tool) {
      case ConstructionTool.deleteObject:
        _removeObjectAt(index);
      case ConstructionTool.showHideObject:
        setState(() {
          _objects[index] = _objects[index].copyWith(
            visible: !_objects[index].visible,
          );
          _objectsVersion++;
        });
        widget.onSceneChanged?.call();
      case ConstructionTool.volume:
        final volume = _objectVolume(_objects[index]);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: _error(
              volume == null
                  ? '该对象不是封闭立体，无法测量体积'
                  : '${_objects[index].label ?? '对象'} · 体积 ${volume.toStringAsFixed(3)}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      case ConstructionTool.intersectionPoint:
        if (_pointIntersectionSourceIndex == null) {
          _pointIntersectionSourceIndex = index;
          widget.onToolInstruction?.call('再点击第二个相交对象');
        } else {
          final first = _objects[_pointIntersectionSourceIndex!];
          final points = _createIntersectionPoints(first, _objects[index]);
          _pointIntersectionSourceIndex = null;
          if (points.isEmpty) {
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: _error('这两个对象没有可显示的离散交点')));
          } else {
            for (final point in points) {
              _appendCreatedObject(Object3D.point(point, color: 0xFFD81B60));
            }
          }
          widget.onToolInstruction?.call(ToolInfo.all[tool]!.tooltip);
        }
      case ConstructionTool.tangentLine:
      case ConstructionTool.polarDiameter:
        _performConicLineAction(
          index,
          tangent: tool == ConstructionTool.tangentLine,
        );
      case ConstructionTool.intersectionCurve:
        if (_intersectionSourceIndex == null) {
          _intersectionSourceIndex = index;
          widget.onToolInstruction?.call('再点击与之相交的平面或球面');
        } else {
          final first = _objects[_intersectionSourceIndex!];
          final intersection = _createIntersectionCurve(first, _objects[index]);
          _intersectionSourceIndex = null;
          if (intersection != null) _appendCreatedObject(intersection);
          widget.onToolInstruction?.call(ToolInfo.all[tool]!.tooltip);
        }
      case ConstructionTool.copyStyle:
        if (_styleSourceIndex == null) {
          _styleSourceIndex = index;
          widget.onToolInstruction?.call('再点击目标对象');
        } else {
          final source = _objects[_styleSourceIndex!];
          setState(() {
            _objects[index] = _objects[index].copyWith(
              color: source.color,
              opacity: source.opacity,
            );
            _styleSourceIndex = null;
            _objectsVersion++;
          });
          widget.onToolInstruction?.call(ToolInfo.all[tool]!.tooltip);
        }
      case ConstructionTool.attachDetachPoint:
        if (_attachmentPointIndex != null) {
          if (_attachmentPointIndex == index) {
            _attachmentPointIndex = null;
            widget.onToolInstruction?.call('已取消附着');
          } else if (_wouldCreateAttachmentCycle(
            _attachmentPointIndex!,
            index,
          )) {
            _attachmentPointIndex = null;
            widget.onToolInstruction?.call('附着关系不能形成循环');
          } else {
            setState(() {
              final pointIndex = _attachmentPointIndex!;
              final point = _objects[pointIndex];
              _objects[pointIndex] = point.copyWith(
                point: _constrainPointToObject(point.point, _objects[index]),
              );
              _pointAttachments[pointIndex] = index;
              _propagateConstructionAndAttachmentMoves(pointIndex);
              _attachmentPointIndex = null;
              _objectsVersion++;
            });
            widget.onToolInstruction?.call('点已附着到对象');
          }
        } else if (_objects[index].type == Object3DType.point) {
          if (_pointAttachments.containsKey(index)) {
            setState(() {
              _pointAttachments.remove(index);
              _objectsVersion++;
            });
            widget.onToolInstruction?.call('点已脱离对象');
          } else if (_attachmentPointIndex == null) {
            _attachmentPointIndex = index;
            widget.onToolInstruction?.call('再点击要附着到的对象');
          }
        }
      case ConstructionTool.unfoldNet:
        final unfolded = _unfoldPolyhedron(_objects[index]);
        if (unfolded != null) _appendCreatedObject(unfolded);
      default:
        break;
    }
    widget.onSceneChanged?.call();
  }

  void _appendCreatedObject(Object3D object) {
    final toolName = ToolInfo.all[_currentTool]!.name;
    var number = 1;
    while (_objects.any((existing) => existing.label == '$toolName$number')) {
      number++;
    }
    final labelled = object.label == null
        ? object.copyWith(label: '$toolName$number')
        : object;
    if (widget.onObjectCreated != null) {
      widget.onObjectCreated!(labelled);
    } else {
      setState(() {
        _objects.add(labelled);
        _objectsVersion++;
      });
      widget.onSceneChanged?.call();
    }
  }

  void _performConicLineAction(int index, {required bool tangent}) {
    final sourceIndex = _conicSourceIndex;
    final isPolarDiameter = _currentTool == ConstructionTool.polarDiameter;
    if (sourceIndex == null) {
      final source = _objects[index];
      final canSelectPoint =
          source.type == Object3DType.point && !source.isTextAnnotation;
      final canSelectLine = isPolarDiameter && source.type == Object3DType.line;
      if (!canSelectPoint && !canSelectLine) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: _error(isPolarDiameter ? '请先选择一个点或直线' : '请先选择一个点')),
        );
      } else {
        _conicSourceIndex = index;
        widget.onToolInstruction?.call(
          tangent
              ? '再点击圆或圆锥曲线'
              : canSelectLine
              ? '再点击圆锥曲线生成共轭径线'
              : '再点击圆锥曲线生成极线',
        );
      }
      return;
    }

    final source = _objects[sourceIndex];
    final conicObject = _objects[index];
    final conic = conicObject.conic;
    _conicSourceIndex = null;
    Object3D? line;
    if (conic != null) {
      if (source.type == Object3DType.point &&
          !source.isTextAnnotation &&
          _pointInConicPlane(conic, source.point) &&
          (!tangent ||
              (_pointOnConic(conic, source.point) &&
                  _pointOnConicPath(conicObject, source.point)))) {
        line = _createPolarLine(
          conic,
          source.point,
          label: tangent ? 'Tangent' : 'Polar',
        );
      } else if (isPolarDiameter && source.type == Object3DType.line) {
        line = _createConjugateDiameter(conic, source);
      }
    }

    if (line == null) {
      final message = tangent
          ? '请选取圆或圆锥曲线上的点'
          : source.type == Object3DType.line
          ? '请选择位于圆锥曲线平面内的直线和具有中心的圆锥曲线'
          : '请选择曲线平面内能确定有限极线的点';
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: _error(message)));
    } else {
      _appendCreatedObject(line);
    }
    widget.onToolInstruction?.call(ToolInfo.all[_currentTool]!.tooltip);
  }

  bool _pointInConicPlane(Conic3D conic, Point3D point) {
    final normal = _conicPlaneNormal(conic);
    if (normal == null) return false;
    return (point - conic.origin).dot(normal).abs() <
        _conicPlaneTolerance(conic, point, minimum: 1e-6);
  }

  Vector3D? _conicPlaneNormal(Conic3D conic) {
    final normal = conic.axisU.cross(conic.axisV);
    final magnitude = normal.magnitude;
    if (!magnitude.isFinite || magnitude == 0) return null;
    return normal * (1 / magnitude);
  }

  double _conicPlaneTolerance(
    Conic3D conic,
    Point3D point, {
    required double minimum,
  }) {
    final coordinateScale =
        [
          conic.origin.x.abs(),
          conic.origin.y.abs(),
          conic.origin.z.abs(),
          point.x.abs(),
          point.y.abs(),
          point.z.abs(),
        ].fold<double>(
          1,
          (scale, coordinate) => dart_math.max(scale, coordinate).toDouble(),
        );
    return dart_math
        .max(minimum, coordinateScale * 1.7763568394002505e-15)
        .toDouble();
  }

  Point3D? _projectPointOntoConic(Conic3D conic, Point3D point) {
    final coordinates = _conicCoordinates(conic, point - conic.origin);
    if (coordinates == null) return null;
    var x = coordinates.x;
    var y = coordinates.y;
    for (var i = 0; i < 12; i++) {
      final value =
          conic.quadraticX * x * x +
          conic.quadraticXY * x * y +
          conic.quadraticY * y * y +
          conic.linearX * x +
          conic.linearY * y +
          conic.constant;
      final gradientX =
          2 * conic.quadraticX * x + conic.quadraticXY * y + conic.linearX;
      final gradientY =
          conic.quadraticXY * x + 2 * conic.quadraticY * y + conic.linearY;
      final gradientSquared = gradientX * gradientX + gradientY * gradientY;
      final gradientScaleX =
          (2 * conic.quadraticX * x).abs() +
          (conic.quadraticXY * y).abs() +
          conic.linearX.abs();
      final gradientScaleY =
          (conic.quadraticXY * x).abs() +
          (2 * conic.quadraticY * y).abs() +
          conic.linearY.abs();
      final gradientScale = dart_math.sqrt(
        gradientScaleX * gradientScaleX + gradientScaleY * gradientScaleY,
      );
      if (!value.isFinite ||
          !gradientSquared.isFinite ||
          !gradientScale.isFinite ||
          dart_math.sqrt(gradientSquared) <= gradientScale * 1e-12) {
        return null;
      }

      final terms = [
        conic.quadraticX * x * x,
        conic.quadraticXY * x * y,
        conic.quadraticY * y * y,
        conic.linearX * x,
        conic.linearY * y,
        conic.constant,
      ];
      final scale = terms.fold<double>(0, (sum, term) => sum + term.abs());
      if (value.abs() <= scale * 1e-12) break;

      final correction = value / gradientSquared;
      x -= correction * gradientX;
      y -= correction * gradientY;
      if (!x.isFinite || !y.isFinite) return null;
    }

    final projected = conic.origin + conic.axisU * x + conic.axisV * y;
    return _pointOnConic(conic, projected) ? projected : null;
  }

  bool _pointOnConic(Conic3D conic, Point3D point) {
    final coordinates = _conicCoordinates(conic, point - conic.origin);
    if (coordinates == null) return false;
    final x = coordinates.x;
    final y = coordinates.y;
    final terms = [
      conic.quadraticX * x * x,
      conic.quadraticXY * x * y,
      conic.quadraticY * y * y,
      conic.linearX * x,
      conic.linearY * y,
      conic.constant,
    ];
    final value = terms.fold<double>(0, (sum, term) => sum + term);
    final scale = terms.fold<double>(0, (sum, term) => sum + term.abs());
    return value.abs() <= scale * 1e-6;
  }

  ({double x, double y})? _conicCoordinates(Conic3D conic, Vector3D offset) {
    final normal = conic.axisU.cross(conic.axisV);
    final normalSquared = normal.dot(normal);
    if (!normalSquared.isFinite || normalSquared == 0) return null;
    final x = offset.cross(conic.axisV).dot(normal) / normalSquared;
    final y = conic.axisU.cross(offset).dot(normal) / normalSquared;
    if (!x.isFinite || !y.isFinite) return null;
    return (x: x, y: y);
  }

  bool _pointOnConicPath(Object3D curve, Point3D point) {
    for (var i = 1; i < curve.vertices.length; i++) {
      if (curve.curveStarts.contains(i)) continue;
      final start = curve.vertices[i - 1];
      final end = curve.vertices[i];
      final direction = end - start;
      final segmentLength = start.distanceTo(end);
      if (!segmentLength.isFinite || segmentLength == 0) continue;
      final unitDirection = direction * (1 / segmentLength);
      final along = (point - start)
          .dot(unitDirection)
          .clamp(0.0, segmentLength)
          .toDouble();
      final closest = start + unitDirection * along;
      final coordinateScale =
          <double>[
            point.x.abs(),
            point.y.abs(),
            point.z.abs(),
            start.x.abs(),
            start.y.abs(),
            start.z.abs(),
            end.x.abs(),
            end.y.abs(),
            end.z.abs(),
            1.0,
          ].fold<double>(
            1,
            (scale, coordinate) => dart_math.max(scale, coordinate).toDouble(),
          );
      if (point.distanceTo(closest) <=
          segmentLength * 0.02 + coordinateScale * 1e-15) {
        return true;
      }
    }
    return false;
  }

  Object3D? _createPolarLine(
    Conic3D conic,
    Point3D point, {
    required String label,
  }) {
    final coordinates = _conicCoordinates(conic, point - conic.origin);
    if (coordinates == null) return null;
    final x = coordinates.x;
    final y = coordinates.y;
    final lineX =
        2 * conic.quadraticX * x + conic.quadraticXY * y + conic.linearX;
    final lineY =
        conic.quadraticXY * x + 2 * conic.quadraticY * y + conic.linearY;
    final lineConstant =
        conic.linearX * x + conic.linearY * y + 2 * conic.constant;

    if (lineX == 0 && lineY == 0) {
      return null;
    }

    late final double localX;
    late final double localY;
    late final Vector3D direction;
    if (lineX.abs() >= lineY.abs()) {
      localX = -lineConstant / lineX;
      localY = 0;
      direction = conic.axisV - conic.axisU * (lineY / lineX);
    } else {
      localX = 0;
      localY = -lineConstant / lineY;
      direction = conic.axisU - conic.axisV * (lineX / lineY);
    }
    final start = conic.origin + conic.axisU * localX + conic.axisV * localY;
    return Object3D.line(
      start,
      start + direction,
      lineKind: Line3DKind.line,
      color: 0xFF4CAF50,
      label: label,
    );
  }

  Object3D? _createConjugateDiameter(Conic3D conic, Object3D sourceLine) {
    if (!_pointInConicPlane(conic, sourceLine.pointA) ||
        !_pointInConicPlane(conic, sourceLine.pointB)) {
      return null;
    }

    final sourceDirection = sourceLine.pointB - sourceLine.pointA;
    final directionCoordinates = _conicCoordinates(conic, sourceDirection);
    if (directionCoordinates == null) return null;
    final directionX = directionCoordinates.x;
    final directionY = directionCoordinates.y;
    final directionScale = dart_math
        .max(directionX.abs(), directionY.abs())
        .toDouble();
    if (!directionScale.isFinite || directionScale == 0) return null;
    final dx = directionX / directionScale;
    final dy = directionY / directionScale;

    final quadraticScale = dart_math
        .max(
          conic.quadraticX.abs(),
          dart_math.max(conic.quadraticXY.abs(), conic.quadraticY.abs()),
        )
        .toDouble();
    if (!quadraticScale.isFinite || quadraticScale == 0) return null;
    final quadraticX = conic.quadraticX / quadraticScale;
    final quadraticXY = conic.quadraticXY / quadraticScale;
    final quadraticY = conic.quadraticY / quadraticScale;
    final linearX = conic.linearX / quadraticScale;
    final linearY = conic.linearY / quadraticScale;
    if (!linearX.isFinite || !linearY.isFinite) return null;

    final determinant = 4 * quadraticX * quadraticY - quadraticXY * quadraticXY;
    final determinantScale =
        (4 * quadraticX * quadraticY).abs() + quadraticXY * quadraticXY;
    if (!determinant.isFinite ||
        determinantScale == 0 ||
        determinant.abs() <= determinantScale * 1e-12) {
      return null;
    }

    final centerX =
        (-2 * quadraticY * linearX + quadraticXY * linearY) / determinant;
    final centerY =
        (-2 * quadraticX * linearY + quadraticXY * linearX) / determinant;
    if (!centerX.isFinite || !centerY.isFinite) return null;

    final formX = quadraticX * dx + quadraticXY * dy / 2;
    final formY = quadraticXY * dx / 2 + quadraticY * dy;
    final formScale = dart_math.max(formX.abs(), formY.abs()).toDouble();
    if (!formScale.isFinite || formScale == 0) return null;

    final center = conic.origin + conic.axisU * centerX + conic.axisV * centerY;
    final diameterDirection =
        conic.axisU * (-formY / formScale) + conic.axisV * (formX / formScale);
    if (!center.x.isFinite ||
        !center.y.isFinite ||
        !center.z.isFinite ||
        !diameterDirection.x.isFinite ||
        !diameterDirection.y.isFinite ||
        !diameterDirection.z.isFinite ||
        diameterDirection.magnitude == 0) {
      return null;
    }

    return Object3D.line(
      center,
      center + diameterDirection,
      lineKind: Line3DKind.line,
      color: 0xFF4CAF50,
      label: 'Conjugate diameter',
    );
  }

  Object3D? _createIntersectionCurve(Object3D first, Object3D second) {
    final firstPlane = first.type == Object3DType.plane ? first : null;
    final secondPlane = second.type == Object3DType.plane ? second : null;
    final firstSphere = first.type == Object3DType.sphere ? first : null;
    final secondSphere = second.type == Object3DType.sphere ? second : null;

    if (firstPlane != null && secondPlane != null) {
      final equation1 = _normalizedPlaneEquation(firstPlane);
      final equation2 = _normalizedPlaneEquation(secondPlane);
      if (equation1 == null || equation2 == null) return null;
      final length1 = dart_math.sqrt(equation1.normalSquared);
      final length2 = dart_math.sqrt(equation2.normalSquared);
      final n1 = equation1.normal * (1 / length1);
      final n2 = equation2.normal * (1 / length2);
      final d1 = equation1.d / length1;
      final d2 = equation2.d / length2;
      final direction = n1.cross(n2);
      final denominator = direction.dot(direction);
      if (!denominator.isFinite || denominator == 0) return null;
      final pointVector =
          (n2.cross(direction) * d1 + direction.cross(n1) * d2) *
          (1 / denominator);
      final point = Point3D(pointVector.x, pointVector.y, pointVector.z);
      final lineDirection = direction.normalized();
      if (!point.x.isFinite ||
          !point.y.isFinite ||
          !point.z.isFinite ||
          !lineDirection.x.isFinite ||
          !lineDirection.y.isFinite ||
          !lineDirection.z.isFinite ||
          lineDirection.magnitude == 0) {
        return null;
      }
      return Object3D.line(
        point,
        point + lineDirection,
        lineKind: Line3DKind.line,
        color: 0xFF1565C0,
      );
    }

    if (firstSphere != null && secondPlane != null) {
      return _spherePlaneIntersection(firstSphere, secondPlane);
    }
    if (firstPlane != null && secondSphere != null) {
      return _spherePlaneIntersection(secondSphere, firstPlane);
    }
    if (firstSphere != null && secondSphere != null) {
      return _sphereSphereIntersection(firstSphere, secondSphere);
    }
    return null;
  }

  List<Point3D> _createIntersectionPoints(Object3D first, Object3D second) {
    if (identical(first, second)) return const [];

    ({Point3D origin, Vector3D direction, double minT, double maxT})? lineInfo(
      Object3D object,
    ) {
      if (object.type != Object3DType.line &&
          object.type != Object3DType.vector)
        return null;
      final origin = object.type == Object3DType.vector
          ? object.point
          : object.pointA;
      final direction = object.type == Object3DType.vector
          ? object.vector
          : object.pointB - object.pointA;
      if (direction.x == 0 && direction.y == 0 && direction.z == 0) {
        return null;
      }
      if (object.type == Object3DType.vector ||
          object.lineKind == Line3DKind.segment) {
        return (origin: origin, direction: direction, minT: 0, maxT: 1);
      }
      return (
        origin: origin,
        direction: direction,
        minT: object.lineKind == Line3DKind.ray ? 0 : double.negativeInfinity,
        maxT: double.infinity,
      );
    }

    double intersectionTolerance(
      Point3D first,
      Point3D second,
      double geometryScale,
    ) {
      final coordinateScale =
          [
            first.x.abs(),
            first.y.abs(),
            first.z.abs(),
            second.x.abs(),
            second.y.abs(),
            second.z.abs(),
          ].fold<double>(
            0,
            (scale, coordinate) => dart_math.max(scale, coordinate).toDouble(),
          );
      return dart_math
          .max(geometryScale * 1e-12, coordinateScale * 1.7763568394002505e-15)
          .toDouble();
    }

    double finiteLineScale(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
    ) {
      if (!line.minT.isFinite || !line.maxT.isFinite) return 0;
      final scale = (line.maxT - line.minT).abs() * line.direction.magnitude;
      return scale.isFinite ? scale : 0;
    }

    bool inRange(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
      double t,
    ) {
      if (!t.isFinite) return false;
      final directionMagnitude = line.direction.magnitude;
      if (!directionMagnitude.isFinite || directionMagnitude == 0) return false;
      final point = line.origin + line.direction * t;
      if (![
        point.x,
        point.y,
        point.z,
      ].every((coordinate) => coordinate.isFinite)) {
        return false;
      }
      if (t < line.minT) {
        if (!line.minT.isFinite) return false;
        final boundary = line.origin + line.direction * line.minT;
        if (point.distanceTo(boundary) >
            intersectionTolerance(boundary, point, finiteLineScale(line))) {
          return false;
        }
      }
      if (t > line.maxT) {
        if (!line.maxT.isFinite) return false;
        final boundary = line.origin + line.direction * line.maxT;
        if (point.distanceTo(boundary) >
            intersectionTolerance(boundary, point, finiteLineScale(line))) {
          return false;
        }
      }
      return true;
    }

    bool pointLiesOnObject(Point3D point, Object3D object) {
      switch (object.type) {
        case Object3DType.point:
          return !object.isTextAnnotation &&
              point.distanceTo(object.point) <=
                  intersectionTolerance(point, object.point, 1.0);
        case Object3DType.line:
        case Object3DType.vector:
          final line = lineInfo(object);
          if (line == null) return false;
          final directionSquared = line.direction.dot(line.direction);
          if (!directionSquared.isFinite || directionSquared == 0) return false;
          final t =
              (point - line.origin).dot(line.direction) / directionSquared;
          if (!inRange(line, t)) return false;
          final closest = line.origin + line.direction * t;
          final featureScale =
              object.type == Object3DType.vector ||
                  object.lineKind == Line3DKind.segment
              ? line.direction.magnitude
              : 1.0;
          return point.distanceTo(closest) <=
              intersectionTolerance(point, closest, featureScale);
        case Object3DType.plane:
          final equation = _normalizedPlaneEquation(object);
          if (equation == null) return false;
          final distance =
              (point - equation.origin).dot(equation.normal).abs() /
              dart_math.sqrt(equation.normalSquared);
          return distance <= intersectionTolerance(point, equation.origin, 1.0);
        case Object3DType.sphere:
          final radius = object.sphereRadius.abs();
          final radialDistance = point.distanceTo(object.sphereCenter);
          return radialDistance.isFinite &&
              (radialDistance - radius).abs() <=
                  intersectionTolerance(
                    point,
                    object.sphereCenter,
                    dart_math.max(radius, radialDistance).toDouble(),
                  );
        case Object3DType.surface:
        case Object3DType.polyhedron:
          for (var i = 0; i + 2 < object.indices.length; i += 3) {
            final ia = object.indices[i];
            final ib = object.indices[i + 1];
            final ic = object.indices[i + 2];
            if (ia < 0 ||
                ia >= object.vertices.length ||
                ib < 0 ||
                ib >= object.vertices.length ||
                ic < 0 ||
                ic >= object.vertices.length) {
              continue;
            }
            final a = object.vertices[ia];
            final b = object.vertices[ib];
            final c = object.vertices[ic];
            final normal = _normalizedTriangleNormal(a, b, c);
            if (normal == null) continue;
            final scale = dart_math
                .max(
                  (b - a).magnitude,
                  dart_math.max((c - b).magnitude, (a - c).magnitude),
                )
                .toDouble();
            if ((point - a).dot(normal).abs() <=
                    intersectionTolerance(point, a, scale) &&
                _pointInTriangle3D(point, a, b, c)) {
              return true;
            }
          }
          return false;
        case Object3DType.curve:
          final conic = object.conic;
          if (conic != null) {
            return _pointInConicPlane(conic, point) &&
                _pointOnConic(conic, point) &&
                _pointOnConicPath(object, point);
          }
          for (var i = 1; i < object.vertices.length; i++) {
            if (object.curveStarts.contains(i)) continue;
            final start = object.vertices[i - 1];
            final direction = object.vertices[i] - start;
            final lengthSquared = direction.dot(direction);
            if (!lengthSquared.isFinite || lengthSquared == 0) continue;
            final t = (point - start).dot(direction) / lengthSquared;
            if (t < 0 || t > 1) continue;
            final closest = start + direction * t;
            if (point.distanceTo(closest) <=
                intersectionTolerance(point, closest, direction.magnitude)) {
              return true;
            }
          }
          return false;
      }
    }

    List<Point3D> collinearLineIntersectionPoints(
      ({Point3D origin, Vector3D direction, double minT, double maxT})
      firstLine,
      ({Point3D origin, Vector3D direction, double minT, double maxT})
      secondLine,
    ) {
      final firstLengthSquared = firstLine.direction.dot(firstLine.direction);
      final secondLengthSquared = secondLine.direction.dot(
        secondLine.direction,
      );
      if (!firstLengthSquared.isFinite ||
          !secondLengthSquared.isFinite ||
          firstLengthSquared == 0 ||
          secondLengthSquared == 0) {
        return const [];
      }
      final geometryScale = dart_math
          .max(finiteLineScale(firstLine), finiteLineScale(secondLine))
          .toDouble();
      final secondOriginOffset = secondLine.origin - firstLine.origin;
      final secondOriginOnFirst =
          firstLine.origin +
          firstLine.direction *
              (secondOriginOffset.dot(firstLine.direction) /
                  firstLengthSquared);
      if (secondOriginOnFirst.distanceTo(secondLine.origin) >
          intersectionTolerance(
            secondOriginOnFirst,
            secondLine.origin,
            geometryScale,
          )) {
        return const [];
      }

      final secondParameterOffset =
          secondOriginOffset.dot(firstLine.direction) / firstLengthSquared;
      final secondParameterScale =
          secondLine.direction.dot(firstLine.direction) / firstLengthSquared;
      if (!secondParameterOffset.isFinite ||
          !secondParameterScale.isFinite ||
          secondParameterScale == 0) {
        return const [];
      }

      double mapSecondParameter(double parameter) =>
          secondParameterOffset + secondParameterScale * parameter;

      final mappedStart = secondLine.minT.isFinite
          ? mapSecondParameter(secondLine.minT)
          : secondParameterScale > 0
          ? double.negativeInfinity
          : double.infinity;
      final mappedEnd = secondLine.maxT.isFinite
          ? mapSecondParameter(secondLine.maxT)
          : secondParameterScale > 0
          ? double.infinity
          : double.negativeInfinity;
      final overlapStart = dart_math
          .max(firstLine.minT, dart_math.min(mappedStart, mappedEnd))
          .toDouble();
      final overlapEnd = dart_math
          .min(firstLine.maxT, dart_math.max(mappedStart, mappedEnd))
          .toDouble();
      if (!overlapStart.isFinite || !overlapEnd.isFinite) return const [];

      final firstOverlapPoint =
          firstLine.origin + firstLine.direction * overlapStart;
      final secondOverlapPoint =
          firstLine.origin + firstLine.direction * overlapEnd;
      return firstOverlapPoint.distanceTo(secondOverlapPoint) <=
              intersectionTolerance(
                firstOverlapPoint,
                secondOverlapPoint,
                geometryScale,
              )
          ? [firstOverlapPoint.midpoint(secondOverlapPoint)]
          : const [];
    }

    Point3D? linePlaneIntersection(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
      Object3D plane,
    ) {
      final equation = _normalizedPlaneEquation(plane);
      if (equation == null) return null;
      final normal = equation.normal;
      final denominator = normal.dot(line.direction);
      final normalMagnitude = normal.magnitude;
      final directionMagnitude = line.direction.magnitude;
      if (!denominator.isFinite ||
          !normalMagnitude.isFinite ||
          !directionMagnitude.isFinite ||
          normalMagnitude == 0 ||
          directionMagnitude == 0 ||
          (denominator / normalMagnitude / directionMagnitude).abs() <= 1e-12) {
        return null;
      }
      final t = (equation.d - normal.dot(line.origin.toVector())) / denominator;
      if (!inRange(line, t)) return null;
      return line.origin + line.direction * t;
    }

    List<Point3D> lineSphereIntersections(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
      Object3D sphere,
    ) {
      final directionMagnitude = line.direction.magnitude;
      if (!directionMagnitude.isFinite || directionMagnitude == 0) {
        return const [];
      }
      final unitDirection = line.direction * (1 / directionMagnitude);
      final offset = line.origin - sphere.sphereCenter;
      final closestDistance = -offset.dot(unitDirection);
      final closestPoint = line.origin + unitDirection * closestDistance;
      final closestOffset = closestPoint - sphere.sphereCenter;
      final closestDistanceSquared = closestOffset.dot(closestOffset);
      final radiusSquared = sphere.sphereRadius * sphere.sphereRadius;
      final chordSquared = radiusSquared - closestDistanceSquared;
      final tangentTolerance = (radiusSquared + closestDistanceSquared) * 1e-12;
      if (!chordSquared.isFinite || chordSquared < -tangentTolerance) {
        return const [];
      }
      final halfChord = dart_math.sqrt(dart_math.max(0, chordSquared));
      final candidates = <double>[closestDistance - halfChord];
      if (halfChord > 0) candidates.add(closestDistance + halfChord);
      return [
        for (final distance in candidates)
          if (inRange(line, distance / directionMagnitude))
            line.origin + line.direction * (distance / directionMagnitude),
      ];
    }

    List<Point3D> lineConicIntersections(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
      Conic3D conic,
    ) {
      final normal = _conicPlaneNormal(conic);
      if (normal == null) return const [];
      final offset = line.origin - conic.origin;
      final planeOffset = offset.dot(normal);
      final planeSlope = line.direction.dot(normal);
      bool liesOnConicPlane(Point3D point) =>
          (point - conic.origin).dot(normal).abs() <=
          _conicPlaneTolerance(conic, point, minimum: 1e-9);

      final directionMagnitude = line.direction.magnitude;
      if (!directionMagnitude.isFinite || directionMagnitude == 0) {
        return const [];
      }
      if (planeSlope.abs() > directionMagnitude * 1e-12) {
        final t = -planeOffset / planeSlope;
        if (!inRange(line, t)) return const [];
        final intersection = line.origin + line.direction * t;
        return _pointOnConic(conic, intersection) &&
                liesOnConicPlane(intersection)
            ? [intersection]
            : const [];
      }
      if (planeOffset.abs() >
          _conicPlaneTolerance(conic, line.origin, minimum: 1e-9)) {
        return const [];
      }

      final originCoordinates = _conicCoordinates(conic, offset);
      final directionCoordinates = _conicCoordinates(conic, line.direction);
      if (originCoordinates == null || directionCoordinates == null) {
        return const [];
      }
      final x = originCoordinates.x;
      final y = originCoordinates.y;
      final dx = directionCoordinates.x;
      final dy = directionCoordinates.y;
      final quadraticTerms = [
        conic.quadraticX * dx * dx,
        conic.quadraticXY * dx * dy,
        conic.quadraticY * dy * dy,
      ];
      final quadratic = quadraticTerms.fold<double>(
        0,
        (sum, term) => sum + term,
      );
      final quadraticScale = quadraticTerms.fold<double>(
        0,
        (sum, term) => sum + term.abs(),
      );
      final linearTerms = [
        2 * conic.quadraticX * x * dx,
        conic.quadraticXY * x * dy,
        conic.quadraticXY * y * dx,
        2 * conic.quadraticY * y * dy,
        conic.linearX * dx,
        conic.linearY * dy,
      ];
      final linear = linearTerms.fold<double>(0, (sum, term) => sum + term);
      final linearScale = linearTerms.fold<double>(
        0,
        (sum, term) => sum + term.abs(),
      );
      final constant =
          conic.quadraticX * x * x +
          conic.quadraticXY * x * y +
          conic.quadraticY * y * y +
          conic.linearX * x +
          conic.linearY * y +
          conic.constant;

      final parameters = <double>[];
      if (quadratic.abs() <= quadraticScale * 1e-12) {
        if (linearScale == 0 || linear.abs() <= linearScale * 1e-12) {
          return const [];
        }
        parameters.add(-constant / linear);
      } else {
        final discriminant = linear * linear - 4 * quadratic * constant;
        final discriminantTolerance =
            (linear * linear + (4 * quadratic * constant).abs()) * 1e-12;
        if (discriminant < -discriminantTolerance) return const [];
        final adjustedDiscriminant = discriminant.abs() <= discriminantTolerance
            ? 0.0
            : discriminant;
        final root = dart_math.sqrt(dart_math.max(0, adjustedDiscriminant));
        if (root == 0) {
          parameters.add(-linear / (2 * quadratic));
        } else {
          final stableNumerator =
              -0.5 * (linear + (linear >= 0 ? root : -root));
          if (stableNumerator == 0) {
            parameters.add(-linear / (2 * quadratic));
          } else {
            parameters
              ..add(stableNumerator / quadratic)
              ..add(constant / stableNumerator);
          }
        }
      }

      final intersections = <Point3D>[];
      for (final t in parameters) {
        if (!t.isFinite || !inRange(line, t)) continue;
        final intersection = line.origin + line.direction * t;
        if (_pointOnConic(conic, intersection) &&
            liesOnConicPlane(intersection)) {
          intersections.add(intersection);
        }
      }
      return intersections;
    }

    ({Point3D center, double radius, Vector3D normal})? circleInfo(
      Conic3D conic,
    ) {
      final quadraticScale = dart_math.max(
        conic.quadraticX.abs(),
        conic.quadraticY.abs(),
      );
      if (quadraticScale == 0 ||
          (conic.quadraticX - conic.quadraticY).abs() >
              quadraticScale * 1e-10 ||
          conic.quadraticXY.abs() > quadraticScale * 1e-10) {
        return null;
      }
      final axisU = conic.axisU;
      final axisV = conic.axisV;
      if ((axisU.magnitude - 1).abs() > 1e-8 ||
          (axisV.magnitude - 1).abs() > 1e-8 ||
          axisU.dot(axisV).abs() > 1e-8) {
        return null;
      }
      final quadratic = (conic.quadraticX + conic.quadraticY) / 2;
      final centerX = -conic.linearX / (2 * quadratic);
      final centerY = -conic.linearY / (2 * quadratic);
      final radiusSquared =
          centerX * centerX + centerY * centerY - conic.constant / quadratic;
      final normal = axisU.cross(axisV).normalized();
      if (!radiusSquared.isFinite ||
          radiusSquared <= 0 ||
          normal.magnitude < 1e-9) {
        return null;
      }
      return (
        center: conic.origin + axisU * centerX + axisV * centerY,
        radius: dart_math.sqrt(radiusSquared),
        normal: normal,
      );
    }

    bool isClosedCircle(Object3D object, double radius) {
      if (object.type != Object3DType.curve ||
          object.conic == null ||
          object.curveStarts.isNotEmpty ||
          object.vertices.length < 4) {
        return false;
      }
      final closureTolerance = dart_math.max(1e-12, radius * 1e-7);
      return object.vertices.first.distanceTo(object.vertices.last) <=
          closureTolerance;
    }

    List<Point3D> circleIntersections(
      ({Point3D center, double radius, Vector3D normal}) firstCircle,
      ({Point3D center, double radius, Vector3D normal}) secondCircle,
    ) {
      final centerOffset = secondCircle.center - firstCircle.center;
      var coordinateScale = 0.0;
      for (final coordinate in [
        firstCircle.center.x.abs(),
        firstCircle.center.y.abs(),
        firstCircle.center.z.abs(),
        secondCircle.center.x.abs(),
        secondCircle.center.y.abs(),
        secondCircle.center.z.abs(),
      ]) {
        coordinateScale = dart_math.max(coordinateScale, coordinate).toDouble();
      }
      final scale = dart_math
          .max(
            firstCircle.radius,
            dart_math.max(secondCircle.radius, centerOffset.magnitude),
          )
          .toDouble();
      final tolerance = dart_math
          .max(1e-15, dart_math.max(scale * 1e-9, coordinateScale * 1e-14))
          .toDouble();
      final normalCross = firstCircle.normal.cross(secondCircle.normal);
      final normalCrossMagnitude = normalCross.magnitude;

      bool liesOnBoth(Point3D point) =>
          ((point - firstCircle.center).magnitude - firstCircle.radius).abs() <=
              tolerance * 2 &&
          ((point - secondCircle.center).magnitude - secondCircle.radius)
                  .abs() <=
              tolerance * 2 &&
          (point - firstCircle.center).dot(firstCircle.normal).abs() <=
              tolerance * 2 &&
          (point - secondCircle.center).dot(secondCircle.normal).abs() <=
              tolerance * 2;

      if (normalCrossMagnitude <= 1e-9) {
        if (centerOffset.dot(firstCircle.normal).abs() > tolerance) {
          return const [];
        }
        final inPlaneOffset =
            centerOffset -
            firstCircle.normal * centerOffset.dot(firstCircle.normal);
        final distance = inPlaneOffset.magnitude;
        if (distance <= tolerance ||
            distance > firstCircle.radius + secondCircle.radius + tolerance ||
            distance <
                (firstCircle.radius - secondCircle.radius).abs() - tolerance) {
          return const [];
        }
        final axis = inPlaneOffset * (1 / distance);
        final along =
            (firstCircle.radius * firstCircle.radius -
                secondCircle.radius * secondCircle.radius +
                distance * distance) /
            (2 * distance);
        var heightSquared =
            firstCircle.radius * firstCircle.radius - along * along;
        final squaredTolerance =
            tolerance * dart_math.max(firstCircle.radius, tolerance) * 2;
        if (heightSquared < -squaredTolerance) return const [];
        heightSquared = dart_math.max(0, heightSquared).toDouble();
        final base = firstCircle.center + axis * along;
        final height = dart_math.sqrt(heightSquared);
        if (height <= tolerance) {
          return liesOnBoth(base) ? [base] : const [];
        }
        final perpendicular = firstCircle.normal.cross(axis).normalized();
        return [
          for (final point in [
            base + perpendicular * height,
            base + perpendicular * -height,
          ])
            if (liesOnBoth(point)) point,
        ];
      }

      final lineDirection = normalCross * (1 / normalCrossMagnitude);
      final denominator = normalCross.dot(normalCross);
      final firstPlaneOffset = firstCircle.normal.dot(
        firstCircle.center.toVector(),
      );
      final secondPlaneOffset = secondCircle.normal.dot(
        secondCircle.center.toVector(),
      );
      final lineOriginVector =
          (secondCircle.normal.cross(normalCross) * firstPlaneOffset +
              normalCross.cross(firstCircle.normal) * secondPlaneOffset) *
          (1 / denominator);
      final lineOrigin = Point3D(
        lineOriginVector.x,
        lineOriginVector.y,
        lineOriginVector.z,
      );
      final closestToCenter =
          lineOrigin +
          lineDirection * (firstCircle.center - lineOrigin).dot(lineDirection);
      final centerDistance = closestToCenter.distanceTo(firstCircle.center);
      var heightSquared =
          firstCircle.radius * firstCircle.radius -
          centerDistance * centerDistance;
      final squaredTolerance =
          tolerance * dart_math.max(firstCircle.radius, tolerance) * 2;
      if (heightSquared < -squaredTolerance) return const [];
      heightSquared = dart_math.max(0, heightSquared).toDouble();
      final height = dart_math.sqrt(heightSquared);
      final candidates = height <= tolerance
          ? [closestToCenter]
          : [
              closestToCenter + lineDirection * height,
              closestToCenter + lineDirection * -height,
            ];
      return [
        for (final point in candidates)
          if (liesOnBoth(point)) point,
      ];
    }

    List<Point3D> lineMeshIntersections(
      ({Point3D origin, Vector3D direction, double minT, double maxT}) line,
      Object3D mesh,
    ) {
      final intersections = <({Point3D point, double scale})>[];
      final directionLength = line.direction.magnitude;
      if (!directionLength.isFinite || directionLength == 0) {
        return const [];
      }
      for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
        final ia = mesh.indices[i];
        final ib = mesh.indices[i + 1];
        final ic = mesh.indices[i + 2];
        if (ia < 0 ||
            ia >= mesh.vertices.length ||
            ib < 0 ||
            ib >= mesh.vertices.length ||
            ic < 0 ||
            ic >= mesh.vertices.length) {
          continue;
        }
        final a = mesh.vertices[ia];
        final b = mesh.vertices[ib];
        final c = mesh.vertices[ic];
        final triangleScale = dart_math
            .max(
              (b - a).magnitude,
              dart_math.max((c - b).magnitude, (a - c).magnitude),
            )
            .toDouble();
        final normal = _normalizedTriangleNormal(a, b, c);
        if (normal == null) continue;
        final denominator = normal.dot(line.direction);
        if (denominator.abs() <= directionLength * 1e-10) {
          continue;
        }
        final t = normal.dot(a - line.origin) / denominator;
        if (!inRange(line, t)) continue;
        final intersection = line.origin + line.direction * t;
        if (_pointInTriangle3D(intersection, a, b, c) &&
            intersections.every(
              (existing) =>
                  existing.point.distanceTo(intersection) >
                  intersectionTolerance(
                    existing.point,
                    intersection,
                    dart_math.max(existing.scale, triangleScale).toDouble(),
                  ),
            )) {
          intersections.add((point: intersection, scale: triangleScale));
        }
      }
      return [for (final intersection in intersections) intersection.point];
    }

    List<Object3D> curveSegments(Object3D curve) {
      final segments = <Object3D>[];
      for (var i = 1; i < curve.vertices.length; i++) {
        if (curve.curveStarts.contains(i)) continue;
        segments.add(
          Object3D.line(
            curve.vertices[i - 1],
            curve.vertices[i],
            lineKind: Line3DKind.segment,
            color: curve.color,
          ),
        );
      }
      return segments;
    }

    ({Point3D start, Point3D end, double tolerance})? coincidentSegmentOverlap(
      Object3D first,
      Object3D second,
    ) {
      final firstStart = first.pointA;
      final firstEnd = first.pointB;
      final secondStart = second.pointA;
      final secondEnd = second.pointB;
      final firstDirection = firstEnd - firstStart;
      final secondDirection = secondEnd - secondStart;
      final firstLength = firstDirection.magnitude;
      final secondLength = secondDirection.magnitude;
      if (!firstLength.isFinite ||
          !secondLength.isFinite ||
          firstLength == 0 ||
          secondLength == 0) {
        return null;
      }

      final scale = dart_math.max(firstLength, secondLength).toDouble();
      final tolerance = dart_math.max(
        intersectionTolerance(firstStart, secondStart, scale),
        intersectionTolerance(firstEnd, secondEnd, scale),
      );
      final firstAxis = firstDirection * (1 / firstLength);
      final secondAxis = secondDirection * (1 / secondLength);
      if (firstAxis.cross(secondAxis).magnitude > 1e-12) return null;

      final startOffset = secondStart - firstStart;
      final endOffset = secondEnd - firstStart;
      final startProjection = startOffset.dot(firstAxis);
      final endProjection = endOffset.dot(firstAxis);
      final startDeviation =
          (startOffset - firstAxis * startProjection).magnitude;
      final endDeviation = (endOffset - firstAxis * endProjection).magnitude;
      if (startDeviation > tolerance || endDeviation > tolerance) return null;

      final overlapStart = dart_math
          .max(0, dart_math.min(startProjection, endProjection))
          .toDouble();
      final overlapEnd = dart_math
          .min(firstLength, dart_math.max(startProjection, endProjection))
          .toDouble();
      if (overlapEnd - overlapStart <= tolerance) return null;
      return (
        start: firstStart + firstAxis * overlapStart,
        end: firstStart + firstAxis * overlapEnd,
        tolerance: tolerance,
      );
    }

    bool liesOnCoincidentOverlap(
      Point3D point,
      ({Point3D start, Point3D end, double tolerance}) overlap,
    ) {
      final direction = overlap.end - overlap.start;
      final lengthSquared = direction.dot(direction);
      if (lengthSquared == 0) return false;
      final fraction = (point - overlap.start).dot(direction) / lengthSquared;
      final fractionTolerance =
          overlap.tolerance / dart_math.sqrt(lengthSquared);
      if (fraction < -fractionTolerance || fraction > 1 + fractionTolerance) {
        return false;
      }
      final closest =
          overlap.start + direction * fraction.clamp(0.0, 1.0).toDouble();
      return point.distanceTo(closest) <= overlap.tolerance;
    }

    bool liesOnSampledCurve(Object3D curve, Point3D point) {
      for (var i = 1; i < curve.vertices.length; i++) {
        if (curve.curveStarts.contains(i)) continue;
        final start = curve.vertices[i - 1];
        final direction = curve.vertices[i] - start;
        final lengthSquared = direction.dot(direction);
        if (lengthSquared < 1e-18) {
          if (point.distanceTo(start) <= 1e-9) return true;
          continue;
        }
        final fraction = (point - start).dot(direction) / lengthSquared;
        if (fraction < -1e-9 || fraction > 1 + 1e-9) continue;
        final closest = start + direction * fraction.clamp(0.0, 1.0).toDouble();
        final tolerance = dart_math.max(
          1e-9,
          dart_math.sqrt(lengthSquared) * 0.02,
        );
        if (point.distanceTo(closest) <= tolerance) return true;
      }
      return false;
    }

    double intersectionFeatureScale(Object3D object) {
      final line = lineInfo(object);
      if (line == null ||
          (object.type != Object3DType.vector &&
              object.lineKind != Line3DKind.segment)) {
        return 0;
      }
      return line.direction.magnitude;
    }

    if (first.type == Object3DType.point) {
      return !first.isTextAnnotation && pointLiesOnObject(first.point, second)
          ? [first.point]
          : const [];
    }
    if (second.type == Object3DType.point) {
      return !second.isTextAnnotation && pointLiesOnObject(second.point, first)
          ? [second.point]
          : const [];
    }

    final conicFirstLine = lineInfo(first);
    final conicSecondLine = lineInfo(second);
    if (first.type == Object3DType.curve &&
        first.conic != null &&
        conicSecondLine != null) {
      return lineConicIntersections(
        conicSecondLine,
        first.conic!,
      ).where((point) => liesOnSampledCurve(first, point)).toList();
    }
    if (second.type == Object3DType.curve &&
        second.conic != null &&
        conicFirstLine != null) {
      return lineConicIntersections(
        conicFirstLine,
        second.conic!,
      ).where((point) => liesOnSampledCurve(second, point)).toList();
    }
    if (first.type == Object3DType.curve &&
        second.type == Object3DType.curve &&
        first.conic != null &&
        second.conic != null) {
      final firstCircle = circleInfo(first.conic!);
      final secondCircle = circleInfo(second.conic!);
      if (firstCircle != null &&
          secondCircle != null &&
          isClosedCircle(first, firstCircle.radius) &&
          isClosedCircle(second, secondCircle.radius)) {
        return circleIntersections(firstCircle, secondCircle);
      }
    }

    if (first.type == Object3DType.curve || second.type == Object3DType.curve) {
      final firstSegments = first.type == Object3DType.curve
          ? curveSegments(first)
          : [first];
      final secondSegments = second.type == Object3DType.curve
          ? curveSegments(second)
          : [second];
      final intersections = <({Point3D point, double scale})>[];
      final coincidentOverlaps =
          <({Point3D start, Point3D end, double tolerance})>[];
      for (final firstSegment in firstSegments) {
        for (final secondSegment in secondSegments) {
          if (first.type == Object3DType.curve &&
              second.type == Object3DType.curve) {
            final overlap = coincidentSegmentOverlap(
              firstSegment,
              secondSegment,
            );
            if (overlap != null) coincidentOverlaps.add(overlap);
          }
          final scale = dart_math
              .max(
                intersectionFeatureScale(firstSegment),
                intersectionFeatureScale(secondSegment),
              )
              .toDouble();
          for (final intersection in _createIntersectionPoints(
            firstSegment,
            secondSegment,
          )) {
            if (intersections.every(
              (existing) =>
                  existing.point.distanceTo(intersection) >
                  intersectionTolerance(
                    existing.point,
                    intersection,
                    dart_math.max(existing.scale, scale).toDouble(),
                  ),
            )) {
              intersections.add((point: intersection, scale: scale));
            }
          }
        }
      }
      return [
        for (final intersection in intersections)
          if (coincidentOverlaps.every(
            (overlap) => !liesOnCoincidentOverlap(intersection.point, overlap),
          ))
            intersection.point,
      ];
    }

    final firstLine = lineInfo(first);
    final secondLine = lineInfo(second);
    if (firstLine != null && secondLine != null) {
      final w = firstLine.origin - secondLine.origin;
      final a = firstLine.direction.dot(firstLine.direction);
      final b = firstLine.direction.dot(secondLine.direction);
      final c = secondLine.direction.dot(secondLine.direction);
      final d = firstLine.direction.dot(w);
      final e = secondLine.direction.dot(w);
      final denominator = a * c - b * b;
      final denominatorScale = a * c;
      if (denominatorScale == 0 ||
          denominator.abs() <= denominatorScale * 1e-12) {
        return collinearLineIntersectionPoints(firstLine, secondLine);
      }
      final firstT = (b * e - c * d) / denominator;
      final secondT = (a * e - b * d) / denominator;
      if (!inRange(firstLine, firstT) || !inRange(secondLine, secondT)) {
        return const [];
      }
      final firstPoint = firstLine.origin + firstLine.direction * firstT;
      final secondPoint = secondLine.origin + secondLine.direction * secondT;
      final scale = dart_math
          .max(finiteLineScale(firstLine), finiteLineScale(secondLine))
          .toDouble();
      final tolerance = intersectionTolerance(firstPoint, secondPoint, scale);
      return firstPoint.distanceTo(secondPoint) <= tolerance
          ? [firstPoint.midpoint(secondPoint)]
          : const [];
    }

    if (firstLine == null && secondLine == null) {
      final intersection = _createIntersectionCurve(first, second);
      if (intersection != null && intersection.type == Object3DType.point) {
        return [intersection.point];
      }
    }

    final line = firstLine ?? secondLine;
    final other = firstLine == null ? first : second;
    if (line == null) return const [];
    if (other.type == Object3DType.plane) {
      final point = linePlaneIntersection(line, other);
      return point == null ? const [] : [point];
    }
    if (other.type == Object3DType.sphere) {
      return lineSphereIntersections(line, other);
    }
    if (other.type == Object3DType.surface ||
        other.type == Object3DType.polyhedron) {
      return lineMeshIntersections(line, other);
    }
    return const [];
  }

  Object3D? _spherePlaneIntersection(Object3D sphere, Object3D plane) {
    final equation = _normalizedPlaneEquation(plane);
    if (equation == null) return null;
    final normal = equation.normal;
    final normalSquared = equation.normalSquared;
    final center = sphere.sphereCenter;
    final signedDistance =
        (normal.dot(center.toVector()) - equation.d) /
        dart_math.sqrt(normalSquared);
    final radius = sphere.sphereRadius.abs();
    final coordinateScale = dart_math.max(
      equation.d.abs(),
      dart_math.max(
        center.x.abs(),
        dart_math.max(center.y.abs(), center.z.abs()),
      ),
    );
    final geometryScale = dart_math.max(radius, signedDistance.abs());
    final tolerance = dart_math.max(
      geometryScale * 1e-12,
      coordinateScale * 1.7763568394002505e-15,
    );
    if (signedDistance.abs() > radius + tolerance) return null;
    final circleCenter =
        center +
        normal * ((equation.d - normal.dot(center.toVector())) / normalSquared);
    var radiusSquared = radius * radius - signedDistance * signedDistance;
    final radiusSquaredTolerance =
        tolerance * (radius + signedDistance.abs()) + tolerance * tolerance;
    if (radiusSquared < -radiusSquaredTolerance) return null;
    if (radiusSquared < 0) radiusSquared = 0;
    final circleRadius = dart_math.sqrt(radiusSquared);
    return _circleOnPlane(circleCenter, normal, circleRadius);
  }

  Object3D? _sphereSphereIntersection(Object3D first, Object3D second) {
    final delta = second.sphereCenter - first.sphereCenter;
    final distance = delta.magnitude;
    final firstRadius = first.sphereRadius.abs();
    final secondRadius = second.sphereRadius.abs();
    final coordinateScale = [
      first.sphereCenter.x.abs(),
      first.sphereCenter.y.abs(),
      first.sphereCenter.z.abs(),
      second.sphereCenter.x.abs(),
      second.sphereCenter.y.abs(),
      second.sphereCenter.z.abs(),
    ].fold<double>(0, (scale, value) => dart_math.max(scale, value).toDouble());
    final geometryScale = dart_math.max(
      distance,
      dart_math.max(firstRadius, secondRadius),
    );
    final tolerance = dart_math.max(
      geometryScale * 1e-12,
      coordinateScale * 1.7763568394002505e-15,
    );
    final radiusDifference = (firstRadius - secondRadius).abs();
    if (distance == 0) {
      return firstRadius == 0 && secondRadius == 0
          ? Object3D.point(first.sphereCenter, color: 0xFF1565C0)
          : null;
    }
    if (distance > firstRadius + secondRadius + tolerance ||
        distance < radiusDifference - tolerance) {
      return null;
    }
    final axis = delta * (1 / distance);
    final along =
        (firstRadius * firstRadius -
            secondRadius * secondRadius +
            distance * distance) /
        (2 * distance);
    final center = first.sphereCenter + axis * along;
    var radiusSquared = firstRadius * firstRadius - along * along;
    final radiusSquaredTolerance =
        tolerance * (firstRadius + along.abs()) + tolerance * tolerance;
    if (radiusSquared < -radiusSquaredTolerance) return null;
    if (radiusSquared < 0) radiusSquared = 0;
    final radius = dart_math.sqrt(radiusSquared);
    return _circleOnPlane(center, axis, radius);
  }

  Object3D _circleOnPlane(Point3D center, Vector3D normal, double radius) {
    if (radius == 0) {
      return Object3D.point(center, color: 0xFF1565C0);
    }
    var u = normal.cross(Vector3D.unitX).normalized();
    if (u.magnitude < 1e-9) u = normal.cross(Vector3D.unitY).normalized();
    final v = normal.normalized().cross(u).normalized();
    final points = List.generate(65, (i) {
      final angle = 2 * dart_math.pi * i / 64;
      return center +
          u * (radius * dart_math.cos(angle)) +
          v * (radius * dart_math.sin(angle));
    });
    return Object3D.curve(
      points: points,
      color: 0xFF1565C0,
      conic: Conic3D(
        origin: center,
        axisU: u,
        axisV: v,
        quadraticX: 1,
        quadraticXY: 0,
        quadraticY: 1,
        linearX: 0,
        linearY: 0,
        constant: -radius * radius,
      ),
    );
  }

  void _removeObjectAt(int index, {bool notify = true}) {
    final hadSelection =
        _selectedObjectIndex != null || _selectedPointIndex != null;
    setState(() {
      final dependencies = <int, _SolidSourceDependency>{};
      for (final entry in _constructionDependencies.entries) {
        if (entry.key == index) continue;
        final dependency = entry.value;
        for (var i = 0; i < dependency.sourcePointIndices.length; i++) {
          final sourceIndex = dependency.sourcePointIndices[i];
          if (sourceIndex == index) {
            dependency.sourcePointIndices[i] = null;
          } else if (sourceIndex != null && sourceIndex > index) {
            dependency.sourcePointIndices[i] = sourceIndex - 1;
          }
        }
        dependencies[entry.key > index ? entry.key - 1 : entry.key] =
            dependency;
      }
      _constructionDependencies
        ..clear()
        ..addAll(dependencies);
      _objects.removeAt(index);
      for (var i = 0; i < _constructionPointSources.length; i++) {
        final source = _constructionPointSources[i];
        if (source == index) {
          _constructionPointSources[i] = null;
        } else if (source != null && source > index) {
          _constructionPointSources[i] = source - 1;
        }
      }
      if (_selectedPointIndex == index) {
        _selectedPointIndex = null;
      } else if (_selectedPointIndex != null && _selectedPointIndex! > index) {
        _selectedPointIndex = _selectedPointIndex! - 1;
      }
      if (_selectedObjectIndex == index) {
        _selectedObjectIndex = null;
      } else if (_selectedObjectIndex != null &&
          _selectedObjectIndex! > index) {
        _selectedObjectIndex = _selectedObjectIndex! - 1;
      }
      final attachments = Map<int, int>.from(_pointAttachments);
      _pointAttachments
        ..clear()
        ..addEntries(
          attachments.entries
              .where((entry) => entry.key != index && entry.value != index)
              .map(
                (entry) => MapEntry(
                  entry.key > index ? entry.key - 1 : entry.key,
                  entry.value > index ? entry.value - 1 : entry.value,
                ),
              ),
        );
      if (_attachmentPointIndex == index) _attachmentPointIndex = null;
      if (_attachmentPointIndex != null && _attachmentPointIndex! > index) {
        _attachmentPointIndex = _attachmentPointIndex! - 1;
      }
      if (_styleSourceIndex == index) {
        _styleSourceIndex = null;
      } else if (_styleSourceIndex != null && _styleSourceIndex! > index) {
        _styleSourceIndex = _styleSourceIndex! - 1;
      }
      if (_intersectionSourceIndex == index) {
        _intersectionSourceIndex = null;
      } else if (_intersectionSourceIndex != null &&
          _intersectionSourceIndex! > index) {
        _intersectionSourceIndex = _intersectionSourceIndex! - 1;
      }
      if (_pointIntersectionSourceIndex == index) {
        _pointIntersectionSourceIndex = null;
      } else if (_pointIntersectionSourceIndex != null &&
          _pointIntersectionSourceIndex! > index) {
        _pointIntersectionSourceIndex = _pointIntersectionSourceIndex! - 1;
      }
      if (_conicSourceIndex == index) {
        _conicSourceIndex = null;
      } else if (_conicSourceIndex != null && _conicSourceIndex! > index) {
        _conicSourceIndex = _conicSourceIndex! - 1;
      }
      _objectsVersion++;
    });
    if (notify && hadSelection) {
      final selectedIndex = _selectedPointIndex ?? _selectedObjectIndex;
      widget.onSelectionChanged?.call(
        selectedIndex == null ? null : _objects[selectedIndex],
      );
    }
    if (notify) widget.onSceneChanged?.call();
  }

  bool _wouldCreateAttachmentCycle(int pointIndex, int targetIndex) {
    final visiting = <int>{};
    final visited = <int>{};
    bool visit(int index) {
      if (index < 0 || index >= _objects.length) return false;
      if (index == pointIndex || visiting.contains(index)) return true;
      if (visited.contains(index)) return false;
      visiting.add(index);
      final attachment = _pointAttachments[index];
      if (attachment != null && visit(attachment)) return true;
      final dependency = _constructionDependencies[index];
      if (dependency != null) {
        for (final source in dependency.sourcePointIndices) {
          if (source != null && visit(source)) return true;
        }
      }
      visiting.remove(index);
      visited.add(index);
      return false;
    }

    return visit(targetIndex);
  }

  int? _sourcePointIndexAt(Point3D position) {
    for (var i = 0; i < _objects.length; i++) {
      final object = _objects[i];
      if (object.type == Object3DType.point &&
          !object.isTextAnnotation &&
          object.visible &&
          object.opacity > 0 &&
          ((object.color >> 24) & 0xFF) > 0 &&
          object.point.distanceTo(position) <= 1e-8) {
        return i;
      }
    }
    return null;
  }

  void _propagateConstructionAndAttachmentMoves(int sourceIndex) {
    // Visit all reachable dependents in dependency order, including both kinds
    // of relationship. A visited set also bounds malformed cyclic documents.
    final visited = <int>{};
    final order = <int>[];
    void visit(int index) {
      if (index < 0 || index >= _objects.length || !visited.add(index)) return;
      for (final entry in _constructionDependencies.entries) {
        if (entry.value.sourcePointIndices.contains(index)) visit(entry.key);
      }
      for (final entry in _pointAttachments.entries) {
        if (entry.value == index) visit(entry.key);
      }
      order.add(index);
    }

    visit(sourceIndex);
    final changed = <int>{sourceIndex};
    for (final solidIndex in order.reversed) {
      if (solidIndex == sourceIndex) continue;
      final dependency = _constructionDependencies[solidIndex];
      if (dependency != null &&
          dependency.sourcePointIndices.any(changed.contains)) {
        for (var i = 0; i < dependency.sourcePointIndices.length; i++) {
          final sourceIndex = dependency.sourcePointIndices[i];
          if (sourceIndex == null ||
              sourceIndex < 0 ||
              sourceIndex >= _objects.length) {
            continue;
          }
          final sourcePoint = _objects[sourceIndex];
          if (sourcePoint.type == Object3DType.point &&
              !sourcePoint.isTextAnnotation) {
            dependency.points[i] = sourcePoint.point;
          }
        }

        final original = _objects[solidIndex];
        final construction = ConstructionState(
          tool: dependency.tool,
          polygonSides: dependency.polygonSides,
        );
        var acceptedAllPoints = true;
        for (var i = 0; i < dependency.points.length; i++) {
          final previousCount = construction.points.length;
          final closesCurve =
              i == dependency.points.length - 1 &&
              const {
                ConstructionTool.polygon,
                ConstructionTool.locus,
                ConstructionTool.polyline,
              }.contains(dependency.tool);
          construction.addPoint(
            closesCurve ? dependency.points.first : dependency.points[i],
            workingPlaneNormal: dependency.workingPlaneNormal,
            closeToFirstPoint: closesCurve,
          );
          if (construction.points.length != previousCount + 1) {
            acceptedAllPoints = false;
            break;
          }
        }
        if (acceptedAllPoints &&
            dependency.tool == ConstructionTool.area &&
            dependency.points.length >= 3) {
          construction.addPoint(
            dependency.points.first,
            workingPlaneNormal: dependency.workingPlaneNormal,
            closeToFirstPoint: true,
          );
        }
        final updated = construction.result;
        if (acceptedAllPoints && updated != null) {
          _objects[solidIndex] = updated.copyWith(
            documentId: original.documentId,
            label:
                const {
                  ConstructionTool.area,
                  ConstructionTool.angle,
                  ConstructionTool.distance,
                }.contains(dependency.tool)
                ? updated.label
                : original.label,
            color: original.color,
            opacity: original.opacity,
            edgeWidth: original.edgeWidth,
            showEdges: original.showEdges,
            visible: original.visible,
          );
          changed.add(solidIndex);
        }
      }
      final targetIndex = _pointAttachments[solidIndex];
      if (targetIndex != null &&
          changed.contains(targetIndex) &&
          targetIndex >= 0 &&
          targetIndex < _objects.length) {
        final point = _objects[solidIndex];
        if (point.type == Object3DType.point) {
          final position = _constrainPointToObject(
            point.point,
            _objects[targetIndex],
          );
          if (position != point.point) {
            _objects[solidIndex] = point.copyWith(point: position);
            changed.add(solidIndex);
          }
        }
      }
    }
  }

  double? _objectVolume(Object3D object) {
    if (object.type == Object3DType.sphere) {
      final radius = object.sphereRadius.abs();
      return 4 / 3 * dart_math.pi * radius * radius * radius;
    }
    if (object.type != Object3DType.polyhedron || !_isClosedMesh(object)) {
      return null;
    }

    final faceCount = object.indices.length ~/ 3;
    final adjacentFaces = List.generate(faceCount, (_) => <int>{});
    final edgeFaces = <String, List<int>>{};
    String edgeKey(int first, int second) =>
        first < second ? '$first:$second' : '$second:$first';
    for (var face = 0; face < faceCount; face++) {
      final offset = face * 3;
      final a = object.indices[offset];
      final b = object.indices[offset + 1];
      final c = object.indices[offset + 2];
      for (final edge in [(a, b), (b, c), (c, a)]) {
        edgeFaces.putIfAbsent(edgeKey(edge.$1, edge.$2), () => []).add(face);
      }
    }
    for (final faces in edgeFaces.values) {
      if (faces.length == 2) {
        adjacentFaces[faces[0]].add(faces[1]);
        adjacentFaces[faces[1]].add(faces[0]);
      }
    }

    final visitedFaces = <int>{};
    var totalVolume = 0.0;
    for (var seed = 0; seed < faceCount; seed++) {
      if (!visitedFaces.add(seed)) continue;

      final firstIndex = object.indices[seed * 3];
      final reference = object.vertices[firstIndex];
      final pendingFaces = <int>[seed];
      var componentVolume = 0.0;
      while (pendingFaces.isNotEmpty) {
        final face = pendingFaces.removeLast();
        final offset = face * 3;
        final a = object.vertices[object.indices[offset]] - reference;
        final b = object.vertices[object.indices[offset + 1]] - reference;
        final c = object.vertices[object.indices[offset + 2]] - reference;
        componentVolume += a.dot(b.cross(c)) / 6;
        for (final adjacent in adjacentFaces[face]) {
          if (visitedFaces.add(adjacent)) pendingFaces.add(adjacent);
        }
      }
      totalVolume += componentVolume.abs();
    }
    return totalVolume;
  }

  bool _isClosedMesh(Object3D object) {
    if (object.indices.length < 12 || object.indices.length % 3 != 0) {
      return false;
    }
    final edgeUseCount = <String, int>{};
    final edgeDirectionBalance = <String, int>{};
    void countEdge(int first, int second) {
      final key = first < second ? '$first:$second' : '$second:$first';
      edgeUseCount.update(key, (count) => count + 1, ifAbsent: () => 1);
      final direction = first < second ? 1 : -1;
      edgeDirectionBalance.update(
        key,
        (balance) => balance + direction,
        ifAbsent: () => direction,
      );
    }

    for (var i = 0; i + 2 < object.indices.length; i += 3) {
      final a = object.indices[i];
      final b = object.indices[i + 1];
      final c = object.indices[i + 2];
      if (a < 0 ||
          b < 0 ||
          c < 0 ||
          a >= object.vertices.length ||
          b >= object.vertices.length ||
          c >= object.vertices.length) {
        return false;
      }
      countEdge(a, b);
      countEdge(b, c);
      countEdge(c, a);
    }
    return edgeUseCount.entries.every(
      (edge) => edge.value == 2 && edgeDirectionBalance[edge.key] == 0,
    );
  }

  Object3D? _unfoldPolyhedron(Object3D object) {
    if (object.type != Object3DType.polyhedron ||
        object.indices.length < 3 ||
        object.indices.length % 3 != 0) {
      return null;
    }
    final triangles = <List<int>>[];
    final edgeFaces = <String, List<int>>{};

    String edgeKey(int first, int second) =>
        first < second ? '$first:$second' : '$second:$first';

    for (var i = 0; i + 2 < object.indices.length; i += 3) {
      final triangle = [
        object.indices[i],
        object.indices[i + 1],
        object.indices[i + 2],
      ];
      if (triangle.any(
        (index) => index < 0 || index >= object.vertices.length,
      )) {
        return null;
      }
      final faceIndex = triangles.length;
      triangles.add(triangle);
      for (var edge = 0; edge < 3; edge++) {
        final key = edgeKey(triangle[edge], triangle[(edge + 1) % 3]);
        edgeFaces.putIfAbsent(key, () => []).add(faceIndex);
      }
    }

    final unfoldedFaces = List<List<Offset>?>.filled(triangles.length, null);
    var componentOffsetX = 0.0;
    for (var start = 0; start < triangles.length; start++) {
      if (unfoldedFaces[start] != null) continue;
      final triangle = triangles[start];
      final a = object.vertices[triangle[0]];
      final b = object.vertices[triangle[1]];
      final c = object.vertices[triangle[2]];
      final edgeLength = a.distanceTo(b);
      if (edgeLength < 1e-9) continue;
      final distanceAC = a.distanceTo(c);
      final distanceBC = b.distanceTo(c);
      final along =
          (distanceAC * distanceAC -
              distanceBC * distanceBC +
              edgeLength * edgeLength) /
          (2 * edgeLength);
      final height = dart_math.sqrt(
        dart_math.max(0, distanceAC * distanceAC - along * along),
      );
      unfoldedFaces[start] = [
        Offset(componentOffsetX, 0),
        Offset(componentOffsetX + edgeLength, 0),
        Offset(componentOffsetX + along, height),
      ];
      final queue = <int>[start];
      var queueIndex = 0;
      var componentMaxX = componentOffsetX + edgeLength + along.abs();

      while (queueIndex < queue.length) {
        final parentIndex = queue[queueIndex++];
        final parentIds = triangles[parentIndex];
        final parentPoints = unfoldedFaces[parentIndex]!;
        for (var edge = 0; edge < 3; edge++) {
          final sharedA = parentIds[edge];
          final sharedB = parentIds[(edge + 1) % 3];
          final key = edgeKey(sharedA, sharedB);
          for (final childIndex in edgeFaces[key] ?? const <int>[]) {
            if (childIndex == parentIndex || unfoldedFaces[childIndex] != null)
              continue;
            final childIds = triangles[childIndex];
            final parentAIndex = parentIds.indexOf(sharedA);
            final parentBIndex = parentIds.indexOf(sharedB);
            final parentThirdIndex = 3 - parentAIndex - parentBIndex;
            final childAIndex = childIds.indexOf(sharedA);
            final childBIndex = childIds.indexOf(sharedB);
            if (childAIndex < 0 || childBIndex < 0) continue;
            final childThirdIndex = 3 - childAIndex - childBIndex;
            final pointA = parentPoints[parentAIndex];
            final pointB = parentPoints[parentBIndex];
            final edgeVector = pointB - pointA;
            final flatEdgeLength = edgeVector.distance;
            if (flatEdgeLength < 1e-9) continue;
            final direction = Offset(
              edgeVector.dx / flatEdgeLength,
              edgeVector.dy / flatEdgeLength,
            );
            final thirdPoint3D = object.vertices[childIds[childThirdIndex]];
            final sharedPointA3D = object.vertices[sharedA];
            final sharedPointB3D = object.vertices[sharedB];
            final distanceA = thirdPoint3D.distanceTo(sharedPointA3D);
            final distanceB = thirdPoint3D.distanceTo(sharedPointB3D);
            final childAlong =
                (distanceA * distanceA -
                    distanceB * distanceB +
                    flatEdgeLength * flatEdgeLength) /
                (2 * flatEdgeLength);
            final childHeight = dart_math.sqrt(
              dart_math.max(0, distanceA * distanceA - childAlong * childAlong),
            );
            final parentThird = parentPoints[parentThirdIndex];
            final parentSide =
                edgeVector.dx * (parentThird.dy - pointA.dy) -
                edgeVector.dy * (parentThird.dx - pointA.dx);
            final outward =
                Offset(-direction.dy, direction.dx) *
                (parentSide >= 0 ? -1 : 1);
            final childPoints = List<Offset>.filled(3, Offset.zero);
            childPoints[childAIndex] = pointA;
            childPoints[childBIndex] = pointB;
            childPoints[childThirdIndex] =
                pointA + direction * childAlong + outward * childHeight;
            unfoldedFaces[childIndex] = childPoints;
            for (final point in childPoints) {
              componentMaxX = dart_math.max(componentMaxX, point.dx).toDouble();
            }
            queue.add(childIndex);
          }
        }
      }
      componentOffsetX = componentMaxX + 1;
    }

    final vertices = <Point3D>[];
    final indices = <int>[];
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final face in unfoldedFaces) {
      if (face == null) continue;
      for (final point in face) {
        minX = dart_math.min(minX, point.dx).toDouble();
        maxX = dart_math.max(maxX, point.dx).toDouble();
        minY = dart_math.min(minY, point.dy).toDouble();
        maxY = dart_math.max(maxY, point.dy).toDouble();
      }
    }
    if (!minX.isFinite) return null;
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final view = camera.viewMatrix();
    final right = Vector3D(view[0], view[4], view[8]).normalized();
    final up = Vector3D(view[1], view[5], view[9]).normalized();
    final viewCenter = camera.target;
    for (final face in unfoldedFaces) {
      if (face == null) continue;
      final firstIndex = vertices.length;
      vertices.addAll(
        face.map(
          (point) =>
              viewCenter +
              right * (point.dx - centerX) +
              up * (point.dy - centerY),
        ),
      );
      indices.addAll([firstIndex, firstIndex + 1, firstIndex + 2]);
    }
    if (indices.isEmpty) return null;
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: object.color,
      label: _label('展开图'),
    );
  }

  bool _cancelPointDrag() {
    var rolledBack = false;
    if (_pointBeforeDrag != null && _selectedPointIndex != null) {
      _objects[_selectedPointIndex!] = _pointBeforeDrag!;
      _propagateConstructionAndAttachmentMoves(_selectedPointIndex!);
      _objectsVersion++;
      rolledBack = true;
    }
    _pointBeforeDrag = null;
    _pointEditPointer = null;
    return rolledBack;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_interactionAllowed(event.kind)) return;
    _focusNode.requestFocus();
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      var sceneRolledBack = false;
      setState(() {
        sceneRolledBack = _cancelPointDrag();
        _multiTouch = true;
        _constGroundPos = null;
        _constStartPoint = null;
        _constructionPreview = null;
      });
      if (sceneRolledBack) widget.onSceneChanged?.call();
      return;
    }
    _multiTouch = false;
    _suppressScale = false;
    _pointerDownPosition = event.localPosition;
    _objectActionGestureMoved = false;
    final secondary = event.buttons & kSecondaryMouseButton != 0;
    final primary = event.buttons & kPrimaryMouseButton != 0;
    final mayEditPoint =
        event.kind != PointerDeviceKind.mouse || (primary && !secondary);
    if (mayEditPoint &&
        !_panModifierPressed &&
        (_currentTool == ConstructionTool.move ||
            _currentTool == ConstructionTool.point)) {
      final hit = _hitPoint(event.localPosition);
      final objectHit = hit == null && _currentTool == ConstructionTool.move
          ? _hitObjectIndex(event.localPosition)
          : null;
      _pointWasSelected = hit != null && hit == _selectedPointIndex;
      setState(() {
        _selectedPointIndex = hit;
        _selectedObjectIndex = objectHit;
        if (hit != null) {
          if (!_pointWasSelected) _pointDragMode = PointDragMode.plane;
          _pointEditPointer = event.pointer;
          _pointBeforeDrag = _objects[hit];
          _pointMoved = false;
          _suppressScale = true;
        }
        if (objectHit != null) _suppressScale = true;
      });
      widget.onSelectionChanged?.call(
        hit != null
            ? _objects[hit]
            : objectHit == null
            ? null
            : _objects[objectHit],
      );
      if (hit != null || objectHit != null) return;
    }
    if (event.kind != PointerDeviceKind.mouse) return;
    final navigationTool =
        ToolInfo.all[_currentTool]!.behavior == ToolBehavior.navigation;
    final mayNavigate = navigationTool || secondary || _panModifierPressed;
    if (!mayNavigate || (!primary && !secondary)) return;
    _mousePointer = event.pointer;
    _lastMousePosition = event.localPosition;
    _mouseGesture = secondary
        ? _NavigationGesture.orbit
        : (_currentTool == ConstructionTool.panView || _panModifierPressed
              ? _NavigationGesture.pan
              : _NavigationGesture.orbit);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_interactionAllowed(event.kind)) return;
    if (!_objectActionGestureMoved &&
        ToolInfo.all[_currentTool]!.behavior == ToolBehavior.objectAction &&
        _pointerDownPosition != null &&
        (event.localPosition - _pointerDownPosition!).distance >= 5) {
      _objectActionGestureMoved = true;
    }
    if (event.pointer == _pointEditPointer && !_multiTouch) {
      final delta = event.localPosition - _pointerDownPosition!;
      if (!_pointMoved && delta.distance < 5) return;
      _pointMoved = true;
      final start = _pointBeforeDrag!.point;
      Point3D position;
      if (_pointDragMode == PointDragMode.height) {
        final projection = _currentProjection();
        final a = worldToScreen(start, camera, projection);
        // Keep the reference in front of the eye even at the closest zoom.
        final heightStep = projection.type == ProjectionType.perspective
            ? dart_math.min(1.0, a.z / 2)
            : 1.0;
        final b = worldToScreen(
          start + Vector3D.unitZ * heightStep,
          camera,
          projection,
        );
        final axis = Offset(b.x - a.x, b.y - a.y);
        // Looking straight down makes the z axis collapse to a screen point.
        // Keep an intuitive upward drag in that view as well.
        var dz = axis.distanceSquared > 16
            ? (delta.dx * axis.dx + delta.dy * axis.dy) / axis.distanceSquared
            : -delta.dy * _computeScaleForCanvas() * 2 / _canvasHeight;
        if (projection.type == ProjectionType.perspective &&
            axis.distanceSquared > 16) {
          final denominator = (1 - dz) * b.z + dz * a.z;
          if (denominator <= 1e-6) return;
          dz = dz * a.z / denominator;
        }
        if (axis.distanceSquared > 16) dz *= heightStep;
        position = Point3D(start.x, start.y, start.z + dz);
      } else {
        final startRay = _screenRay(
          _pointerDownPosition!.dx,
          _pointerDownPosition!.dy,
        );
        final ray = _screenRay(event.localPosition.dx, event.localPosition.dy);
        final a = _intersectWorkingPlane(
          startRay,
          point: start,
          normal: Vector3D.unitZ,
        );
        final b = _intersectWorkingPlane(
          ray,
          point: start,
          normal: Vector3D.unitZ,
        );
        if (ray.direction.z.abs() > 0.02 && a != null && b != null) {
          final offset = b - a;
          position = Point3D(start.x + offset.x, start.y + offset.y, start.z);
        } else {
          // A horizontal plane is edge-on in front/side views.
          final view = camera.viewMatrix();
          final right = Vector3D(view[0], view[4], 0).normalized();
          position =
              start +
              right * (delta.dx * _computeScaleForCanvas() * 2 / _canvasHeight);
        }
      }
      if (![position.x, position.y, position.z].every((v) => v.isFinite))
        return;
      final attachedObject = _pointAttachments[_selectedPointIndex!];
      if (attachedObject != null &&
          attachedObject >= 0 &&
          attachedObject < _objects.length) {
        position = _constrainPointToObject(position, _objects[attachedObject]);
      }
      setState(() {
        final selectedIndex = _selectedPointIndex!;
        _objects[selectedIndex] = _pointBeforeDrag!.copyWith(point: position);
        _propagateConstructionAndAttachmentMoves(selectedIndex);
        _objectsVersion++;
      });
      return;
    }
    if (event.pointer != _mousePointer || _lastMousePosition == null) return;
    final delta = event.localPosition - _lastMousePosition!;
    _lastMousePosition = event.localPosition;
    if (delta == Offset.zero) return;
    switch (_mouseGesture) {
      case _NavigationGesture.orbit:
        _orbitBy(delta);
      case _NavigationGesture.pan:
        _panBy(delta);
      case _NavigationGesture.none:
        break;
    }
  }

  void _onPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer == _pointEditPointer) {
      setState(() {
        if (!_pointMoved && _pointWasSelected) {
          _pointDragMode = _pointDragMode == PointDragMode.plane
              ? PointDragMode.height
              : PointDragMode.plane;
        }
        _pointBeforeDrag = null;
        _pointEditPointer = null;
      });
      if (_pointMoved) widget.onSceneChanged?.call();
      widget.onViewportChange?.call();
    }
    if (event.pointer != _mousePointer) return;
    _mousePointer = null;
    _lastMousePosition = null;
    _mouseGesture = _NavigationGesture.none;
    widget.onViewportChange?.call();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!_interactionAllowed(event.kind) &&
        !_activePointers.contains(event.pointer) &&
        event.pointer != _pointEditPointer &&
        event.pointer != _mousePointer) {
      return;
    }
    _activePointers.remove(event.pointer);
    var sceneRolledBack = false;
    setState(() {
      sceneRolledBack = _cancelPointDrag();
      _suppressScale = true;
      _constGroundPos = null;
      _constStartPoint = null;
      _constructionPreview = null;
    });
    if (sceneRolledBack) widget.onSceneChanged?.call();
    _onPointerUp(event);
  }

  void _orbitBy(Offset delta) {
    setState(() {
      _cameraTheta += delta.dx * 0.008;
      _cameraPhi = (_cameraPhi + delta.dy * 0.008).clamp(
        -dart_math.pi * 0.49,
        dart_math.pi * 0.49,
      );
    });
  }

  Camera3D _panCamera(Camera3D cam, Offset delta) {
    final projection = _projectionType == ProjectionType.parallel
        ? Projection3D.parallel(
            width: _canvasWidth,
            height: _canvasHeight,
            scale: cam.distance * _orthographicDistanceScale,
          )
        : _currentProjection();
    return cam.pan(deltaX: delta.dx, deltaY: delta.dy, projection: projection);
  }

  void _panBy(Offset delta) {
    final panned = _panCamera(camera, delta);
    setState(() => _cameraTarget = panned.target);
  }

  void _zoomBy(double factor, {Offset? focalPoint}) {
    if (!factor.isFinite || factor <= 0) return;
    final oldDistance = _cameraDistance;
    final newDistance = (oldDistance / factor)
        .clamp(0.25, double.maxFinite)
        .toDouble();
    if ((newDistance - oldDistance).abs() < 1e-10) return;

    var newTarget = _cameraTarget;
    if (focalPoint != null &&
        _projectionType == ProjectionType.parallel &&
        _canvasWidth > 0 &&
        _canvasHeight > 0) {
      final view = camera.viewMatrix();
      final right = Vector3D(view[0], view[4], view[8]);
      final up = Vector3D(view[1], view[5], view[9]);
      final ndcX = 2 * focalPoint.dx / _canvasWidth - 1;
      final ndcY = 1 - 2 * focalPoint.dy / _canvasHeight;
      final aspect = _canvasWidth / _canvasHeight;
      final oldHalfHeight = oldDistance * _orthographicDistanceScale;
      final newHalfHeight = newDistance * _orthographicDistanceScale;
      final difference = oldHalfHeight - newHalfHeight;
      final shift =
          right * (ndcX * difference * aspect) + up * (ndcY * difference);
      newTarget = _cameraTarget + shift;
    }

    setState(() {
      _cameraDistance = newDistance;
      _cameraTarget = newTarget;
    });
    widget.onViewportChange?.call();
  }

  void _setView({required double theta, required double phi}) {
    setState(() {
      _cameraTheta = theta;
      _cameraPhi = phi;
    });
    widget.onViewportChange?.call();
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_mousePointer != null) return;
    _lastFocalPoint = details.localFocalPoint;
    _initialScaleDistance = _cameraDistance;
    if (_suppressScale || _multiTouch) return;

    final behavior = ToolInfo.all[_currentTool]!.behavior;
    if (behavior == ToolBehavior.objectAction) {
      _constStartPoint = details.localFocalPoint;
      _lastFocalPoint = details.localFocalPoint;
      return;
    }

    // In construction mode, start tracking a point on the active working
    // plane. The first point uses a coordinate plane; later points use a
    // screen-facing plane through the previous construction point.
    if (behavior == ToolBehavior.construction && _construction != null) {
      _constStartPoint = _pointerDownPosition ?? details.localFocalPoint;
      _constGroundPos = _screenToConstructionPlane(
        _constStartPoint!.dx,
        _constStartPoint!.dy,
        snap: true,
        normalOverride: _constructionPlaneNormal,
      );
      _constPlaneNormal = _constructionPlaneNormal;
      _constHeight = 0;
      _constPointPlaced = false;
      _updateConstructionPreview(_constGroundPos);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_mousePointer != null) return;
    final focalPoint = details.localFocalPoint;
    final scale = details.scale;
    if (details.pointerCount < 2 && (_suppressScale || _multiTouch)) return;

    final behavior = ToolInfo.all[_currentTool]!.behavior;
    if (behavior == ToolBehavior.objectAction) {
      _lastFocalPoint = focalPoint;
      return;
    }

    // ===== Construction mode: tap → point on a working plane, drag →
    // adjust height or move across the screen-facing construction plane.
    if (behavior == ToolBehavior.construction &&
        _construction != null &&
        !_constPointPlaced &&
        !_multiTouch &&
        details.pointerCount == 1) {
      if (_constGroundPos != null && _constStartPoint != null) {
        final preview = _constructionPointForDrag(focalPoint);
        _updateConstructionPreview(preview);
      }
      _lastFocalPoint = focalPoint;
      return; // Don't orbit during construction
    }

    // ===== Standard orbit/pan/zoom (Move tool or no construction active)
    if (details.pointerCount == 1) {
      // Single finger: orbit
      final dx = _lastFocalPoint == null
          ? 0.0
          : (focalPoint.dx - _lastFocalPoint!.dx);
      final dy = _lastFocalPoint == null
          ? 0.0
          : (focalPoint.dy - _lastFocalPoint!.dy);

      if (_currentTool == ConstructionTool.panView) {
        _panBy(Offset(dx, dy));
      } else {
        _orbitBy(Offset(dx, dy));
      }
    } else if (details.pointerCount >= 2) {
      // GeoGebra combines two-finger translation and pinch in one gesture.
      final delta = _lastFocalPoint == null
          ? Offset.zero
          : focalPoint - _lastFocalPoint!;
      final startDistance = _initialScaleDistance ?? _cameraDistance;
      final newDistance = (startDistance / scale)
          .clamp(0.25, double.maxFinite)
          .toDouble();
      final panned = _panCamera(
        Camera3D(
          target: _cameraTarget,
          distance: newDistance,
          theta: _cameraTheta,
          phi: _cameraPhi,
        ),
        delta,
      );
      setState(() {
        _cameraDistance = newDistance;
        _cameraTarget = panned.target;
      });
    }

    _lastFocalPoint = focalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mousePointer != null) return;
    if (_suppressScale || _multiTouch) {
      _lastFocalPoint = null;
      _constGroundPos = null;
      _constStartPoint = null;
      _objectActionGestureMoved = false;
      return;
    }
    final behavior = ToolInfo.all[_currentTool]!.behavior;
    if (behavior == ToolBehavior.objectAction && _constStartPoint != null) {
      if (!_objectActionGestureMoved) {
        _performObjectAction(_lastFocalPoint ?? _constStartPoint!);
      }
      _objectActionGestureMoved = false;
      _constStartPoint = null;
      _lastFocalPoint = null;
      widget.onViewportChange?.call();
      return;
    }
    // ===== Construction mode: finalize the point with the latest spatial
    // position. A second sphere point therefore remains in 3D instead of
    // falling back to z=0.
    if (behavior == ToolBehavior.construction &&
        _construction != null &&
        !_constPointPlaced &&
        _constGroundPos != null) {
      _constPointPlaced = true;
      final finalPos = _constructionPointForDrag(
        _lastFocalPoint ?? _constStartPoint!,
      );
      _handleConstructionPoint(finalPos);

      _constGroundPos = null;
      _constStartPoint = null;
      _constPlaneNormal = null;
      _lastFocalPoint = null;
      widget.onViewportChange?.call();
      return;
    }

    // Handle the case where user just tapped without dragging
    if (behavior == ToolBehavior.construction &&
        _construction != null &&
        !_constPointPlaced &&
        _constGroundPos == null &&
        _constStartPoint != null) {
      // Place point on the active working plane at the tap position.
      _constPointPlaced = true;
      final groundPos = _screenToConstructionPlane(
        _constStartPoint!.dx,
        _constStartPoint!.dy,
        snap: true,
      );
      _handleConstructionPoint(groundPos);

      _constGroundPos = null;
      _constStartPoint = null;
      _constPlaneNormal = null;
      _lastFocalPoint = null;
      widget.onViewportChange?.call();
      return;
    }

    _lastFocalPoint = null;
    _constStartPoint = null;
    _constGroundPos = null;
    _constPlaneNormal = null;
    _constructionPreview = null;
    widget.onViewportChange?.call();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.allowMouseGestures) return;
    if (event is PointerScrollEvent) {
      // Wheel up zooms in, wheel down zooms out. Exponential scaling keeps
      // mouse wheels and high-resolution touchpads consistent.
      final factor = dart_math.exp(-event.scrollDelta.dy * 0.0015);
      _zoomBy(factor, focalPoint: event.localPosition);
    }
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!widget.allowMouseGestures) return;
    _focusNode.requestFocus();
    _panZoomInitialDistance = _cameraDistance;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!widget.allowMouseGestures) return;
    final initialDistance = _panZoomInitialDistance ?? _cameraDistance;
    final newDistance = (initialDistance / event.scale)
        .clamp(0.25, double.maxFinite)
        .toDouble();
    final panned = _panCamera(
      Camera3D(
        target: _cameraTarget,
        distance: newDistance,
        theta: _cameraTheta,
        phi: _cameraPhi,
      ),
      event.panDelta,
    );
    setState(() {
      _cameraDistance = newDistance;
      _cameraTarget = panned.target;
    });
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!widget.allowMouseGestures) return;
    _panZoomInitialDistance = null;
    widget.onViewportChange?.call();
  }

  bool _interactionAllowed(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse ||
    PointerDeviceKind.trackpad => widget.allowMouseGestures,
    PointerDeviceKind.touch ||
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus => widget.allowTouchGestures,
    _ => widget.allowMouseGestures || widget.allowTouchGestures,
  };

  // ==================================================================
  // Construction click handling
  // ==================================================================

  /// Compute the orthographic scale matching the painter's projection.
  double _computeScaleForCanvas() {
    return _cameraDistance.clamp(0.25, double.maxFinite) *
        _orthographicDistanceScale;
  }

  Ray3D _screenRay(double screenX, double screenY) {
    final cam = camera;
    final viewMatrix = cam.viewMatrix();
    final pos = cam.position;
    final right = Vector3D(viewMatrix[0], viewMatrix[4], viewMatrix[8]);
    final up = Vector3D(viewMatrix[1], viewMatrix[5], viewMatrix[9]);
    final forward = (_cameraTarget - pos).normalized();
    final ndcX = 2 * screenX / _canvasWidth - 1;
    final ndcY = 1 - 2 * screenY / _canvasHeight;
    final aspect = _canvasWidth / _canvasHeight;

    if (_projectionType == ProjectionType.parallel) {
      final halfHeight = _computeScaleForCanvas();
      final offset =
          right * (ndcX * halfHeight * aspect) + up * (ndcY * halfHeight);
      return Ray3D(pos + offset, forward);
    }

    final tanHalfFov = dart_math.tan(dart_math.pi / 6);
    return Ray3D(
      pos,
      (forward +
              right * (ndcX * tanHalfFov * aspect) +
              up * (ndcY * tanHalfFov))
          .normalized(),
    );
  }

  Point3D? _intersectWorkingPlane(
    Ray3D ray, {
    required Point3D point,
    required Vector3D normal,
  }) => intersectRayPlane(
    ray,
    point: point,
    normal: normal,
    allowBehind: _projectionType == ProjectionType.parallel,
  );

  Projection3D _currentProjection({bool includeHidden = false}) {
    return _projectionType == ProjectionType.parallel
        ? Projection3D.parallel(
            width: _canvasWidth,
            height: _canvasHeight,
            scale: _computeScaleForCanvas(),
          )
        : Projection3D.perspective(
            width: _canvasWidth,
            height: _canvasHeight,
            fov: 60,
            far: _perspectiveFarPlane(
              _objects,
              _cameraTarget,
              _cameraDistance,
              preview: _constructionPreview,
              includeHidden: includeHidden,
            ),
          );
  }

  Vector3D get _constructionPlaneNormal {
    if ((_construction?.points ?? const <Point3D>[]).isEmpty) {
      return Vector3D.unitZ;
    }
    return (_cameraTarget - camera.position).normalized();
  }

  Point3D? _nearestSnappedPoint(double screenX, double screenY) {
    if (_canvasWidth <= 0 || _canvasHeight <= 0) return null;
    final projection = _currentProjection();
    bool pointInDepthRange(Point3D point) {
      final depth = worldToScreen(point, camera, projection).z;
      return projection.type == ProjectionType.parallel ||
          (depth >= projection.near && depth <= projection.far);
    }

    final candidates = <Point3D>[
      if (pointInDepthRange(Point3D.origin)) Point3D.origin,
    ];
    if (const {
      ConstructionTool.polygon,
      ConstructionTool.area,
      ConstructionTool.polyline,
      ConstructionTool.locus,
    }.contains(_currentTool)) {
      final points = _construction?.points ?? const <Point3D>[];
      if (points.isNotEmpty && pointInDepthRange(points.first)) {
        candidates.add(points.first);
      }
    }
    final surfaceCandidates = <Point3D>[];
    final segmentCandidates = Set<Point3D>.identity();

    void addSegmentCandidate(Point3D a, Point3D b) {
      if (projection.type == ProjectionType.perspective) {
        final depthA = worldToScreen(a, camera, projection).z;
        final depthB = worldToScreen(b, camera, projection).z;
        final delta = depthB - depthA;
        if (!depthA.isFinite || !depthB.isFinite) return;
        if (delta.abs() < 1e-12) {
          if (depthA < projection.near || depthA > projection.far) return;
        } else {
          final nearT = (projection.near - depthA) / delta;
          final farT = (projection.far - depthA) / delta;
          final start = dart_math.max(0.0, dart_math.min(nearT, farT));
          final end = dart_math.min(1.0, dart_math.max(nearT, farT));
          if (start > end) return;
          final edge = b - a;
          b = a + edge * end;
          a = a + edge * start;
        }
      }
      final aScreen = worldToScreen(a, camera, projection);
      final bScreen = worldToScreen(b, camera, projection);
      final dx = bScreen.x - aScreen.x;
      final dy = bScreen.y - aScreen.y;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared < 1e-9
          ? 0.0
          : ((screenX - aScreen.x) * dx + (screenY - aScreen.y) * dy) /
                lengthSquared;
      var clampedT = t.clamp(0.0, 1.0).toDouble();
      if (projection.type == ProjectionType.perspective &&
          aScreen.z > 0 &&
          bScreen.z > 0) {
        clampedT =
            clampedT *
            aScreen.z /
            ((1 - clampedT) * bScreen.z + clampedT * aScreen.z);
      }
      final candidate = Point3D(
        a.x + (b.x - a.x) * clampedT,
        a.y + (b.y - a.y) * clampedT,
        a.z + (b.z - a.z) * clampedT,
      );
      candidates.add(candidate);
      segmentCandidates.add(candidate);
    }

    final ray = _screenRay(screenX, screenY);
    for (final object in _objects) {
      if (!object.visible ||
          object.opacity <= 0 ||
          ((object.color >> 24) & 0xFF) == 0) {
        continue;
      }
      switch (object.type) {
        case Object3DType.point:
          if (pointInDepthRange(object.point)) {
            candidates.add(object.point);
          }
        case Object3DType.line:
          candidates.addAll([object.pointA, object.pointB]);
          final endpoints = clipLineToView(object, camera, projection);
          if (endpoints.length == 2)
            addSegmentCandidate(endpoints[0], endpoints[1]);
        case Object3DType.surface:
        case Object3DType.polyhedron:
          candidates.addAll(object.vertices);
          for (var i = 0; i + 2 < object.indices.length; i += 3) {
            final a = object.indices[i];
            final b = object.indices[i + 1];
            final c = object.indices[i + 2];
            if (a < 0 ||
                a >= object.vertices.length ||
                b < 0 ||
                b >= object.vertices.length ||
                c < 0 ||
                c >= object.vertices.length) {
              continue;
            }
            addSegmentCandidate(object.vertices[a], object.vertices[b]);
            addSegmentCandidate(object.vertices[b], object.vertices[c]);
            addSegmentCandidate(object.vertices[c], object.vertices[a]);
          }
        case Object3DType.curve:
          candidates.addAll(object.vertices);
          for (var i = 1; i < object.vertices.length; i++) {
            if (!object.curveStarts.contains(i)) {
              addSegmentCandidate(object.vertices[i - 1], object.vertices[i]);
            }
          }
        case Object3DType.sphere:
          candidates.add(object.sphereCenter);
          final centerToRay = object.sphereCenter - ray.origin;
          final alongRay = centerToRay.dot(ray.direction);
          final closest = ray.origin + ray.direction * alongRay;
          final distanceToRay = closest.distanceTo(object.sphereCenter);
          final radius = object.sphereRadius.abs();
          if (distanceToRay <= radius) {
            final offset = dart_math.sqrt(
              dart_math.max(
                0.0,
                radius * radius - distanceToRay * distanceToRay,
              ),
            );
            if (projection.type != ProjectionType.perspective) {
              if (alongRay >= 0) {
                surfaceCandidates.add(
                  ray.pointAt(dart_math.max(0.0, alongRay - offset)),
                );
              }
              break;
            }
            for (final hitDistance in [alongRay - offset, alongRay + offset]) {
              if (hitDistance < 0) continue;
              final hit = ray.pointAt(hitDistance);
              final depth = worldToScreen(hit, camera, projection).z;
              if (projection.type == ProjectionType.perspective &&
                  (depth < projection.near || depth > projection.far)) {
                continue;
              }
              surfaceCandidates.add(hit);
              break;
            }
          }
        case Object3DType.vector:
          candidates.addAll([object.point, object.point + object.vector]);
          addSegmentCandidate(object.point, object.point + object.vector);
        case Object3DType.plane:
          final equation = _normalizedPlaneEquation(object);
          if (equation == null) break;
          final hit = _intersectWorkingPlane(
            ray,
            point: equation.origin,
            normal: equation.normal,
          );
          if (hit != null && _withinRenderedPlaneGrid(object, hit)) {
            surfaceCandidates.add(hit);
          }
      }
    }

    Point3D? nearestIn(List<Point3D> points) {
      Point3D? nearest;
      var nearestDistance = 14.0;
      for (final candidate in points) {
        final screen = worldToScreen(candidate, camera, projection);
        final nearTolerance = segmentCandidates.contains(candidate)
            ? 1e-9 * dart_math.max(1.0, projection.near.abs())
            : 0.0;
        final farTolerance = segmentCandidates.contains(candidate)
            ? 1e-9 * dart_math.max(1.0, projection.far.abs())
            : 0.0;
        if (projection.type == ProjectionType.perspective &&
            (!screen.z.isFinite ||
                screen.z < projection.near - nearTolerance ||
                screen.z > projection.far + farTolerance)) {
          continue;
        }
        final dx = screen.x - screenX;
        final dy = screen.y - screenY;
        final pixelDistance = dart_math.sqrt(dx * dx + dy * dy);
        if (pixelDistance < nearestDistance) {
          nearestDistance = pixelDistance;
          nearest = candidate;
        }
      }
      return nearest;
    }

    return nearestIn(candidates) ?? nearestIn(surfaceCandidates);
  }

  Point3D _screenToConstructionPlane(
    double screenX,
    double screenY, {
    required bool snap,
    Vector3D? normalOverride,
  }) {
    if (snap && _currentTool != ConstructionTool.point) {
      final snapped = _nearestSnappedPoint(screenX, screenY);
      if (snapped != null) return snapped;
    }

    final ray = _screenRay(screenX, screenY);
    final points = _construction?.points ?? const <Point3D>[];
    final normal =
        normalOverride ??
        (points.isEmpty ? Vector3D.unitZ : _constructionPlaneNormal);
    final planePoint = points.isEmpty ? Point3D.origin : points.last;
    final hit = _intersectWorkingPlane(ray, point: planePoint, normal: normal);
    if (hit != null) return hit;

    final ground = _intersectWorkingPlane(
      ray,
      point: Point3D.origin,
      normal: Vector3D.unitZ,
    );
    if (ground != null) return ground;

    // In a front or side view the camera ray is parallel to xOy. Choose the
    // visible vertical coordinate plane so a click still carries both a
    // horizontal and a vertical coordinate instead of collapsing to target.
    final verticalNormal = ray.direction.x.abs() > ray.direction.y.abs()
        ? Vector3D.unitX
        : Vector3D.unitY;
    final verticalPlane = _intersectWorkingPlane(
      ray,
      point: _cameraTarget,
      normal: verticalNormal,
    );
    final fallback = verticalPlane ?? _cameraTarget;
    return _currentTool == ConstructionTool.point
        ? Point3D(fallback.x, fallback.y, 0)
        : fallback;
  }

  Point3D _constructionPointForDrag(Offset focalPoint) {
    final points = _construction?.points ?? const <Point3D>[];
    if (points.isNotEmpty) {
      final snapped = _nearestSnappedPoint(focalPoint.dx, focalPoint.dy);
      if (snapped != null) return snapped;
      final point = _screenToConstructionPlane(
        focalPoint.dx,
        focalPoint.dy,
        snap: true,
        normalOverride: _constPlaneNormal,
      );
      return _snapToConstructionGeometry(point);
    }

    final pixelsPerWorldUnit =
        _canvasHeight / (_cameraDistance * _orthographicDistanceScale * 2);
    _constHeight =
        -((focalPoint.dy - (_constStartPoint?.dy ?? focalPoint.dy)) /
            pixelsPerWorldUnit);
    final base = _constGroundPos ?? Point3D.origin;
    return Point3D(base.x, base.y, base.z + _constHeight);
  }

  Point3D _snapToConstructionGeometry(Point3D point) {
    double snap(double value) {
      final step = value.abs() < 5 ? 0.5 : 1.0;
      final rounded = (value / step).round() * step;
      return (value - rounded).abs() < 0.08 ? rounded : value;
    }

    final points = _construction?.points ?? const <Point3D>[];
    final normal = _constPlaneNormal;
    if (points.isNotEmpty && normal != null && normal.magnitude > 1e-9) {
      final view = camera.viewMatrix();
      final right = Vector3D(view[0], view[4], view[8]).normalized();
      final up = right.cross(normal).normalized();
      final anchor = points.last;
      final relative = point - anchor;
      final snappedU = snap(relative.dot(right));
      final snappedV = snap(relative.dot(up));
      return anchor + right * snappedU + up * snappedV;
    }

    return Point3D(snap(point.x), snap(point.y), snap(point.z));
  }

  void _updateConstructionPreview(Point3D? point) {
    if (point == null || _construction == null) return;
    setState(() {
      _construction!.updatePreviewPoint(
        point,
        workingPlaneNormal: _constPlaneNormal,
      );
      _constructionPreview = _construction?.previewObject;
      _objectsVersion++;
    });
  }

  /// Handle a placed 3D point during construction.
  /// Advances the construction state and creates the object when ready.
  bool _isConstructionClosureClick() {
    const closureTools = {
      ConstructionTool.polygon,
      ConstructionTool.locus,
      ConstructionTool.polyline,
      ConstructionTool.area,
    };
    final construction = _construction;
    final position = _lastFocalPoint ?? _constStartPoint;
    if (construction == null ||
        !closureTools.contains(_currentTool) ||
        construction.points.length < 3 ||
        position == null) {
      return false;
    }
    final first = worldToScreen(
      construction.points.first,
      camera,
      _currentProjection(),
    );
    if (!first.x.isFinite || !first.y.isFinite) return false;
    const closureRadius = 14.0;
    final dx = first.x - position.dx;
    final dy = first.y - position.dy;
    return dx * dx + dy * dy <= closureRadius * closureRadius;
  }

  void _handleConstructionPoint(Point3D worldPt) {
    if (_currentTool == ConstructionTool.text) {
      _showTextInput(worldPt);
      _constPointPlaced = false;
      return;
    }
    int? pointOnObjectTargetIndex;
    if (_currentTool == ConstructionTool.pointOnObject) {
      final selectionPosition = _constStartPoint;
      final targetIndex = selectionPosition == null
          ? null
          : _hitObjectIndex(selectionPosition);
      if (targetIndex == null) {
        widget.onToolInstruction?.call('请点击现有对象上的位置');
        return;
      }
      pointOnObjectTargetIndex = targetIndex;
      final target = _objects[targetIndex];
      final placementPosition = _lastFocalPoint ?? selectionPosition;
      if (placementPosition != null) {
        worldPt = _pointOnObjectAtScreen(target, placementPosition, worldPt);
      } else {
        worldPt = _constrainPointToObject(worldPt, target);
      }
    }
    if (_construction == null) return;

    final construction = _construction!;
    final previousPointCount = construction.points.length;
    final sourcePointIndex = _sourcePointIndexAt(worldPt);
    final closeToFirstPoint = _isConstructionClosureClick();
    final action = construction.addPoint(
      worldPt,
      workingPlaneNormal: _constPlaneNormal,
      closeToFirstPoint: closeToFirstPoint,
    );
    if (construction.points.length > previousPointCount) {
      _constructionPointSources.add(sourcePointIndex);
    }
    switch (action) {
      case ConstructionAction.complete:
        final result = construction.result;
        if (result != null) {
          final name = ToolInfo.all[_currentTool]!.name;
          var number = 1;
          while (_objects.any((object) => object.label == '$name$number')) {
            number++;
          }
          final keepMeasurement = const {
            ConstructionTool.angle,
            ConstructionTool.distance,
            ConstructionTool.area,
          }.contains(_currentTool);
          final obj = result.copyWith(
            label: keepMeasurement ? result.label : '$name$number',
            documentId: _newDocumentObjectId(
              _objects.map((object) => object.documentId).toSet(),
            ),
          );
          if (widget.onObjectCreated != null) {
            _completingConstruction = true;
            try {
              widget.onObjectCreated!(obj);
            } finally {
              _completingConstruction = false;
            }
          } else {
            setState(() {
              _objects.add(obj);
              _objectsVersion++;
            });
          }
          final objectIndex = _objects.indexOf(obj);
          if (objectIndex >= 0 &&
              _constructionPointSources.any((index) => index != null)) {
            _constructionDependencies[objectIndex] = _SolidSourceDependency(
              tool: _currentTool,
              points: construction.points,
              sourcePointIndices: _constructionPointSources,
              workingPlaneNormal: _constPlaneNormal ?? Vector3D.unitZ,
              polygonSides: widget.polygonSides,
            );
          }
          if (_currentTool == ConstructionTool.point ||
              _currentTool == ConstructionTool.pointOnObject) {
            final index = _objects.indexOf(obj);
            if (index >= 0) {
              setState(() {
                _selectedPointIndex = index;
                _pointDragMode = PointDragMode.height;
                if (pointOnObjectTargetIndex != null) {
                  _pointAttachments[index] = pointOnObjectTargetIndex;
                }
              });
              widget.onSelectionChanged?.call(obj);
            }
          }
          widget.onSceneChanged?.call();
        }
        _construction = ConstructionState(
          tool: _currentTool,
          polygonSides: widget.polygonSides,
        );
        _constructionPointSources.clear();
        break;
      case ConstructionAction.advanceStep:
        // Continue to next step
        break;
      case ConstructionAction.awaitInput:
        // Wait for more input
        break;
      case ConstructionAction.reset:
        _construction = ConstructionState(
          tool: _currentTool,
          polygonSides: widget.polygonSides,
        );
        _constructionPointSources.clear();
        break;
    }
    widget.onToolInstruction?.call(_construction?.currentInstruction ?? '');

    // Reset the placement guard so the next gesture can place a point
    // (needed for tap-based construction where _onScaleStart won't fire again)
    _constPointPlaced = false;

    // Update preview objects
    _objectsVersion++;
    _constructionPreview = _construction?.previewObject;
  }

  Future<void> _showTextInput(Point3D point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _dialog(
        dialogContext,
        AlertDialog(
          title: Text(_label('添加文本')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: _label('输入要显示的内容')),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_label('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(_label('添加')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    _appendCreatedObject(
      Object3D.text(point, text: text.trim(), color: 0xFF1565C0),
    );
  }

  // ==================================================================
  // Build
  // ==================================================================

  void _handleViewAction(_ViewAction action) {
    switch (action) {
      case _ViewAction.toggleAxes:
        toggleAxes();
      case _ViewAction.togglePlane:
        togglePlane();
      case _ViewAction.toggleGrid:
        toggleGrid();
      case _ViewAction.parallelProjection:
        setProjectionType(ProjectionType.parallel);
      case _ViewAction.perspectiveProjection:
        setProjectionType(ProjectionType.perspective);
      case _ViewAction.standardView:
        resetView();
      case _ViewAction.topView:
        _setView(theta: _defaultTheta, phi: dart_math.pi * 0.49);
      case _ViewAction.frontView:
        _setView(theta: dart_math.pi, phi: 0);
      case _ViewAction.sideView:
        _setView(theta: dart_math.pi / 2, phi: 0);
    }
  }

  Widget _floatingControl({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, size: 21),
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size(40, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_ViewAction> _menuToggle({
    required _ViewAction value,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(_label(label))),
          if (selected) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }

  List<PopupMenuEntry<_ViewAction>> _viewMenuItems() => [
    _menuToggle(
      value: _ViewAction.toggleAxes,
      icon: Icons.straighten,
      label: _label('坐标轴'),
      selected: _showAxes,
    ),
    _menuToggle(
      value: _ViewAction.togglePlane,
      icon: Icons.crop_square,
      label: _label('xOy 平面'),
      selected: _showPlane,
    ),
    _menuToggle(
      value: _ViewAction.toggleGrid,
      icon: Icons.grid_on,
      label: _label('网格'),
      selected: _showGrid,
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: _ViewAction.parallelProjection,
      child: Row(
        children: [
          const Icon(Icons.view_in_ar, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(_label('平行投影'))),
          if (_projectionType == ProjectionType.parallel)
            const Icon(Icons.check, size: 18),
        ],
      ),
    ),
    PopupMenuItem(
      value: _ViewAction.perspectiveProjection,
      child: Row(
        children: [
          const Icon(Icons.vrpano, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(_label('透视投影'))),
          if (_projectionType == ProjectionType.perspective)
            const Icon(Icons.check, size: 18),
        ],
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: _ViewAction.standardView,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.home_outlined, size: 20),
        title: Text(_label('标准视图')),
      ),
    ),
    PopupMenuItem(
      value: _ViewAction.topView,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.vertical_align_bottom, size: 20),
        title: Text(_label('俯视 xOy')),
      ),
    ),
    PopupMenuItem(
      value: _ViewAction.frontView,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.crop_landscape, size: 20),
        title: Text(_label('正视 xOz')),
      ),
    ),
    PopupMenuItem(
      value: _ViewAction.sideView,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.crop_portrait, size: 20),
        title: Text(_label('侧视 yOz')),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        _canvasHeight = constraints.maxHeight;

        final supportedDevices =
            widget.allowTouchGestures && widget.allowMouseGestures
            ? null
            : <PointerDeviceKind>{
                if (widget.allowTouchGestures) PointerDeviceKind.touch,
                if (widget.allowTouchGestures) PointerDeviceKind.stylus,
                if (widget.allowTouchGestures) PointerDeviceKind.invertedStylus,
                if (widget.allowMouseGestures) PointerDeviceKind.mouse,
                if (widget.allowMouseGestures) PointerDeviceKind.trackpad,
              };
        return Focus(
          focusNode: _focusNode,
          child: MouseRegion(
            cursor: _currentTool == ConstructionTool.move
                ? SystemMouseCursors.grab
                : SystemMouseCursors.precise,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                    onPointerSignal: _onPointerSignal,
                    onPointerPanZoomStart: _onPointerPanZoomStart,
                    onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
                    onPointerPanZoomEnd: _onPointerPanZoomEnd,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      supportedDevices: supportedDevices,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      child: CustomPaint(
                        painter: MathCanvas3DPainter(
                          cameraDistance: _cameraDistance,
                          cameraTheta: _cameraTheta,
                          cameraPhi: _cameraPhi,
                          cameraTarget: _cameraTarget,
                          projectionType: _projectionType,
                          showAxes: _showAxes,
                          showPlane: _showPlane,
                          showGrid: _showGrid,
                          showLabels: _showLabels,
                          objects: _objects,
                          selectedPoint: selectedPoint,
                          pointDragMode: _pointDragMode,
                          constructionPreview: _constructionPreview,
                          objectsVersion: _objectsVersion,
                          canvasWidth: _canvasWidth,
                          canvasHeight: _canvasHeight,
                          backgroundColor: cs.surface,
                          axisColor: cs.onSurface,
                          gridColor: cs.outlineVariant.withValues(alpha: 0.45),
                          labelColor: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  if (selectedPoint != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 60,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: TextButton.icon(
                          key: const ValueKey('point-drag-mode'),
                          style: TextButton.styleFrom(
                            backgroundColor: cs.surfaceContainerHigh,
                            foregroundColor: cs.onSurface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                MathUiTokens.cornerRadius,
                              ),
                            ),
                          ),
                          icon: Icon(
                            _pointDragMode == PointDragMode.height
                                ? Icons.height
                                : Icons.open_with,
                            size: 20,
                          ),
                          onPressed: () => setState(() {
                            _pointDragMode =
                                _pointDragMode == PointDragMode.plane
                                ? PointDragMode.height
                                : PointDragMode.plane;
                          }),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${selectedPoint!.label ?? _label('点')} · ${_label(_pointDragMode == PointDragMode.height ? '高度移动' : '平面移动')} · ${_label('点击切换')}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'x ${selectedPoint!.point.x.toStringAsFixed(2)}  y ${selectedPoint!.point.y.toStringAsFixed(2)}  z ${selectedPoint!.point.z.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_currentTool == ConstructionTool.move &&
                      selectedObject != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 60,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: _SolidStyleControls(
                            key: const ValueKey('solid-style-controls'),
                            object: selectedObject!,
                            labelResolver: widget.labelResolver,
                            dialogBuilder: widget.dialogBuilder,
                            onColorChanged: (color) =>
                                updateSelectedObjectStyle(color: color),
                            onEdgeWidthChanged: (width) =>
                                updateSelectedObjectStyle(edgeWidth: width),
                            onShowEdgesChanged: (showEdges) =>
                                updateSelectedObjectStyle(showEdges: showEdges),
                            onDelete: deleteSelectedObject,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: cs.surface,
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: PopupMenuButton<_ViewAction>(
                        tooltip: _label('3D 视图设置'),
                        icon: const Icon(Icons.settings, size: 21),
                        onSelected: _handleViewAction,
                        itemBuilder: (_) => _viewMenuItems(),
                        style: IconButton.styleFrom(
                          fixedSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Column(
                      children: [
                        _floatingControl(
                          icon: Icons.filter_center_focus,
                          tooltip: _label('缩放至适合'),
                          onPressed: fitToView,
                        ),
                        _floatingControl(
                          icon: Icons.zoom_in,
                          tooltip: _label('放大'),
                          onPressed: zoomIn,
                        ),
                        _floatingControl(
                          icon: Icons.zoom_out,
                          tooltip: _label('缩小'),
                          onPressed: zoomOut,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ======================================================================
// MathCanvas3DPainter
// ======================================================================

class _SolidStyleControls extends StatefulWidget {
  final Object3D object;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<double> onEdgeWidthChanged;
  final ValueChanged<bool> onShowEdgesChanged;
  final VoidCallback onDelete;
  final String Function(String sourceText)? labelResolver;
  final Widget Function(BuildContext context, Widget dialog)? dialogBuilder;

  const _SolidStyleControls({
    super.key,
    required this.object,
    required this.onColorChanged,
    required this.onEdgeWidthChanged,
    required this.onShowEdgesChanged,
    required this.onDelete,
    this.labelResolver,
    this.dialogBuilder,
  });

  @override
  State<_SolidStyleControls> createState() => _SolidStyleControlsState();
}

class _SolidStyleControlsState extends State<_SolidStyleControls> {
  late final TextEditingController _edgeWidthController;

  bool get _hasEdges => widget.object.type == Object3DType.polyhedron;

  String _label(String source) => widget.labelResolver?.call(source) ?? source;

  Widget _dialog(BuildContext context, Widget child) =>
      widget.dialogBuilder?.call(context, child) ?? child;

  @override
  void initState() {
    super.initState();
    _edgeWidthController = TextEditingController(
      text: _formatEdgeWidth(widget.object.edgeWidth),
    );
  }

  @override
  void didUpdateWidget(_SolidStyleControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.edgeWidth != widget.object.edgeWidth) {
      _edgeWidthController.text = _formatEdgeWidth(widget.object.edgeWidth);
    }
  }

  @override
  void dispose() {
    _edgeWidthController.dispose();
    super.dispose();
  }

  String _formatEdgeWidth(double width) =>
      width.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  void _commitEdgeWidth(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      _edgeWidthController.text = _formatEdgeWidth(widget.object.edgeWidth);
      return;
    }
    final width = parsed.clamp(0.0, maxSolidEdgeWidth).toDouble();
    _edgeWidthController.text = _formatEdgeWidth(width);
    widget.onEdgeWidthChanged(width);
  }

  void _showColorPicker() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _dialog(
        dialogContext,
        AlertDialog(
          title: Text(_label('选择颜色')),
          content: Wrap(
            spacing: MathUiTokens.canvasInset,
            runSpacing: MathUiTokens.canvasInset,
            children: [
              for (var index = 0; index < formulaPalette.length; index++)
                Builder(
                  builder: (context) {
                    final color = formulaPalette[index];
                    final selected = widget.object.color == color.toARGB32();
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: _label('物体颜色 ${index + 1}'),
                      child: SizedBox.square(
                        dimension: MathUiTokens.swatchTapTarget,
                        child: InkWell(
                          key: ValueKey('solid-color-$index'),
                          customBorder: const CircleBorder(),
                          onTap: () {
                            widget.onColorChanged(color.toARGB32());
                            Navigator.pop(dialogContext);
                          },
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 3,
                                      )
                                    : null,
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check,
                                      color: color.computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_label('取消')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.object.label ?? _label('立体图形'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('solid-delete'),
                  tooltip: _label('删除对象'),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDelete,
                  icon: Icon(Icons.delete_outline, color: cs.error),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('solid-fill-color'),
                  tooltip: _label('选择填充颜色'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _showColorPicker,
                  icon: Icon(
                    Icons.palette_outlined,
                    color: Color(widget.object.color),
                  ),
                ),
                Text(_label('填充色')),
                if (_hasEdges) ...[
                  const Spacer(),
                  SizedBox(
                    width: 86,
                    height: 50,
                    child: TextField(
                      key: const ValueKey('solid-edge-width'),
                      controller: _edgeWidthController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                      ],
                      textAlign: TextAlign.center,
                      onSubmitted: _commitEdgeWidth,
                      onTapOutside: (_) =>
                          _commitEdgeWidth(_edgeWidthController.text),
                      decoration: InputDecoration(
                        labelText: _label('棱宽 (0–6)'),
                        suffixText: 'px',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_hasEdges)
              Row(
                children: [
                  Checkbox(
                    key: const ValueKey('solid-show-edges'),
                    value: widget.object.showEdges,
                    onChanged: (value) {
                      if (value != null) widget.onShowEdgesChanged(value);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(_label('显示棱')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter that renders a 3D scene onto a 2D Canvas.
///
/// Uses painter's algorithm (back-to-front sorting) for correct occlusion.
class MathCanvas3DPainter extends CustomPainter {
  final double cameraDistance;
  final double cameraTheta;
  final double cameraPhi;
  final Point3D cameraTarget;
  final ProjectionType projectionType;
  final bool showAxes;
  final bool showPlane;
  final bool showGrid;
  final bool showLabels;
  final List<Object3D> objects;
  final Object3D? constructionPreview;
  final Object3D? selectedPoint;
  final PointDragMode pointDragMode;
  final int objectsVersion;
  final double canvasWidth;
  final double canvasHeight;
  final Color backgroundColor;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;

  const MathCanvas3DPainter({
    this.cameraDistance = 10,
    this.cameraTheta = dart_math.pi * 0.75,
    this.cameraPhi = dart_math.pi / 6,
    this.cameraTarget = Point3D.origin,
    this.projectionType = ProjectionType.parallel,
    this.showAxes = true,
    this.showPlane = true,
    this.showGrid = false,
    this.showLabels = true,
    this.objects = const [],
    this.constructionPreview,
    this.selectedPoint,
    this.pointDragMode = PointDragMode.plane,
    this.objectsVersion = 0,
    this.canvasWidth = 800,
    this.canvasHeight = 600,
    this.backgroundColor = Colors.white,
    this.axisColor = Colors.black87,
    this.gridColor = const Color(0x4DCCCCCC),
    this.labelColor = Colors.grey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    // Build camera and projection
    final camera = Camera3D(
      target: cameraTarget,
      distance: cameraDistance,
      theta: cameraTheta,
      phi: cameraPhi,
    );
    final projection = projectionType == ProjectionType.parallel
        ? Projection3D.parallel(
            width: size.width,
            height: size.height,
            scale: _computeScale(),
          )
        : Projection3D.perspective(
            width: size.width,
            height: size.height,
            fov: 60,
            far: _perspectiveFarPlane(
              objects,
              cameraTarget,
              cameraDistance,
              preview: constructionPreview,
            ),
          );

    if (showPlane) {
      _drawCoordinatePlane(canvas, camera, projection);
    }

    // Draw grid on the xOy-plane.
    if (showGrid) {
      _drawGrid(canvas, size, camera, projection);
    }

    // Draw axes
    if (showAxes) {
      _drawAxes(canvas, size, camera, projection);
    }

    // Draw objects (sorted back-to-front)
    _drawObjects(canvas, size, camera, projection);
    final point = selectedPoint?.point;
    if (point != null) {
      final screen = worldToScreen(point, camera, projection);
      if (projection.type == ProjectionType.perspective &&
          (screen.z <= 0 ||
              screen.z < projection.near ||
              screen.z > projection.far)) {
        return;
      }
      final center = Offset(screen.x, screen.y);
      final guide = Paint()
        ..color = const Color(0xFF7C4DFF)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 10, guide);
      final ground = worldToScreen(
        Point3D(point.x, point.y, 0),
        camera,
        projection,
      );
      canvas.drawLine(
        center,
        Offset(ground.x, ground.y),
        guide..color = const Color(0x807C4DFF),
      );
      guide.color = const Color(0xFF7C4DFF);
      final axisStep = projection.type == ProjectionType.perspective
          ? dart_math.min(1.0, screen.z.abs() * 0.5).toDouble()
          : 1.0;
      Offset projectedAxis(Vector3D axis) {
        final axisEnd = worldToScreen(
          point + axis * axisStep,
          camera,
          projection,
        );
        final projected = Offset(axisEnd.x - center.dx, axisEnd.y - center.dy);
        final length = projected.distance;
        if (length < 1e-8 || !length.isFinite) return Offset.zero;
        return projected * (28 / length);
      }

      final List<Offset> directions;
      if (pointDragMode == PointDragMode.height) {
        directions = [const Offset(0, 28), const Offset(0, -28)];
      } else {
        final xAxis = projectedAxis(Vector3D.unitX);
        final yAxis = projectedAxis(Vector3D.unitY);
        directions = [xAxis, -xAxis, yAxis, -yAxis];
      }
      for (final direction in directions) {
        canvas.drawLine(center + direction * 0.5, center + direction, guide);
        _drawArrowHead(
          canvas,
          center,
          center + direction,
          Paint()..color = guide.color,
        );
      }
    }
  }

  /// Compute a reasonable scale based on camera distance.
  double _computeScale() {
    return cameraDistance.clamp(0.25, double.maxFinite) *
        MathCanvas3DState._orthographicDistanceScale;
  }

  // ==================================================================
  // Background
  // ==================================================================

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  // ==================================================================
  // Grid
  // ==================================================================

  void _drawCoordinatePlane(
    Canvas canvas,
    Camera3D camera,
    Projection3D projection,
  ) {
    final extent = dart_math.max(6.0, camera.distance * 1.2);
    final center = camera.target;
    final corners = [
      Point3D(center.x - extent, center.y - extent, 0),
      Point3D(center.x + extent, center.y - extent, 0),
      Point3D(center.x + extent, center.y + extent, 0),
      Point3D(center.x - extent, center.y + extent, 0),
    ].map((point) => worldToScreen(point, camera, projection)).toList();
    final path = Path()
      ..moveTo(corners[0].x, corners[0].y)
      ..lineTo(corners[1].x, corners[1].y)
      ..lineTo(corners[2].x, corners[2].y)
      ..lineTo(corners[3].x, corners[3].y)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = axisColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    Camera3D camera,
    Projection3D projection,
  ) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // Keep the grid around the view target so panning does not reveal a blank
    // canvas. Increase spacing at larger scales to bound painting work.
    final gridRange = dart_math.max(
      10.0,
      dart_math.min(camera.distance, double.maxFinite / 4) * 1.5,
    );
    final gridCenter = camera.target;
    const maxHalfLines = 50;
    final step = dart_math.max(1.0, gridRange / maxHalfLines);
    final lines = <List<Offset>>[];
    final startX = gridCenter.x - gridRange;
    final startY = gridCenter.y - gridRange;
    final remainderX = startX.remainder(step);
    final remainderY = startY.remainder(step);
    final anchorX = startX - remainderX + (remainderX > 0 ? step : 0);
    final anchorY = startY - remainderY + (remainderY > 0 ? step : 0);

    // Lines along X (constant Y).
    for (var i = 0; i <= 2 * maxHalfLines; i++) {
      final y = anchorY + i * step;
      if (y > gridCenter.y + gridRange) break;
      final p1 = worldToScreen(
        Point3D(gridCenter.x - gridRange, y, 0),
        camera,
        projection,
      );
      final p2 = worldToScreen(
        Point3D(gridCenter.x + gridRange, y, 0),
        camera,
        projection,
      );
      lines.add([Offset(p1.x, p1.y), Offset(p2.x, p2.y)]);
    }

    // Lines along Y (constant X).
    for (var i = 0; i <= 2 * maxHalfLines; i++) {
      final x = anchorX + i * step;
      if (x > gridCenter.x + gridRange) break;
      final p1 = worldToScreen(
        Point3D(x, gridCenter.y - gridRange, 0),
        camera,
        projection,
      );
      final p2 = worldToScreen(
        Point3D(x, gridCenter.y + gridRange, 0),
        camera,
        projection,
      );
      lines.add([Offset(p1.x, p1.y), Offset(p2.x, p2.y)]);
    }

    for (final line in lines) {
      canvas.drawLine(line[0], line[1], paint);
    }
  }

  // ==================================================================
  // Axes
  // ==================================================================

  void _drawAxes(
    Canvas canvas,
    Size size,
    Camera3D camera,
    Projection3D projection,
  ) {
    const axisLength = 6.0;
    const origin = Point3D.origin;

    final axes = [
      (
        'x',
        const Point3D(-axisLength, 0, 0),
        const Point3D(axisLength, 0, 0),
        const Color(0xFFE32636),
        const Offset(9, 1),
      ),
      (
        'y',
        const Point3D(0, -axisLength, 0),
        const Point3D(0, axisLength, 0),
        const Color(0xFF18862A),
        const Offset(7, -10),
      ),
      (
        'z',
        const Point3D(0, 0, -axisLength),
        const Point3D(0, 0, axisLength),
        const Color(0xFF1649E8),
        const Offset(7, -4),
      ),
    ];

    for (final (label, start, tip, color, labelOffset) in axes) {
      final startScreen = worldToScreen(start, camera, projection);
      final tipScreen = worldToScreen(tip, camera, projection);
      final startPt = Offset(startScreen.x, startScreen.y);
      final tipPt = Offset(tipScreen.x, tipScreen.y);
      final axisPaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawLine(startPt, tipPt, axisPaint);
      _drawArrowHead(canvas, startPt, tipPt, arrowPaint);

      for (var value = -5; value <= 5; value++) {
        if (value == 0) continue;
        final point = switch (label) {
          'x' => Point3D(value.toDouble(), 0, 0),
          'y' => Point3D(0, value.toDouble(), 0),
          _ => Point3D(0, 0, value.toDouble()),
        };
        final screen = worldToScreen(point, camera, projection);
        final axisDirection = (tipPt - startPt);
        if (axisDirection.distance < 1) continue;
        final normal =
            Offset(-axisDirection.dy, axisDirection.dx) /
            axisDirection.distance;
        final center = Offset(screen.x, screen.y);
        canvas.drawLine(center - normal * 3, center + normal * 3, axisPaint);

        final tickPainter = TextPainter(
          text: TextSpan(
            text: '$value',
            style: TextStyle(color: color, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tickPainter.paint(canvas, center + normal * 5);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, tipPt + labelOffset);
    }

    final originScreen = worldToScreen(origin, camera, projection);
    canvas.drawCircle(
      Offset(originScreen.x, originScreen.y),
      2.5,
      Paint()..color = labelColor,
    );
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final direction = (to - from);
    final length = direction.distance;
    if (length < 1) return;

    final unit = direction / length;
    final perp = Offset(-unit.dy, unit.dx);
    final arrowSize = 8.0;

    final tip = to;
    final base = to - unit * arrowSize;
    final left = base + perp * arrowSize * 0.4;
    final right = base - perp * arrowSize * 0.4;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  // ==================================================================
  // Objects rendering with painter's algorithm
  // ==================================================================

  void _drawObjects(
    Canvas canvas,
    Size size,
    Camera3D camera,
    Projection3D projection,
  ) {
    // Collect all renderables with depth info
    final renderables = <_Renderable>[];

    for (final obj in objects) {
      if (!obj.visible) continue;
      switch (obj.type) {
        case Object3DType.point:
          _collectPoint(renderables, obj, camera, projection);
        case Object3DType.line:
          _collectLine(renderables, obj, camera, projection);
        case Object3DType.plane:
          _collectPlane(renderables, obj, camera, projection);
        case Object3DType.surface:
          _collectSurface(renderables, obj, camera, projection);
        case Object3DType.sphere:
          _collectSphere(renderables, obj, camera, projection);
        case Object3DType.polyhedron:
          _collectPolyhedron(renderables, obj, camera, projection);
        case Object3DType.vector:
          _collectVector(renderables, obj, camera, projection);
        case Object3DType.curve:
          _collectCurve(renderables, obj, camera, projection);
      }
      if (showLabels && obj.label != null && obj.type != Object3DType.point) {
        _collectObjectLabel(renderables, obj, camera, projection);
      }
    }

    final preview = constructionPreview;
    if (preview != null) {
      switch (preview.type) {
        case Object3DType.point:
          _collectPoint(renderables, preview, camera, projection);
        case Object3DType.line:
          _collectLine(renderables, preview, camera, projection);
        case Object3DType.plane:
          _collectPlane(renderables, preview, camera, projection);
        case Object3DType.surface:
          _collectSurface(renderables, preview, camera, projection);
        case Object3DType.sphere:
          _collectSphere(renderables, preview, camera, projection);
        case Object3DType.polyhedron:
          _collectPolyhedron(renderables, preview, camera, projection);
        case Object3DType.vector:
          _collectVector(renderables, preview, camera, projection);
        case Object3DType.curve:
          _collectCurve(renderables, preview, camera, projection);
      }
    }

    // Sort back-to-front (larger z = farther = drawn first)
    renderables.sort((a, b) => b.depth.compareTo(a.depth));

    // Draw in order
    for (final r in renderables) {
      r.draw(canvas);
    }
  }

  void _collectPoint(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final screen = worldToScreen(obj.point, camera, projection);
    if (projection.type == ProjectionType.perspective &&
        (screen.z <= 0 ||
            screen.z < projection.near ||
            screen.z > projection.far)) {
      return;
    }
    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);
    renderables.add(
      _Renderable(
        depth: screen.z,
        draw: (canvas) {
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.fill;
          if (!obj.isTextAnnotation) {
            canvas.drawCircle(
              Offset(screen.x, screen.y),
              _pointMarkerRadius,
              paint,
            );
          }

          if ((showLabels || obj.isTextAnnotation) && obj.label != null) {
            final tp = TextPainter(
              text: TextSpan(
                text: obj.label,
                style: TextStyle(color: color, fontSize: 11),
              ),
              textDirection: TextDirection.ltr,
            );
            tp.layout();
            final labelPosition = obj.isTextAnnotation
                ? Offset(screen.x, screen.y)
                : Offset(screen.x + 6, screen.y - 6);
            tp.paint(canvas, labelPosition);
          }
        },
      ),
    );
  }

  void _collectObjectLabel(
    List<_Renderable> renderables,
    Object3D object,
    Camera3D camera,
    Projection3D projection,
  ) {
    final anchor = switch (object.type) {
      Object3DType.line => _lineLabelAnchor(object, camera, projection),
      Object3DType.plane => _planeLabelAnchor(object, camera, projection),
      Object3DType.sphere => _sphereLabelAnchor(object, camera, projection),
      Object3DType.vector => _lineLabelAnchor(
        Object3D.line(
          object.point,
          object.point + object.vector,
          lineKind: Line3DKind.segment,
        ),
        camera,
        projection,
      ),
      Object3DType.surface => _frontmostTriangleCentroid(
        object,
        camera,
        projection,
      ),
      Object3DType.curve => _curveLabelAnchor(object, camera, projection),
      Object3DType.polyhedron => _frontmostTriangleCentroid(
        object,
        camera,
        projection,
      ),
      Object3DType.point => object.point,
    };
    if (anchor == null) return;
    final screen = worldToScreen(anchor, camera, projection);
    final alpha = ((object.color >> 24) & 0xFF) / 255.0;
    final color = Color(object.color).withValues(alpha: alpha * object.opacity);
    renderables.add(
      _Renderable(
        depth:
            object.type == Object3DType.polyhedron ||
                object.type == Object3DType.surface
            ? screen.z - 1e-6
            : screen.z,
        draw: (canvas) {
          final painter = TextPainter(
            text: TextSpan(
              text: object.label,
              style: TextStyle(color: color, fontSize: 11),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(screen.x + 6, screen.y - 6));
        },
      ),
    );
  }

  Point3D? _frontmostTriangleCentroid(
    Object3D object,
    Camera3D camera,
    Projection3D projection,
  ) {
    Point3D? anchor;
    var nearestDepth = double.infinity;

    bool isVisible(ScreenPoint screen) =>
        screen.x.isFinite &&
        screen.y.isFinite &&
        screen.z.isFinite &&
        screen.x >= 0 &&
        screen.x <= canvasWidth &&
        screen.y >= 0 &&
        screen.y <= canvasHeight &&
        (projection.type != ProjectionType.perspective ||
            (screen.z >= projection.near && screen.z <= projection.far));

    void consider(Point3D point) {
      final screen = worldToScreen(point, camera, projection);
      if (isVisible(screen) && screen.z < nearestDepth) {
        anchor = point;
        nearestDepth = screen.z;
      }
    }

    for (var i = 0; i + 2 < object.indices.length; i += 3) {
      final ia = object.indices[i];
      final ib = object.indices[i + 1];
      final ic = object.indices[i + 2];
      if (ia < 0 ||
          ia >= object.vertices.length ||
          ib < 0 ||
          ib >= object.vertices.length ||
          ic < 0 ||
          ic >= object.vertices.length) {
        continue;
      }
      final a = object.vertices[ia];
      final b = object.vertices[ib];
      final c = object.vertices[ic];
      final center = Point3D(
        (a.x + b.x + c.x) / 3,
        (a.y + b.y + c.y) / 3,
        (a.z + b.z + c.z) / 3,
      );
      consider(center);
    }

    if (anchor != null) return anchor;

    // If a projected face covers the viewport center, anchor its label there
    // even when the triangle itself is larger than the viewport.
    final viewportCenterRay = Ray3D(
      camera.position,
      (camera.target - camera.position).normalized(),
    );
    for (var i = 0; i + 2 < object.indices.length; i += 3) {
      final ia = object.indices[i];
      final ib = object.indices[i + 1];
      final ic = object.indices[i + 2];
      if (ia < 0 ||
          ia >= object.vertices.length ||
          ib < 0 ||
          ib >= object.vertices.length ||
          ic < 0 ||
          ic >= object.vertices.length) {
        continue;
      }
      final a = object.vertices[ia];
      final b = object.vertices[ib];
      final c = object.vertices[ic];
      final normal = _normalizedTriangleNormal(a, b, c);
      if (normal != null) {
        final hit = intersectRayPlane(
          viewportCenterRay,
          point: a,
          normal: normal,
          allowBehind: projection.type == ProjectionType.parallel,
        );
        if (hit != null && _pointInTriangle3D(hit, a, b, c)) consider(hit);
      }
      for (final edge in [(a, b), (b, c), (c, a)]) {
        final clipped = clipLineToView(
          Object3D.line(edge.$1, edge.$2),
          camera,
          projection,
        );
        for (final point in clipped) {
          consider(point);
        }
      }
    }
    return anchor;
  }

  Point3D? _planeLabelAnchor(
    Object3D plane,
    Camera3D camera,
    Projection3D projection,
  ) {
    final equation = _normalizedPlaneEquation(plane);
    if (equation == null) return null;
    final a = equation.normal.x;
    final b = equation.normal.y;
    final c = equation.normal.z;
    final d = equation.d;
    var nearest = double.infinity;
    Point3D? anchor;
    final viewportCenter = Offset(canvasWidth / 2, canvasHeight / 2);

    void considerSegment(Point3D start, Point3D end) {
      final clipped = clipLineToView(
        Object3D.line(start, end),
        camera,
        projection,
      );
      if (clipped.length != 2) return;
      final candidate = clipped[0].midpoint(clipped[1]);
      final screen = worldToScreen(candidate, camera, projection);
      if (!screen.x.isFinite || !screen.y.isFinite || !screen.z.isFinite) {
        return;
      }
      if (projection.type == ProjectionType.perspective &&
          (screen.z < projection.near || screen.z > projection.far)) {
        return;
      }
      final distance =
          (Offset(screen.x, screen.y) - viewportCenter).distanceSquared;
      if (distance < nearest) {
        nearest = distance;
        anchor = candidate;
      }
    }

    for (var fixed = -_planeGridRange; fixed <= _planeGridRange; fixed += 1.0) {
      if (c.abs() >= a.abs() && c.abs() >= b.abs()) {
        considerSegment(
          Point3D(
            -_planeGridRange,
            fixed,
            (d + a * _planeGridRange - b * fixed) / c,
          ),
          Point3D(
            _planeGridRange,
            fixed,
            (d - a * _planeGridRange - b * fixed) / c,
          ),
        );
        considerSegment(
          Point3D(
            fixed,
            -_planeGridRange,
            (d - a * fixed + b * _planeGridRange) / c,
          ),
          Point3D(
            fixed,
            _planeGridRange,
            (d - a * fixed - b * _planeGridRange) / c,
          ),
        );
      } else if (b.abs() >= a.abs()) {
        considerSegment(
          Point3D(
            -_planeGridRange,
            (d + a * _planeGridRange - c * fixed) / b,
            fixed,
          ),
          Point3D(
            _planeGridRange,
            (d - a * _planeGridRange - c * fixed) / b,
            fixed,
          ),
        );
        considerSegment(
          Point3D(
            fixed,
            (d - a * fixed + c * _planeGridRange) / b,
            -_planeGridRange,
          ),
          Point3D(
            fixed,
            (d - a * fixed - c * _planeGridRange) / b,
            _planeGridRange,
          ),
        );
      } else {
        considerSegment(
          Point3D(
            (d + b * _planeGridRange - c * fixed) / a,
            -_planeGridRange,
            fixed,
          ),
          Point3D(
            (d - b * _planeGridRange - c * fixed) / a,
            _planeGridRange,
            fixed,
          ),
        );
        considerSegment(
          Point3D(
            (d - b * fixed + c * _planeGridRange) / a,
            fixed,
            -_planeGridRange,
          ),
          Point3D(
            (d - b * fixed - c * _planeGridRange) / a,
            fixed,
            _planeGridRange,
          ),
        );
      }
    }
    return anchor;
  }

  Point3D? _lineLabelAnchor(
    Object3D line,
    Camera3D camera,
    Projection3D projection,
  ) {
    final endpoints = clipLineToView(line, camera, projection);
    if (endpoints.length != 2) return null;
    return endpoints[0].midpoint(endpoints[1]);
  }

  Point3D? _sphereLabelAnchor(
    Object3D sphere,
    Camera3D camera,
    Projection3D projection,
  ) {
    const segments = 16;
    final center = sphere.sphereCenter;
    final radius = sphere.sphereRadius;
    final viewportCenter = Offset(canvasWidth / 2, canvasHeight / 2);
    var nearest = double.infinity;
    Point3D? anchor;
    Point3D spherePoint(double theta, double phi) => Point3D(
      center.x + radius * dart_math.cos(phi) * dart_math.cos(theta),
      center.y + radius * dart_math.sin(phi),
      center.z + radius * dart_math.cos(phi) * dart_math.sin(theta),
    );

    void considerPath(List<Point3D> points) {
      for (var i = 1; i < points.length; i++) {
        final clipped = clipLineToView(
          Object3D.line(points[i - 1], points[i], lineKind: Line3DKind.segment),
          camera,
          projection,
        );
        if (clipped.length != 2) continue;
        final candidate = clipped[0].midpoint(clipped[1]);
        final screen = worldToScreen(candidate, camera, projection);
        if (!screen.x.isFinite || !screen.y.isFinite || !screen.z.isFinite) {
          continue;
        }
        final distance =
            (Offset(screen.x, screen.y) - viewportCenter).distanceSquared;
        if (distance < nearest) {
          nearest = distance;
          anchor = candidate;
        }
      }
    }

    for (var i = 0; i < segments; i++) {
      final theta = i * 2 * dart_math.pi / segments;
      considerPath([
        for (var j = 0; j <= segments; j++)
          spherePoint(theta, -dart_math.pi / 2 + j * dart_math.pi / segments),
      ]);
    }

    for (var j = 1; j < segments; j++) {
      final phi = -dart_math.pi / 2 + j * dart_math.pi / segments;
      considerPath([
        for (var i = 0; i <= segments; i++)
          spherePoint(i * 2 * dart_math.pi / segments, phi),
      ]);
    }
    return anchor;
  }

  Point3D? _curveLabelAnchor(
    Object3D curve,
    Camera3D camera,
    Projection3D projection,
  ) {
    Point3D? nearest;
    var nearestCenterDistance = double.infinity;
    final viewportCenter = Offset(canvasWidth / 2, canvasHeight / 2);
    for (var i = 1; i < curve.vertices.length; i++) {
      if (curve.curveStarts.contains(i)) continue;
      final clipped = clipLineToView(
        Object3D.line(curve.vertices[i - 1], curve.vertices[i]),
        camera,
        projection,
      );
      if (clipped.length != 2) continue;
      final anchor = clipped[0].midpoint(clipped[1]);
      final screen = worldToScreen(anchor, camera, projection);
      if (!screen.x.isFinite || !screen.y.isFinite || !screen.z.isFinite) {
        continue;
      }
      if (projection.type == ProjectionType.perspective &&
          (screen.z < projection.near || screen.z > projection.far)) {
        continue;
      }
      if (screen.x < 0 ||
          screen.x > canvasWidth ||
          screen.y < 0 ||
          screen.y > canvasHeight) {
        continue;
      }
      final centerDistance =
          (Offset(screen.x, screen.y) - viewportCenter).distanceSquared;
      if (centerDistance < nearestCenterDistance) {
        nearest = anchor;
        nearestCenterDistance = centerDistance;
      }
    }
    return nearest;
  }

  void _collectLine(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final endpoints = clipLineToView(obj, camera, projection);
    if (endpoints.length != 2) return;
    final a = worldToScreen(endpoints[0], camera, projection);
    final b = worldToScreen(endpoints[1], camera, projection);
    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);
    final avgZ = (a.z + b.z) / 2;

    renderables.add(
      _Renderable(
        depth: avgZ,
        draw: (canvas) {
          final paint = Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;
          canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
        },
      ),
    );
  }

  void _collectPlane(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    // Render a plane as a grid of lines on the plane surface
    final equation = _normalizedPlaneEquation(obj);
    if (equation == null) return;
    final a = equation.normal.x;
    final b = equation.normal.y;
    final c = equation.normal.z;
    final d = equation.d;
    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);

    // Generate grid points on the plane within a range
    // Plane: ax + by + cz = d
    // Solve for the axis with largest coefficient for numeric stability
    const range = _planeGridRange;
    const step = 1.0;
    final lines = <List<Offset>>[];
    var totalZ = 0.0;
    var count = 0;

    void addClippedPath(List<Point3D> points) {
      for (var i = 1; i < points.length; i++) {
        final clipped = clipLineToView(
          Object3D.line(points[i - 1], points[i]),
          camera,
          projection,
        );
        if (clipped.length != 2) continue;
        final start = worldToScreen(clipped[0], camera, projection);
        final end = worldToScreen(clipped[1], camera, projection);
        lines.add([Offset(start.x, start.y), Offset(end.x, end.y)]);
        totalZ += start.z + end.z;
        count += 2;
      }
    }

    if (c.abs() >= a.abs() && c.abs() >= b.abs()) {
      // z = (d - ax - by) / c
      // Lines along X (constant Y)
      for (double y = -range; y <= range; y += step) {
        final pts = <Point3D>[];
        for (double x = -range; x <= range; x += step * 0.5) {
          final z = (d - a * x - b * y) / c;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
      // Lines along Y (constant X)
      for (double x = -range; x <= range; x += step) {
        final pts = <Point3D>[];
        for (double y = -range; y <= range; y += step * 0.5) {
          final z = (d - a * x - b * y) / c;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
    } else if (b.abs() >= a.abs()) {
      // y = (d - ax - cz) / b  — vertical plane, free variable z
      for (double z = -range; z <= range; z += step) {
        final pts = <Point3D>[];
        for (double x = -range; x <= range; x += step * 0.5) {
          final y = (d - a * x - c * z) / b;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
      for (double x = -range; x <= range; x += step) {
        final pts = <Point3D>[];
        for (double z = -range; z <= range; z += step * 0.5) {
          final y = (d - a * x - c * z) / b;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
    } else {
      // x = (d - by - cz) / a  — vertical plane, free variable z
      for (double z = -range; z <= range; z += step) {
        final pts = <Point3D>[];
        for (double y = -range; y <= range; y += step * 0.5) {
          final x = (d - b * y - c * z) / a;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
      for (double y = -range; y <= range; y += step) {
        final pts = <Point3D>[];
        for (double z = -range; z <= range; z += step * 0.5) {
          final x = (d - b * y - c * z) / a;
          pts.add(Point3D(x, y, z));
        }
        addClippedPath(pts);
      }
    }

    final avgZ = count > 0 ? totalZ / count : 0.0;

    renderables.add(
      _Renderable(
        depth: avgZ,
        draw: (canvas) {
          final paint = Paint()
            ..color = color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
          for (final pts in lines) {
            if (pts.length >= 2) {
              canvas.drawPoints(PointMode.polygon, pts, paint);
            }
          }
        },
      ),
    );
  }

  void _collectSurface(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final vertices = obj.vertices;
    final indices = obj.indices;
    if (vertices.isEmpty || indices.length < 3) return;

    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color.withValues(alpha: objAlpha * obj.opacity * 0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Create triangle renderables
    for (int i = 0; i + 2 < indices.length; i += 3) {
      final i0 = indices[i];
      final i1 = indices[i + 1];
      final i2 = indices[i + 2];
      if (i0 < 0 ||
          i0 >= vertices.length ||
          i1 < 0 ||
          i1 >= vertices.length ||
          i2 < 0 ||
          i2 >= vertices.length) {
        continue;
      }
      final clipped = _clipPolygonToDepthRange(
        [vertices[i0], vertices[i1], vertices[i2]],
        camera,
        projection,
      );
      if (clipped.length < 3) continue;
      final projected = clipped
          .map((point) => worldToScreen(point, camera, projection))
          .toList();
      final fillPaths = <Path>[];
      for (var fan = 1; fan + 1 < projected.length; fan++) {
        final p0 = projected[0];
        final p1 = projected[fan];
        final p2 = projected[fan + 1];
        fillPaths.add(
          Path()
            ..moveTo(p0.x, p0.y)
            ..lineTo(p1.x, p1.y)
            ..lineTo(p2.x, p2.y)
            ..close(),
        );
      }
      final outlinePath = Path()..moveTo(projected.first.x, projected.first.y);
      for (final point in projected.skip(1)) {
        outlinePath.lineTo(point.x, point.y);
      }
      outlinePath.close();
      final avgDepth =
          projected.fold<double>(0, (sum, point) => sum + point.z) /
          projected.length;

      renderables.add(
        _Renderable(
          depth: avgDepth,
          draw: (canvas) {
            for (final path in fillPaths) {
              canvas.drawPath(path, fillPaint);
            }
            canvas.drawPath(outlinePath, strokePaint);
          },
        ),
      );
    }
  }

  void _collectSphere(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final center = obj.sphereCenter;
    final radius = obj.sphereRadius;
    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);
    final segments = 16;

    // Generate wireframe sphere: latitude and longitude lines
    final lines = <List<Offset>>[];
    var totalZ = 0.0;
    var count = 0;

    void addClippedPath(List<Point3D> points) {
      for (var i = 1; i < points.length; i++) {
        final clipped = clipLineToView(
          Object3D.line(points[i - 1], points[i]),
          camera,
          projection,
        );
        if (clipped.length != 2) continue;
        final start = worldToScreen(clipped[0], camera, projection);
        final end = worldToScreen(clipped[1], camera, projection);
        lines.add([Offset(start.x, start.y), Offset(end.x, end.y)]);
        totalZ += start.z + end.z;
        count += 2;
      }
    }

    // Longitude lines (around Y axis)
    for (int i = 0; i < segments; i++) {
      final theta = i * 2 * dart_math.pi / segments;
      final worldPoints = <Point3D>[];
      for (int j = 0; j <= segments; j++) {
        final phi = -dart_math.pi / 2 + j * dart_math.pi / segments;
        final x = center.x + radius * dart_math.cos(phi) * dart_math.cos(theta);
        final y = center.y + radius * dart_math.sin(phi);
        final z = center.z + radius * dart_math.cos(phi) * dart_math.sin(theta);
        worldPoints.add(Point3D(x, y, z));
      }
      addClippedPath(worldPoints);
    }

    // Latitude lines
    for (int j = 1; j < segments; j++) {
      final phi = -dart_math.pi / 2 + j * dart_math.pi / segments;
      final worldPoints = <Point3D>[];
      for (int i = 0; i <= segments; i++) {
        final theta = i * 2 * dart_math.pi / segments;
        final x = center.x + radius * dart_math.cos(phi) * dart_math.cos(theta);
        final y = center.y + radius * dart_math.sin(phi);
        final z = center.z + radius * dart_math.cos(phi) * dart_math.sin(theta);
        worldPoints.add(Point3D(x, y, z));
      }
      addClippedPath(worldPoints);
    }

    final avgZ = count > 0
        ? totalZ / count
        : (worldToScreen(center, camera, projection).z);
    if (lines.isEmpty) return;

    renderables.add(
      _Renderable(
        depth: avgZ,
        draw: (canvas) {
          final paint = Paint()
            ..color = color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
          for (final pts in lines) {
            canvas.drawPoints(PointMode.polygon, pts, paint);
          }
        },
      ),
    );
  }

  void _collectPolyhedron(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final vertices = obj.vertices;
    final indices = obj.indices;
    if (vertices.isEmpty || indices.length < 3) return;

    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final fillColor = Color(obj.color)
        .withValues(alpha: objAlpha * obj.opacity);
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final edgeNormals = <(int, int), List<Vector3D>>{};
    final edgeFaces = <(int, int), List<int>>{};
    final facePaths = <List<Path>>[];
    final faceDepths = <double>[];
    final faceEdges = <List<(Offset, Offset)>>[];
    void addEdge(int first, int second, Vector3D normal, int faceIndex) {
      final key = first < second ? (first, second) : (second, first);
      edgeNormals.putIfAbsent(key, () => []).add(normal);
      edgeFaces.putIfAbsent(key, () => []).add(faceIndex);
    }

    for (var i = 0; i + 2 < indices.length; i += 3) {
      final ia = indices[i];
      final ib = indices[i + 1];
      final ic = indices[i + 2];
      if (ia < 0 ||
          ib < 0 ||
          ic < 0 ||
          ia >= vertices.length ||
          ib >= vertices.length ||
          ic >= vertices.length) {
        continue;
      }
      final a = vertices[ia];
      final b = vertices[ib];
      final c = vertices[ic];
      final normal = _normalizedTriangleNormal(a, b, c);
      if (normal == null) continue;

      final clipped = _clipPolygonToDepthRange([a, b, c], camera, projection);
      if (clipped.length < 3) continue;
      final projected = clipped
          .map((point) => worldToScreen(point, camera, projection))
          .toList();
      final paths = <Path>[];
      for (var fan = 1; fan + 1 < projected.length; fan++) {
        paths.add(
          Path()
            ..moveTo(projected[0].x, projected[0].y)
            ..lineTo(projected[fan].x, projected[fan].y)
            ..lineTo(projected[fan + 1].x, projected[fan + 1].y)
            ..close(),
        );
      }
      final depth =
          projected.fold<double>(0, (sum, point) => sum + point.z) /
          projected.length;
      final faceIndex = facePaths.length;
      facePaths.add(paths);
      faceDepths.add(depth);
      faceEdges.add([]);
      addEdge(ia, ib, normal, faceIndex);
      addEdge(ib, ic, normal, faceIndex);
      addEdge(ic, ia, normal, faceIndex);
    }

    final edgePaint = Paint()
      ..color = solidEdgeContrastColor(Color(obj.color))
          .withValues(alpha: objAlpha * obj.opacity)
      ..strokeWidth = obj.edgeWidth.clamp(0.0, maxSolidEdgeWidth).toDouble()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (obj.showEdges && obj.edgeWidth > 0) {
      for (final entry in edgeNormals.entries) {
        final normals = entry.value;
        final firstNormal = normals.first;
        final isCrease =
            normals.length == 1 ||
            normals.any((normal) => firstNormal.dot(normal).abs() < 0.9999);
        if (!isCrease) continue;

        final (first, second) = entry.key;
        final clipped = clipLineToView(
          Object3D.line(
            vertices[first],
            vertices[second],
            lineKind: Line3DKind.segment,
          ),
          camera,
          projection,
        );
        if (clipped.length != 2) continue;
        final start = worldToScreen(clipped[0], camera, projection);
        final end = worldToScreen(clipped[1], camera, projection);
        final incidentFaces = edgeFaces[entry.key]!;
        final ownerFace = incidentFaces.reduce(
          (first, second) =>
              faceDepths[first] <= faceDepths[second] ? first : second,
        );
        faceEdges[ownerFace].add((
          Offset(start.x, start.y),
          Offset(end.x, end.y),
        ));
      }
    }

    for (var faceIndex = 0; faceIndex < facePaths.length; faceIndex++) {
      final paths = facePaths[faceIndex];
      final edges = faceEdges[faceIndex];
      renderables.add(
        _Renderable(
          depth: faceDepths[faceIndex],
          draw: (canvas) {
            for (final path in paths) {
              canvas.drawPath(path, fillPaint);
            }
            for (final (start, end) in edges) {
              canvas.drawLine(start, end, edgePaint);
            }
          },
        ),
      );
    }
  }

  void _collectVector(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final origin = obj.point;
    final tip = origin + obj.vector;
    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);

    final clipped = clipLineToView(
      Object3D.line(origin, tip),
      camera,
      projection,
    );
    if (clipped.length != 2) return;
    final originScreen = worldToScreen(clipped[0], camera, projection);
    final tipScreen = worldToScreen(clipped[1], camera, projection);
    final avgZ = (originScreen.z + tipScreen.z) / 2;
    final tipIsVisible = clipped[1].distanceTo(tip) <= 1e-9;

    renderables.add(
      _Renderable(
        depth: avgZ,
        draw: (canvas) {
          final paint = Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;

          final from = Offset(originScreen.x, originScreen.y);
          final to = Offset(tipScreen.x, tipScreen.y);
          canvas.drawLine(from, to, paint);

          // Arrow head
          if (tipIsVisible) _drawArrowHeadStatic(canvas, from, to, color);
        },
      ),
    );
  }

  void _drawArrowHeadStatic(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
  ) {
    final direction = (to - from);
    final length = direction.distance;
    if (length < 5) return;

    final unit = direction / length;
    final perp = Offset(-unit.dy, unit.dx);
    final arrowSize = 10.0;

    final tip = to;
    final base = to - unit * arrowSize;
    final left = base + perp * arrowSize * 0.4;
    final right = base - perp * arrowSize * 0.4;

    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _collectCurve(
    List<_Renderable> renderables,
    Object3D obj,
    Camera3D camera,
    Projection3D projection,
  ) {
    final vertices = obj.vertices;
    if (vertices.length < 2) return;

    final objAlpha = ((obj.color >> 24) & 0xFF) / 255.0;
    final color = Color(obj.color).withValues(alpha: objAlpha * obj.opacity);
    final curveStarts = obj.curveStarts
        .where((start) => start > 0 && start < vertices.length)
        .toSet();
    var pathStart = 0;

    void addPath(int pathEnd) {
      if (pathEnd - pathStart < 2) {
        pathStart = pathEnd;
        return;
      }
      final projectedSegments = <(Offset, Offset)>[];
      var totalDepth = 0.0;
      for (var i = pathStart + 1; i < pathEnd; i++) {
        final clipped = clipLineToView(
          Object3D.line(vertices[i - 1], vertices[i]),
          camera,
          projection,
        );
        if (clipped.length != 2) continue;
        final start = worldToScreen(clipped[0], camera, projection);
        final end = worldToScreen(clipped[1], camera, projection);
        projectedSegments.add((Offset(start.x, start.y), Offset(end.x, end.y)));
        totalDepth += start.z + end.z;
      }
      pathStart = pathEnd;
      if (projectedSegments.isEmpty) return;
      renderables.add(
        _Renderable(
          depth: totalDepth / (projectedSegments.length * 2),
          draw: (canvas) {
            final paint = Paint()
              ..color = color
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke;
            final path = Path();
            for (final (start, end) in projectedSegments) {
              path
                ..moveTo(start.dx, start.dy)
                ..lineTo(end.dx, end.dy);
            }
            canvas.drawPath(path, paint);
          },
        ),
      );
    }

    for (var i = 1; i < vertices.length; i++) {
      if (curveStarts.contains(i)) addPath(i);
    }
    addPath(vertices.length);
  }

  // ==================================================================
  // shouldRepaint
  // ==================================================================

  @override
  bool shouldRepaint(MathCanvas3DPainter oldDelegate) {
    return oldDelegate.cameraDistance != cameraDistance ||
        oldDelegate.cameraTheta != cameraTheta ||
        oldDelegate.cameraPhi != cameraPhi ||
        oldDelegate.cameraTarget != cameraTarget ||
        oldDelegate.projectionType != projectionType ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.showPlane != showPlane ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.objectsVersion != objectsVersion ||
        oldDelegate.canvasWidth != canvasWidth ||
        oldDelegate.canvasHeight != canvasHeight ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.constructionPreview != constructionPreview ||
        oldDelegate.selectedPoint != selectedPoint ||
        oldDelegate.pointDragMode != pointDragMode;
  }
}

// ======================================================================
// Internal types
// ======================================================================

/// A renderable element with depth for z-sorting.
class _Renderable {
  final double depth;
  final void Function(Canvas canvas) draw;

  const _Renderable({required this.depth, required this.draw});
}
