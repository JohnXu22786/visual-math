import 'dart:math' as dart_math;

import 'math_3d_object.dart';
import 'math_3d_tool.dart';

/// Result of a construction action — what the system should do next.
enum ConstructionAction {
  /// Continue waiting for more user input on the current step.
  awaitInput,

  /// Advance to the next step.
  advanceStep,

  /// Construction is complete — create the object.
  complete,

  /// Reset the construction (user cancelled or error).
  reset,
}

/// Tracks the state of an ongoing construction.
///
/// When the user selects a tool, a new [ConstructionState] is created.
/// As the user clicks in the 3D view, points are accumulated.
/// When enough points are collected, the object is created.
class ConstructionState {
  final ConstructionTool tool;
  final List<Point3D> _points = [];
  int _stepIndex = 0;
  Object3D? _previewObject;
  Object3D? _result;
  String? _validationMessage;
  Vector3D _workingPlaneNormal = Vector3D.unitZ;

  int polygonSides;

  ConstructionState({required this.tool, this.polygonSides = 6}) {
    if (polygonSides < 3 || polygonSides > 12) {
      throw ArgumentError.value(polygonSides, 'polygonSides', 'Use 3–12 sides');
    }
  }

  /// Change the side count without discarding points in a regular polygon
  /// construction already in progress.
  void updatePolygonSides(int sides) {
    if (sides < 3 || sides > 12) {
      throw ArgumentError.value(sides, 'polygonSides', 'Use 3–12 sides');
    }
    polygonSides = sides;
    _previewObject = null;
  }

  /// The current step the user is on.
  int get stepIndex => _stepIndex;

  /// Points accumulated so far in this construction.
  List<Point3D> get points => List.unmodifiable(_points);

  /// Keep an in-progress input aligned with its moved scene point.
  void updatePoint(int index, Point3D point) {
    if (index < 0 || index >= _points.length || !_isFinitePoint(point)) return;
    _points[index] = point;
    _previewObject = null;
  }

  /// A preview object showing what's being constructed so far.
  Object3D? get previewObject => _previewObject;

  /// The completed object (non-null only after [complete] returns true).
  Object3D? get result => _result;

  /// Total number of steps in this construction workflow.
  int get totalSteps {
    final workflow = ConstructionWorkflow.workflows[tool];
    if (workflow == null) return 1;
    return workflow.steps.length;
  }

  /// The instruction for the current step.
  String get currentInstruction {
    if (_validationMessage != null) return _validationMessage!;
    final workflow = ConstructionWorkflow.workflows[tool];
    if (workflow == null || _stepIndex >= workflow.steps.length) {
      return '完成构造';
    }
    return workflow.steps[_stepIndex].instruction;
  }

  /// Whether the construction is complete.
  bool get isComplete => _result != null;

  /// Add a point to the construction and return the action to take.
  ConstructionAction addPoint(
    Point3D point, {
    Vector3D? workingPlaneNormal,
    bool closeToFirstPoint = false,
  }) {
    if (!_isFinitePoint(point)) {
      return _reject('无法放置无效坐标，请重新选择位置');
    }
    if (tool == ConstructionTool.conic &&
        _points.any((existing) => existing.distanceTo(point) < 1e-9)) {
      return _reject('圆锥曲线的五个点不能重合，请重新选择');
    }
    if ((tool == ConstructionTool.arc ||
            tool == ConstructionTool.circularSector) &&
        _points.length == 2) {
      final projectedEnd = _projectArcEndpoint(_points[0], _points[1], point);
      if (projectedEnd == null) {
        return _reject('圆弧终点不能与圆心重合，请重新选择终点');
      }
      point = projectedEnd;
    }
    if (const {
          ConstructionTool.polygon,
          ConstructionTool.locus,
          ConstructionTool.polyline,
          ConstructionTool.area,
        }.contains(tool) &&
        _points.isNotEmpty &&
        (_points.first.distanceTo(point) < _closureTolerance() ||
            closeToFirstPoint) &&
        !_hasThreeDistinctVertices()) {
      return _reject('至少选择三个不同的顶点后才能点击首点闭合');
    }

    // Reject degenerate inputs before they become part of the construction.
    // A zero-length edge or a collinear plane is not a useful object and would
    // otherwise produce invalid normals or invisible geometry.
    if (const {
          ConstructionTool.line,
          ConstructionTool.segment,
          ConstructionTool.ray,
          ConstructionTool.vector,
          ConstructionTool.midpoint,
          ConstructionTool.regularPolygon,
          ConstructionTool.plane,
          ConstructionTool.parallelPlane,
          ConstructionTool.perpendicularPlane,
          ConstructionTool.tetrahedron,
          ConstructionTool.circleThreePoints,
          ConstructionTool.circumcircleArc,
          ConstructionTool.circumcircleSector,
        }.contains(tool) &&
        _points.isNotEmpty &&
        !((tool == ConstructionTool.parallelPlane ||
                tool == ConstructionTool.perpendicularPlane) &&
            _points.length >= 3) &&
        _points.last.distanceTo(point) < 1e-9) {
      return _reject('两点不能重合，请重新选择第二个点');
    }
    if ((tool == ConstructionTool.sphere ||
            tool == ConstructionTool.sphereByRadius ||
            tool == ConstructionTool.circle) &&
        _points.isNotEmpty &&
        _points.last.distanceTo(point) < 1e-9) {
      return _reject('半径必须大于 0，请重新选择半径点');
    }
    if (tool == ConstructionTool.generalPlane &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('两点不能重合，请重新选择法向量端点');
    }
    if ((tool == ConstructionTool.circleAxisPoint ||
            tool == ConstructionTool.circleCenterNormalRadius) &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('圆的轴线或法向量两点不能重合，请重新选择');
    }
    if (tool == ConstructionTool.circleAxisPoint && _points.length == 2) {
      final axis = _points[1] - _points[0];
      final fromAxis = point - _points[0];
      final radial = fromAxis - axis * (fromAxis.dot(axis) / axis.dot(axis));
      if (radial.magnitude < 1e-9) {
        return _reject('圆周点不能位于轴线上，请重新选择');
      }
    }
    if (tool == ConstructionTool.circleCenterNormalRadius &&
        _points.length == 2) {
      final normal = (_points[1] - _points[0]).normalized();
      final radiusVector = point - _points[0];
      final axialOffset = radiusVector.dot(normal).abs();
      final planeTolerance = dart_math
          .max(1e-9, radiusVector.magnitude * 1e-9)
          .toDouble();
      if (axialOffset > planeTolerance) {
        return _reject('圆周点必须位于与法向量垂直的平面内，请重新选择');
      }
      final radial = radiusVector - normal * radiusVector.dot(normal);
      if (radial.magnitude < 1e-9) {
        return _reject('半径方向不能与法向量平行，请重新选择圆周点');
      }
    }
    if ((tool == ConstructionTool.parallelLine ||
            tool == ConstructionTool.perpendicularLine) &&
        _points.length == 2 &&
        _points[1].distanceTo(point) < 1e-9) {
      return _reject('方向线上的两点不能重合，请重新选择方向点');
    }
    if ((tool == ConstructionTool.plane ||
            tool == ConstructionTool.circleThreePoints ||
            tool == ConstructionTool.circumcircleArc ||
            tool == ConstructionTool.circumcircleSector ||
            tool == ConstructionTool.parallelPlane ||
            tool == ConstructionTool.perpendicularPlane) &&
        _points.length == 2 &&
        !_isNonCollinear(_points[0], _points[1], point)) {
      return _reject('参考平面的三个点不能共线，请重新选择第三个点');
    }
    if (tool == ConstructionTool.perpendicularPlane && _points.length == 4) {
      final referenceNormal = _triangleUnitNormal(
        _points[0],
        _points[1],
        _points[2],
      );
      final direction = point - _points[3];
      if (direction.magnitude < 1e-9) {
        return _reject('方向点不能与平面经过点重合，请重新选择');
      }
      if (referenceNormal.cross(direction.normalized()).magnitude < 1e-9) {
        return _reject('方向点不能位于参考平面的法线上，请重新选择');
      }
    }
    if (tool == ConstructionTool.fixedLengthSegment &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('方向点不能与起点重合，请重新选择方向点');
    }
    if (tool == ConstructionTool.fixedLengthSegment &&
        _points.length == 2 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('线段长度必须大于 0，请重新选择长度点');
    }
    if ((tool == ConstructionTool.arc ||
            tool == ConstructionTool.circularSector) &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('圆弧半径必须大于 0，请重新选择起点');
    }
    if ((tool == ConstructionTool.arc ||
            tool == ConstructionTool.circularSector) &&
        _points.length == 2) {
      if (point.distanceTo(_points[1]) < 1e-9) {
        return _reject('圆弧终点不能与起点重合，请重新选择终点');
      }
    }
    if (tool == ConstructionTool.ellipse &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('长轴长度必须大于 0，请重新选择长轴端点');
    }
    if (tool == ConstructionTool.ellipse && _points.length == 2) {
      final major = _points[1] - _points[0];
      final majorLength = major.magnitude;
      final majorUnit = major.normalized();
      final minorOffset = point - _points[0];
      final minorRadius =
          (minorOffset - majorUnit * minorOffset.dot(majorUnit)).magnitude;
      if (minorRadius < 1e-9) {
        return _reject('短轴长度必须大于 0，请重新选择短轴端点');
      }
      if (minorRadius >
          majorLength + dart_math.max(1e-12, majorLength * 1e-9)) {
        return _reject('短轴长度不能超过长轴，请重新选择短轴端点');
      }
    }
    if (tool == ConstructionTool.parabola && _points.length == 2) {
      final directrix = point - _points[1];
      final lengthSquared = directrix.dot(directrix);
      if (directrix.magnitude < 1e-9) {
        return _reject('准线两点不能重合，请重新选择第二点');
      }
      final t = (_points[0] - _points[1]).dot(directrix) / lengthSquared;
      final foot = _points[1] + directrix * t;
      if (_points[0].distanceTo(foot) < 1e-9) {
        return _reject('焦点不能位于准线上，请重新选择准线点');
      }
    }
    if (tool == ConstructionTool.parabola &&
        _points.length == 1 &&
        _points[0].distanceTo(point) < 1e-9) {
      return _reject('准线不能经过焦点，请重新选择准线点');
    }
    if (tool == ConstructionTool.surfaceOfRevolution &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('旋转轴长度必须大于 0，请重新选择轴线第二点');
    }
    if (tool == ConstructionTool.surfaceOfRevolution &&
        _points.length == 3 &&
        _points[2].distanceTo(point) < 1e-9) {
      return _reject('母线长度必须大于 0，请重新选择母线终点');
    }
    if (tool == ConstructionTool.surfaceOfRevolution && _points.length == 3) {
      final axis = (_points[1] - _points[0]).normalized();
      final start = _points[2] - _points[0];
      final end = point - _points[0];
      final startRadius = (start - axis * start.dot(axis)).magnitude;
      final endRadius = (end - axis * end.dot(axis)).magnitude;
      if (startRadius < 1e-9 && endRadius < 1e-9) {
        return _reject('母线不能完全位于旋转轴上，请重新选择终点');
      }
    }
    if (tool == ConstructionTool.angle &&
        (_points.length == 1 || _points.length == 2) &&
        _points[_points.length == 1 ? 0 : 1].distanceTo(point) < 1e-9) {
      return _reject('角的两边长度必须大于 0，请重新选择');
    }
    if (tool == ConstructionTool.rotation &&
        _points.length == 2 &&
        _points[1].distanceTo(point) < 1e-9) {
      return _reject('旋转轴两点不能重合，请重新选择第二点');
    }
    if (tool == ConstructionTool.rotation && _points.length == 3) {
      final axis = (_points[2] - _points[1]).normalized();
      final end = point - _points[1];
      final endPlane = end - axis * end.dot(axis);
      if (endPlane.magnitude < 1e-9) {
        return _reject('角度点不能位于旋转轴上，请重新选择角度点');
      }
    }
    if (tool == ConstructionTool.axialSymmetry &&
        _points.length == 2 &&
        _points[1].distanceTo(point) < 1e-9) {
      return _reject('对称轴两点不能重合，请重新选择第二点');
    }
    if (tool == ConstructionTool.angleBisector &&
        (_points.length == 1 || _points.length == 2) &&
        _points[_points.length == 1 ? 0 : 1].distanceTo(point) < 1e-9) {
      return _reject('角的两边长度必须大于 0，请重新选择');
    }
    if (tool == ConstructionTool.reflectionInPlane &&
        _points.length == 2 &&
        _points[1].distanceTo(point) < 1e-9) {
      return _reject('反射平面的两个点不能重合，请重新选择');
    }
    if (tool == ConstructionTool.reflectionInPlane &&
        _points.length == 3 &&
        !_isNonCollinear(_points[1], _points[2], point)) {
      return _reject('反射平面的三个点不能共线，请重新选择第三个点');
    }
    if (tool == ConstructionTool.hyperbola &&
        _points.length == 1 &&
        _points.first.distanceTo(point) < 1e-9) {
      return _reject('实轴长度必须大于 0，请重新选择实轴端点');
    }
    if (tool == ConstructionTool.hyperbola && _points.length == 2) {
      final realAxis = (_points[1] - _points[0]).normalized();
      final offset = point - _points[0];
      final transverse = offset - realAxis * offset.dot(realAxis);
      if (transverse.magnitude < 1e-9) {
        return _reject('共轭轴不能与实轴重合，请重新选择一点');
      }
    }
    if ((tool == ConstructionTool.cube ||
            tool == ConstructionTool.prism ||
            tool == ConstructionTool.extrudePrism ||
            tool == ConstructionTool.pyramid) &&
        _points.length == 1 &&
        _points.last.distanceTo(point) < 1e-9) {
      return _reject('底面顶点不能重合，请重新选择');
    }
    if ((tool == ConstructionTool.prism ||
            tool == ConstructionTool.extrudePrism ||
            tool == ConstructionTool.pyramid) &&
        _points.length == 2 &&
        !_isNonCollinear(_points[0], _points[1], point)) {
      return _reject('底面三个点不能共线，请重新选择第三个点');
    }
    if ((tool == ConstructionTool.prism ||
            tool == ConstructionTool.extrudePrism ||
            tool == ConstructionTool.pyramid) &&
        _points.length == 3) {
      final baseNormal = _triangleUnitNormal(
        _points[0],
        _points[1],
        _points[2],
      );
      final baseScale = dart_math
          .max(
            _points[0].distanceTo(_points[1]),
            dart_math.max(
              _points[0].distanceTo(_points[2]),
              _points[1].distanceTo(_points[2]),
            ),
          )
          .toDouble();
      final coordinateScale = <Point3D>[..._points, point].fold<double>(
        0,
        (maximum, candidate) => dart_math
            .max(
              maximum,
              dart_math.max(
                candidate.x.abs(),
                dart_math.max(candidate.y.abs(), candidate.z.abs()),
              ),
            )
            .toDouble(),
      );
      const machineEpsilon = 2.220446049250313e-16;
      final heightTolerance = dart_math
          .max(baseScale * 1e-9, coordinateScale * machineEpsilon * 8)
          .toDouble();
      if ((point - _points[0]).dot(baseNormal).abs() < heightTolerance) {
        return _reject('高度必须离开底面，请重新选择顶点');
      }
    }
    if ((tool == ConstructionTool.cone ||
            tool == ConstructionTool.extrudeCone ||
            tool == ConstructionTool.cylinder) &&
        _points.length == 1 &&
        _points[0].distanceTo(point) < 1e-9) {
      return _reject('底面半径必须大于 0，请重新选择半径点');
    }
    if ((tool == ConstructionTool.cone ||
            tool == ConstructionTool.extrudeCone ||
            tool == ConstructionTool.cylinder) &&
        _points.length == 2) {
      final axis = point - _points[0];
      if (axis.magnitude < 1e-9) {
        return _reject('高度必须大于 0，请重新选择顶部位置');
      }
      final axisUnit = axis.normalized();
      final radiusVector = _points[1] - _points[0];
      final projectedRadius =
          radiusVector - axisUnit * radiusVector.dot(axisUnit);
      if (projectedRadius.magnitude < 1e-9) {
        return _reject('半径方向不能与高度方向平行，请重新选择顶部位置');
      }
    }
    if (tool == ConstructionTool.conic &&
        _points.length == 3 &&
        _conicPlane([..._points, point]) == null) {
      return _reject('前四个点必须共面并能确定平面，请重新选择第四个点');
    }
    if (tool == ConstructionTool.conic && _points.length == 4) {
      if (_conicPlane([..._points, point]) == null) {
        return _reject('五个点必须共面且能确定圆锥曲线，请重新选择');
      }
    }

    _validationMessage = null;
    if (workingPlaneNormal != null && workingPlaneNormal.magnitude > 1e-9) {
      _workingPlaneNormal = workingPlaneNormal.normalized();
    }
    _points.add(point);
    // Advance to next step, capped at the last workflow step
    final maxStep = totalSteps - 1;
    _stepIndex = _points.length < totalSteps ? _points.length : maxStep;

    final extendedAction = _addExtendedTool(
      closeToFirstPoint: closeToFirstPoint,
    );
    if (extendedAction != null) return extendedAction;

    // Determine if we have enough points based on tool type
    switch (tool) {
      case ConstructionTool.move:
        return ConstructionAction.reset;

      case ConstructionTool.point:
        // Single click = point is placed
        _result = Object3D.point(
          point,
          color: 0xFF2196F3,
          label: 'P${_points.length}',
        );
        _updatePreview();
        return ConstructionAction.complete;

      case ConstructionTool.midpoint:
      case ConstructionTool.vector:
      case ConstructionTool.regularPolygon:
      case ConstructionTool.tetrahedron:
        if (_points.length >= 2) {
          final a = _points[0];
          final b = _points[1];
          _result = switch (tool) {
            ConstructionTool.midpoint => Object3D.point(
              a.midpoint(b),
              color: 0xFF2196F3,
            ),
            ConstructionTool.vector => Object3D.vectorObj(
              origin: a,
              vector: b - a,
              color: 0xFF00897B,
            ),
            ConstructionTool.regularPolygon => _createRegularPolygon(a, b),
            _ => _createTetrahedron(a, b),
          };
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.circleThreePoints:
        if (_points.length >= 3) {
          _result = _createThreePointCircle(_points[0], _points[1], _points[2]);
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.line:
      case ConstructionTool.segment:
      case ConstructionTool.ray:
        if (_points.length >= 2) {
          _result = Object3D.line(
            _points[0],
            _points[1],
            color: 0xFF4CAF50,
            label: ToolInfo.all[tool]!.name,
            lineKind: switch (tool) {
              ConstructionTool.line => Line3DKind.line,
              ConstructionTool.ray => Line3DKind.ray,
              _ => Line3DKind.segment,
            },
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.polygon:
        // Check if we closed the polygon (clicked near first point)
        if (_points.length >= 4 &&
            (_points.first.distanceTo(_points.last) < _closureTolerance() ||
                closeToFirstPoint)) {
          // Remove the duplicate closing point
          final vertices = List<Point3D>.from(_points)..removeLast();
          if (vertices.length >= 3) {
            final plane = _conicPlane(vertices);
            if (plane == null &&
                (_hasNonCollinearVertices(vertices) || _hasArea(vertices))) {
              _validationMessage = '多边形要求所有顶点共面，请重新选择所有顶点';
              _points.clear();
              _stepIndex = 0;
              _updatePreview();
              return ConstructionAction.awaitInput;
            }
            if (plane != null && _hasSelfIntersectingEdges(vertices)) {
              _validationMessage = '多边形边界不能自交，请重新选择所有顶点';
              _points.clear();
              _stepIndex = 0;
              _updatePreview();
              return ConstructionAction.awaitInput;
            }
            if (_hasArea(vertices)) {
              _result = _createPolygon(vertices);
              _updatePreview();
              return ConstructionAction.complete;
            }
          }
          _points.removeLast();
          _stepIndex = _points.length < totalSteps
              ? _points.length
              : totalSteps - 1;
          _updatePreview();
          return ConstructionAction.awaitInput;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.plane:
        if (_points.length >= 3) {
          if (!_isNonCollinear(_points[0], _points[1], _points[2])) {
            _points.removeLast();
            _stepIndex = _points.length;
            _updatePreview();
            return ConstructionAction.awaitInput;
          }
          _result = _createPlane(_points[0], _points[1], _points[2]);
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.sphere:
        if (_points.length >= 2) {
          final radius = _points[0].distanceTo(_points[1]);
          if (radius < 1e-10) {
            _points.removeLast();
            _stepIndex = _points.length;
            _updatePreview();
            return ConstructionAction.awaitInput;
          }
          _result = Object3D.sphere(
            center: _points[0],
            radius: radius,
            color: 0x804CAF50,
            label: 'Sphere',
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.circle:
        if (_points.length >= 2) {
          _result = _createCircle(
            _points[0],
            _points[1],
            planeNormal: _workingPlaneNormal,
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.cube:
        if (_points.length >= 2) {
          _result = _createCube(
            _points[0],
            _points[1],
            planeNormal: _workingPlaneNormal,
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;

      case ConstructionTool.extrudePrism:
        if (_points.length >= 4) {
          _result = _createTriangularPrism(
            _points[0],
            _points[1],
            _points[2],
            _points[3],
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;
      case ConstructionTool.pyramid:
        if (_points.length >= 4) {
          _result = _createPyramid(
            _points[0],
            _points[1],
            _points[2],
            _points[3],
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;
      case ConstructionTool.cone:
        if (_points.length >= 3) {
          _result = _createCone(_points[0], _points[1], _points[2]);
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;
      case ConstructionTool.cylinder:
        if (_points.length >= 3) {
          _result = _createCylinder(_points[0], _points[1], _points[2]);
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;
      default:
        return ConstructionAction.reset;
    }
  }

  ConstructionAction? _addExtendedTool({required bool closeToFirstPoint}) {
    final count = _points.length;

    ConstructionAction finishWhenReady(
      int required,
      Object3D Function() create,
    ) {
      if (count < required) {
        _updatePreview();
        return ConstructionAction.advanceStep;
      }
      _result = create();
      _updatePreview();
      return ConstructionAction.complete;
    }

    ConstructionAction finishOpenCurve({required bool filled}) {
      if (count >= 4 &&
          (_points.first.distanceTo(_points.last) < _closureTolerance() ||
              closeToFirstPoint)) {
        if (filled) {
          _points.removeLast();
        } else {
          _points[_points.length - 1] = _points.first;
        }
        if (filled) {
          final plane = _conicPlane(_points);
          if (plane != null && _hasSelfIntersectingEdges(_points)) {
            _validationMessage = '面积测量要求边界不自交，请重新选择所有顶点';
            _points.clear();
            _stepIndex = 0;
            _updatePreview();
            return ConstructionAction.awaitInput;
          }
          final hasArea = _hasArea(_points);
          if (plane == null && (hasArea || _hasNonCollinearVertices(_points))) {
            _validationMessage = '面积测量要求所有顶点共面，请重新选择所有顶点';
            _points.clear();
            _stepIndex = 0;
            _updatePreview();
            return ConstructionAction.awaitInput;
          }
          if (hasArea) {
            final area = _polygonArea(_points);
            final center = _polygonInteriorPoint(_points);
            _result = Object3D.point(
              center,
              color: 0xFF1565C0,
              label: '面积 ${area.toStringAsFixed(3)}',
            );
          } else {
            _validationMessage = '顶点不能共线，请继续选择顶点';
            _updatePreview();
            return ConstructionAction.awaitInput;
          }
        } else {
          _result = Object3D.curve(
            points: List<Point3D>.from(_points),
            color: 0xFF1565C0,
          );
        }
        _updatePreview();
        return ConstructionAction.complete;
      }
      _updatePreview();
      return ConstructionAction.advanceStep;
    }

    switch (tool) {
      case ConstructionTool.pointOnObject:
        return finishWhenReady(
          1,
          () => Object3D.point(_points.first, color: 0xFF2196F3),
        );
      case ConstructionTool.fixedLengthSegment:
        return finishWhenReady(3, () {
          return _createFixedLengthSegment(
            _points[0],
            _points[1],
            _points[2],
            color: 0xFF4CAF50,
          );
        });
      case ConstructionTool.parallelLine:
      case ConstructionTool.perpendicularLine:
        return finishWhenReady(3, () {
          return _createParallelOrPerpendicularLine(
            _points[0],
            _points[1],
            _points[2],
            perpendicular: tool == ConstructionTool.perpendicularLine,
            color: 0xFF4CAF50,
          );
        });
      case ConstructionTool.angleBisector:
        return finishWhenReady(3, () {
          return _createAngleBisector(
            _points[0],
            _points[1],
            _points[2],
            color: 0xFF4CAF50,
          );
        });
      case ConstructionTool.prism:
        return finishWhenReady(
          4,
          () => _createTriangularPrism(
            _points[0],
            _points[1],
            _points[2],
            _points[3],
          ),
        );
      case ConstructionTool.sphereByRadius:
        return finishWhenReady(2, () {
          final radius = _points[0].distanceTo(_points[1]);
          return Object3D.sphere(
            center: _points[0],
            radius: radius,
            color: 0x804CAF50,
          );
        });
      case ConstructionTool.extrudeCone:
        return finishWhenReady(
          3,
          () => _createCone(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.surfaceOfRevolution:
        return finishWhenReady(
          4,
          () => _createSurfaceOfRevolution(
            _points[0],
            _points[1],
            _points[2],
            _points[3],
          ),
        );
      case ConstructionTool.generalPlane:
        return finishWhenReady(
          2,
          () => _createPlaneFromNormal(_points[0], _points[1] - _points[0]),
        );
      case ConstructionTool.parallelPlane:
        return finishWhenReady(4, () {
          final normal = _triangleUnitNormal(
            _points[0],
            _points[1],
            _points[2],
          );
          return _createPlaneFromNormal(_points[3], normal);
        });
      case ConstructionTool.perpendicularPlane:
        return finishWhenReady(5, () {
          final referenceNormal = _triangleUnitNormal(
            _points[0],
            _points[1],
            _points[2],
          );
          final direction = _points[4] - _points[3];
          final normal = _stableNormalize(referenceNormal.cross(direction));
          return _createPlaneFromNormal(_points[3], normal);
        });
      case ConstructionTool.circleAxisPoint:
        return finishWhenReady(3, () {
          final axis = _points[1] - _points[0];
          final axisSquared = axis.dot(axis);
          final t = (_points[2] - _points[0]).dot(axis) / axisSquared;
          final center = _points[0] + axis * t;
          final radial = _points[2] - center;
          return _createCircle(center, center + radial, planeNormal: axis);
        });
      case ConstructionTool.circleCenterNormalRadius:
        return finishWhenReady(3, () {
          final normal = (_points[1] - _points[0]).normalized();
          final radiusVector = _points[2] - _points[0];
          final radial = radiusVector - normal * radiusVector.dot(normal);
          return _createCircle(
            _points[0],
            _points[0] + radial,
            planeNormal: normal,
          );
        });
      case ConstructionTool.arc:
        return finishWhenReady(
          3,
          () => _createArc(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.circumcircleArc:
        return finishWhenReady(
          3,
          () => _createCircumcircleArc(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.circularSector:
        return finishWhenReady(
          3,
          () => _createSector(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.circumcircleSector:
        return finishWhenReady(
          3,
          () => _createCircumcircleSector(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.ellipse:
        return finishWhenReady(
          3,
          () => _createEllipse(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.conic:
        if (count < 5) {
          _updatePreview();
          return ConstructionAction.advanceStep;
        }
        final conic = _createConic(_points);
        if (conic == null) {
          _points.removeLast();
          _stepIndex = _points.length < totalSteps
              ? _points.length
              : totalSteps - 1;
          _validationMessage = '五个点必须共面且能确定圆锥曲线，请重新选择';
          _updatePreview();
          return ConstructionAction.awaitInput;
        }
        _result = conic;
        _updatePreview();
        return ConstructionAction.complete;
      case ConstructionTool.parabola:
        return finishWhenReady(
          3,
          () => _createParabola(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.hyperbola:
        return finishWhenReady(
          3,
          () => _createHyperbola(_points[0], _points[1], _points[2]),
        );
      case ConstructionTool.locus:
        return finishOpenCurve(filled: false);
      case ConstructionTool.polyline:
        if (count >= 4 &&
            (_points.first.distanceTo(_points.last) < _closureTolerance() ||
                closeToFirstPoint)) {
          _points[_points.length - 1] = _points.first;
          _result = Object3D.curve(
            points: List<Point3D>.from(_points),
            color: 0xFF1565C0,
          );
          _updatePreview();
          return ConstructionAction.complete;
        }
        _updatePreview();
        return ConstructionAction.advanceStep;
      case ConstructionTool.area:
        return finishOpenCurve(filled: true);
      case ConstructionTool.reflectionInPlane:
        return finishWhenReady(4, () {
          final normal = (_points[2] - _points[1]).cross(
            _points[3] - _points[1],
          );
          final n2 = normal.dot(normal);
          final offset = (_points[0] - _points[1]).dot(normal) / n2;
          return Object3D.point(_points[0] + normal * (-2 * offset));
        });
      case ConstructionTool.centralSymmetry:
        return finishWhenReady(
          2,
          () => Object3D.point(_points[1] + (_points[1] - _points[0])),
        );
      case ConstructionTool.rotation:
        return finishWhenReady(4, () {
          final axis = (_points[2] - _points[1]).normalized();
          final start = _points[0] - _points[1];
          final end = _points[3] - _points[1];
          final startPlane = start - axis * start.dot(axis);
          final endPlane = end - axis * end.dot(axis);
          final angle = dart_math.atan2(
            axis.dot(startPlane.cross(endPlane)),
            startPlane.dot(endPlane),
          );
          return Object3D.point(
            _points[1] + _rotateAroundAxis(start, axis, angle),
          );
        });
      case ConstructionTool.translation:
        return finishWhenReady(
          3,
          () => Object3D.point(_points[0] + (_points[2] - _points[1])),
        );
      case ConstructionTool.dilation:
        return finishWhenReady(3, () {
          final original = _points[0] - _points[1];
          final originalScale = dart_math
              .max(
                original.x.abs(),
                dart_math.max(original.y.abs(), original.z.abs()),
              )
              .toDouble();
          if (originalScale == 0) return Object3D.point(_points[1]);
          final direction = Vector3D(
            original.x / originalScale,
            original.y / originalScale,
            original.z / originalScale,
          ).normalized();
          final radiusVector = _points[2] - _points[1];
          final radiusScale = dart_math
              .max(
                radiusVector.x.abs(),
                dart_math.max(radiusVector.y.abs(), radiusVector.z.abs()),
              )
              .toDouble();
          final radius = radiusScale == 0
              ? 0.0
              : radiusScale *
                    dart_math.sqrt(
                      (radiusVector.x / radiusScale) *
                              (radiusVector.x / radiusScale) +
                          (radiusVector.y / radiusScale) *
                              (radiusVector.y / radiusScale) +
                          (radiusVector.z / radiusScale) *
                              (radiusVector.z / radiusScale),
                    );
          return Object3D.point(_points[1] + direction * radius);
        });
      case ConstructionTool.axialSymmetry:
        return finishWhenReady(3, () {
          final axis = _points[2] - _points[1];
          final lengthSquared = axis.dot(axis);
          if (lengthSquared < 1e-18) return Object3D.point(_points[0]);
          final t = (_points[0] - _points[1]).dot(axis) / lengthSquared;
          final foot = _points[1] + axis * t;
          return Object3D.point(foot + (foot - _points[0]));
        });
      case ConstructionTool.angle:
        return finishWhenReady(3, () {
          final a = _points[0] - _points[1];
          final b = _points[2] - _points[1];
          final cosine = (a.dot(b) / (a.magnitude * b.magnitude)).clamp(
            -1.0,
            1.0,
          );
          final degrees = dart_math.acos(cosine) * 180 / dart_math.pi;
          return Object3D.point(
            _points[1],
            color: 0xFF1565C0,
            label: '角度 ${degrees.toStringAsFixed(2)}°',
          );
        });
      case ConstructionTool.distance:
        return finishWhenReady(2, () {
          final distance = _points[0].distanceTo(_points[1]);
          return Object3D.point(
            _points[0].midpoint(_points[1]),
            color: 0xFF1565C0,
            label: '长度 ${distance.toStringAsFixed(3)}',
          );
        });
      case ConstructionTool.equalVector:
        return finishWhenReady(
          3,
          () => Object3D.vectorObj(
            origin: _points[2],
            vector: _points[1] - _points[0],
            color: 0xFF00897B,
          ),
        );
      case ConstructionTool.text:
        return finishWhenReady(
          1,
          () => Object3D.point(_points.first, label: '文本'),
        );
      default:
        return null;
    }
  }

  /// Update the transient preview without committing a construction point.
  ///
  /// This is deliberately separate from [addPoint]: a drag should show the
  /// object being built, while only pointer-up advances the workflow.
  void updatePreviewPoint(Point3D point, {Vector3D? workingPlaneNormal}) {
    if (!_isFinitePoint(point)) return;
    if (workingPlaneNormal != null && workingPlaneNormal.magnitude > 1e-9) {
      _workingPlaneNormal = workingPlaneNormal.normalized();
    }
    if (_points.isEmpty) {
      _previewObject = Object3D.point(point, color: 0x60808080);
      return;
    }

    if ((tool == ConstructionTool.arc ||
            tool == ConstructionTool.circularSector) &&
        _points.length == 2) {
      final projectedEnd = _projectArcEndpoint(_points[0], _points[1], point);
      if (projectedEnd != null && projectedEnd.distanceTo(_points[1]) >= 1e-9) {
        _previewObject = tool == ConstructionTool.arc
            ? _createArc(_points[0], _points[1], projectedEnd)
            : _createSector(_points[0], _points[1], projectedEnd);
      } else {
        _previewObject = Object3D.line(_points[1], point, color: 0x60808080);
      }
      return;
    }

    if (const {
      ConstructionTool.midpoint,
      ConstructionTool.segment,
      ConstructionTool.ray,
      ConstructionTool.vector,
      ConstructionTool.circleThreePoints,
      ConstructionTool.regularPolygon,
      ConstructionTool.tetrahedron,
    }.contains(tool)) {
      final preview = ConstructionState(tool: tool, polygonSides: polygonSides);
      for (final existing in _points) {
        preview.addPoint(existing, workingPlaneNormal: _workingPlaneNormal);
      }
      preview.addPoint(point, workingPlaneNormal: _workingPlaneNormal);
      _previewObject =
          preview.result ??
          Object3D.curve(points: [..._points, point], color: 0x60808080);
      return;
    }

    final start = _points.last;
    switch (tool) {
      case ConstructionTool.sphere:
      case ConstructionTool.sphereByRadius:
        {
          final radius = start.distanceTo(point);
          _previewObject = radius < 1e-9
              ? Object3D.point(start, color: 0x60808080)
              : Object3D.sphere(
                  center: start,
                  radius: radius,
                  color: 0x404CAF50,
                );
          return;
        }
      case ConstructionTool.circle:
        {
          final radius = start.distanceTo(point);
          _previewObject = radius < 1e-9
              ? Object3D.point(start, color: 0x60808080)
              : _createCircle(
                  start,
                  point,
                  planeNormal: _workingPlaneNormal,
                  color: 0x804CAF50,
                );
          return;
        }
      case ConstructionTool.line:
      case ConstructionTool.cube:
        _previewObject = Object3D.line(start, point, color: 0x60808080);
        return;
      case ConstructionTool.parallelLine:
      case ConstructionTool.perpendicularLine:
        _previewObject = _points.length >= 2
            ? _createParallelOrPerpendicularLine(
                _points[0],
                _points[1],
                point,
                perpendicular: tool == ConstructionTool.perpendicularLine,
                color: 0x60808080,
              )
            : Object3D.line(start, point, color: 0x60808080);
        return;
      case ConstructionTool.angleBisector:
        _previewObject = _points.length >= 2
            ? _createAngleBisector(
                _points[0],
                _points[1],
                point,
                color: 0x60808080,
              )
            : Object3D.line(start, point, color: 0x60808080);
        return;
      case ConstructionTool.fixedLengthSegment:
        _previewObject = _points.length < 2
            ? Object3D.line(start, point, color: 0x60808080)
            : _createFixedLengthSegment(
                _points[0],
                _points[1],
                point,
                color: 0x60808080,
              );
        return;
      case ConstructionTool.cone:
      case ConstructionTool.extrudeCone:
        if (_points.length >= 2 &&
            _hasRoundSolidGeometry(_points[0], _points[1], point)) {
          _previewObject = _createCone(_points[0], _points[1], point);
        } else {
          _previewObject = Object3D.line(start, point, color: 0x60808080);
        }
        return;
      case ConstructionTool.cylinder:
        if (_points.length >= 2 &&
            _hasRoundSolidGeometry(_points[0], _points[1], point)) {
          _previewObject = _createCylinder(_points[0], _points[1], point);
        } else {
          _previewObject = Object3D.line(start, point, color: 0x60808080);
        }
        return;
      case ConstructionTool.prism:
      case ConstructionTool.extrudePrism:
        if (_points.length >= 3) {
          _previewObject = _createTriangularPrism(
            _points[0],
            _points[1],
            _points[2],
            point,
          );
        } else {
          _previewObject = Object3D.line(start, point, color: 0x60808080);
        }
        return;
      case ConstructionTool.pyramid:
        if (_points.length >= 3) {
          _previewObject = _createPyramid(
            _points[0],
            _points[1],
            _points[2],
            point,
          );
        } else {
          _previewObject = Object3D.line(start, point, color: 0x60808080);
        }
        return;
      default:
        _previewObject = Object3D.line(start, point, color: 0x60808080);
    }
  }

  /// Remove a transient preview after a gesture ends or a tool is cancelled.
  void clearPreview() {
    _previewObject = null;
  }

  /// Return a non-mutating preview for the point currently under the cursor.
  Object3D? previewForPoint(Point3D point) {
    if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
      return null;
    }

    final previewPoints = [..._points, point];
    if (previewPoints.length == 1) {
      return Object3D.point(previewPoints.first, color: 0x60808080);
    }
    if (tool == ConstructionTool.polygon) {
      return Object3D.curve(points: previewPoints, color: 0x60808080);
    }
    return Object3D.line(
      previewPoints[previewPoints.length - 2],
      previewPoints.last,
      color: 0x60808080,
    );
  }

  static bool _hasArea(List<Point3D> vertices) {
    final origin = vertices.first;
    var area = Vector3D.zero;
    var scaleSquared = 0.0;
    for (var i = 1; i < vertices.length - 1; i++) {
      final first = vertices[i] - origin;
      final second = vertices[i + 1] - origin;
      area = area + first.cross(second);
      scaleSquared = dart_math
          .max(
            scaleSquared,
            dart_math.max(first.dot(first), second.dot(second)),
          )
          .toDouble();
    }
    return scaleSquared > 0 && area.magnitude > scaleSquared * 1e-10;
  }

  static bool _hasNonCollinearVertices(List<Point3D> vertices) {
    if (vertices.length < 3) return false;
    final anchor = vertices.first;
    for (var first = 1; first < vertices.length - 1; first++) {
      for (var second = first + 1; second < vertices.length; second++) {
        if (_isNonCollinear(anchor, vertices[first], vertices[second])) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasSelfIntersectingEdges(List<Point3D> vertices) {
    final plane = _conicPlane(vertices);
    if (plane == null) return false;
    final coordinates = vertices.map((point) {
      final relative = point - plane.origin;
      return (relative.dot(plane.u), relative.dot(plane.v));
    }).toList();
    final scale = coordinates.fold<double>(0, (maximum, point) {
      return dart_math
          .max(maximum, dart_math.max(point.$1.abs(), point.$2.abs()))
          .toDouble();
    });
    if (!scale.isFinite || scale == 0) return false;
    final normalized = coordinates
        .map((point) => (point.$1 / scale, point.$2 / scale))
        .toList();

    double cross(
      (double, double) first,
      (double, double) second,
      (double, double) third,
    ) =>
        (second.$1 - first.$1) * (third.$2 - first.$2) -
        (second.$2 - first.$2) * (third.$1 - first.$1);

    bool onSegment(
      (double, double) point,
      (double, double) start,
      (double, double) end,
    ) {
      const tolerance = 1e-12;
      return cross(start, end, point).abs() <= tolerance &&
          point.$1 >= dart_math.min(start.$1, end.$1) - tolerance &&
          point.$1 <= dart_math.max(start.$1, end.$1) + tolerance &&
          point.$2 >= dart_math.min(start.$2, end.$2) - tolerance &&
          point.$2 <= dart_math.max(start.$2, end.$2) + tolerance;
    }

    bool segmentsIntersect(
      (double, double) firstStart,
      (double, double) firstEnd,
      (double, double) secondStart,
      (double, double) secondEnd,
    ) {
      const tolerance = 1e-12;
      final firstSide = cross(firstStart, firstEnd, secondStart);
      final secondSide = cross(firstStart, firstEnd, secondEnd);
      final thirdSide = cross(secondStart, secondEnd, firstStart);
      final fourthSide = cross(secondStart, secondEnd, firstEnd);
      if (((firstSide > tolerance && secondSide < -tolerance) ||
              (firstSide < -tolerance && secondSide > tolerance)) &&
          ((thirdSide > tolerance && fourthSide < -tolerance) ||
              (thirdSide < -tolerance && fourthSide > tolerance))) {
        return true;
      }
      return (firstSide.abs() <= tolerance &&
              onSegment(secondStart, firstStart, firstEnd)) ||
          (secondSide.abs() <= tolerance &&
              onSegment(secondEnd, firstStart, firstEnd)) ||
          (thirdSide.abs() <= tolerance &&
              onSegment(firstStart, secondStart, secondEnd)) ||
          (fourthSide.abs() <= tolerance &&
              onSegment(firstEnd, secondStart, secondEnd));
    }

    for (var first = 0; first < normalized.length; first++) {
      final firstNext = (first + 1) % normalized.length;
      for (var second = first + 1; second < normalized.length; second++) {
        final secondNext = (second + 1) % normalized.length;
        if (firstNext == second) {
          if (onSegment(
                normalized[secondNext],
                normalized[first],
                normalized[firstNext],
              ) ||
              onSegment(
                normalized[first],
                normalized[second],
                normalized[secondNext],
              )) {
            return true;
          }
          continue;
        }
        if (secondNext == first) {
          if (onSegment(
                normalized[firstNext],
                normalized[second],
                normalized[secondNext],
              ) ||
              onSegment(
                normalized[second],
                normalized[first],
                normalized[firstNext],
              )) {
            return true;
          }
          continue;
        }
        if (segmentsIntersect(
          normalized[first],
          normalized[firstNext],
          normalized[second],
          normalized[secondNext],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static Object3D _createFixedLengthSegment(
    Point3D start,
    Point3D directionPoint,
    Point3D lengthPoint, {
    required int color,
  }) {
    final direction = (directionPoint - start).normalized();
    final length = start.distanceTo(lengthPoint);
    return Object3D.line(
      start,
      start + direction * length,
      lineKind: Line3DKind.segment,
      color: color,
    );
  }

  Object3D _createParallelOrPerpendicularLine(
    Point3D anchor,
    Point3D directionStart,
    Point3D directionPoint, {
    required bool perpendicular,
    required int color,
  }) {
    var lineDirection = directionPoint - directionStart;
    if (perpendicular) {
      final planeNormal = _workingPlaneNormal.normalized();
      lineDirection = planeNormal.cross(lineDirection.normalized());
      if (lineDirection.magnitude < 1e-9) {
        lineDirection = _stablePerpendicular(planeNormal);
      } else {
        lineDirection = lineDirection.normalized();
      }
    }
    return Object3D.line(
      anchor,
      anchor + lineDirection,
      lineKind: Line3DKind.line,
      color: color,
    );
  }

  Object3D _createAngleBisector(
    Point3D firstPoint,
    Point3D vertex,
    Point3D secondPoint, {
    required int color,
  }) {
    final first = (firstPoint - vertex).normalized();
    final second = (secondPoint - vertex).normalized();
    var direction = first + second;
    if (direction.magnitude < 1e-9) {
      direction = _workingPlaneNormal.cross(first);
      if (direction.magnitude < 1e-9) {
        direction = _stablePerpendicular(first);
      }
    }
    return Object3D.line(
      vertex,
      vertex + direction.normalized(),
      lineKind: Line3DKind.ray,
      color: color,
    );
  }

  /// Create a preview line or marker showing the current state.
  void _updatePreview() {
    if (_points.length == 1) {
      _previewObject = Object3D.point(_points[0], color: 0x60808080);
    } else if (_points.length >= 2 && _result == null) {
      _previewObject = Object3D.line(
        _points[_points.length - 2],
        _points[_points.length - 1],
        color: 0x60808080,
      );
    } else {
      _previewObject = null;
    }
  }

  // Choose a stable plane even when the input edge is parallel to its normal.
  Vector3D _edgePerpendicular(Vector3D edge) {
    var perpendicular = _workingPlaneNormal.cross(edge).normalized();
    if (perpendicular.magnitude < 1e-9) {
      final fallback = edge.normalized().x.abs() < 0.9
          ? Vector3D.unitX
          : Vector3D.unitY;
      perpendicular = fallback.cross(edge).normalized();
    }
    return perpendicular;
  }

  Object3D _createRegularPolygon(Point3D a, Point3D b) {
    final edge = b - a;
    final inward = _edgePerpendicular(edge);
    final center =
        a.midpoint(b) +
        inward *
            (edge.magnitude / (2 * dart_math.tan(dart_math.pi / polygonSides)));
    final normal = edge.cross(inward).normalized();
    final radial = a - center;
    final tangent = normal.cross(radial);
    return _createPolygon(
      List.generate(polygonSides, (i) {
        final angle = 2 * dart_math.pi * i / polygonSides;
        return center +
            radial * dart_math.cos(angle) +
            tangent * dart_math.sin(angle);
      }),
    );
  }

  Object3D _createTetrahedron(Point3D a, Point3D b) {
    final edge = b - a;
    final inward = _edgePerpendicular(edge);
    final normal = edge.cross(inward).normalized();
    final c = a.midpoint(b) + inward * (edge.magnitude * dart_math.sqrt(3) / 2);
    final baseCenter = a + ((b - a) + (c - a)) * (1 / 3);
    final apex = baseCenter + normal * (edge.magnitude * dart_math.sqrt(2 / 3));
    return Object3D.polyhedron(
      vertices: [a, b, c, apex],
      indices: [0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3],
      color: 0x80FF9800,
    );
  }

  static Object3D _createThreePointCircle(Point3D a, Point3D b, Point3D c) {
    return _createCircle(
      _circumcenter(a, b, c),
      a,
      planeNormal: _triangleUnitNormal(a, b, c),
    );
  }

  /// Create a polygon from a list of vertices.
  static Object3D _createPolygon(List<Point3D> vertices) {
    return Object3D.polyhedron(
      vertices: vertices,
      indices: _triangulatePolygon(vertices),
      color: 0x804CAF50,
      label: 'Polygon',
    );
  }

  /// Triangulate a planar polygon while preserving its boundary, including
  /// concave outlines. Coordinates are normalized before area tests so the
  /// ear-clipping tolerances do not depend on the polygon's position or scale.
  static List<int> _triangulatePolygon(List<Point3D> vertices) {
    List<int> fan() => [
      for (var i = 1; i < vertices.length - 1; i++) ...[0, i, i + 1],
    ];

    if (vertices.length < 3) return fan();

    final origin = vertices.first;
    final offsets = vertices.map((point) => point - origin).toList();
    var scale = 0.0;
    for (final offset in offsets) {
      scale = dart_math
          .max(
            scale,
            dart_math.max(
              offset.x.abs(),
              dart_math.max(offset.y.abs(), offset.z.abs()),
            ),
          )
          .toDouble();
    }
    if (scale == 0 || !scale.isFinite) return fan();

    final normalized = offsets.map((offset) => offset * (1 / scale)).toList();
    var normal = Vector3D.zero;
    for (var i = 0; i < normalized.length; i++) {
      normal =
          normal + normalized[i].cross(normalized[(i + 1) % normalized.length]);
    }
    final dropAxis =
        normal.x.abs() >= normal.y.abs() && normal.x.abs() >= normal.z.abs()
        ? 0
        : normal.y.abs() >= normal.z.abs()
        ? 1
        : 2;
    final projected = normalized.map((point) {
      return switch (dropAxis) {
        0 => (point.y, point.z),
        1 => (point.x, point.z),
        _ => (point.x, point.y),
      };
    }).toList();

    double cross((double, double) a, (double, double) b, (double, double) c) {
      return (b.$1 - a.$1) * (c.$2 - a.$2) - (b.$2 - a.$2) * (c.$1 - a.$1);
    }

    var signedArea = 0.0;
    for (var i = 0; i < projected.length; i++) {
      final current = projected[i];
      final next = projected[(i + 1) % projected.length];
      signedArea += current.$1 * next.$2 - next.$1 * current.$2;
    }
    const areaTolerance = 1e-12;
    if (!signedArea.isFinite || signedArea.abs() <= areaTolerance) {
      return fan();
    }
    final orientation = signedArea > 0 ? 1.0 : -1.0;
    final remaining = List<int>.generate(vertices.length, (index) => index);
    final indices = <int>[];

    bool containsPoint(
      (double, double) point,
      (double, double) a,
      (double, double) b,
      (double, double) c,
    ) {
      return orientation * cross(a, b, point) >= -areaTolerance &&
          orientation * cross(b, c, point) >= -areaTolerance &&
          orientation * cross(c, a, point) >= -areaTolerance;
    }

    while (remaining.length > 3) {
      var earFound = false;
      for (var i = 0; i < remaining.length; i++) {
        final previousIndex =
            remaining[(i - 1 + remaining.length) % remaining.length];
        final currentIndex = remaining[i];
        final nextIndex = remaining[(i + 1) % remaining.length];
        final a = projected[previousIndex];
        final b = projected[currentIndex];
        final c = projected[nextIndex];
        if (orientation * cross(a, b, c) <= areaTolerance) continue;

        var containsOtherVertex = false;
        for (final candidateIndex in remaining) {
          if (candidateIndex == previousIndex ||
              candidateIndex == currentIndex ||
              candidateIndex == nextIndex) {
            continue;
          }
          if (containsPoint(projected[candidateIndex], a, b, c)) {
            containsOtherVertex = true;
            break;
          }
        }
        if (containsOtherVertex) continue;

        indices
          ..add(previousIndex)
          ..add(currentIndex)
          ..add(nextIndex);
        remaining.removeAt(i);
        earFound = true;
        break;
      }
      if (!earFound) {
        var collinearIndex = -1;
        for (var i = 0; i < remaining.length; i++) {
          final previousIndex =
              remaining[(i - 1 + remaining.length) % remaining.length];
          final currentIndex = remaining[i];
          final nextIndex = remaining[(i + 1) % remaining.length];
          final a = projected[previousIndex];
          final b = projected[currentIndex];
          final c = projected[nextIndex];
          final between =
              (b.$1 - a.$1) * (b.$1 - c.$1) + (b.$2 - a.$2) * (b.$2 - c.$2);
          if (cross(a, b, c).abs() <= areaTolerance &&
              between <= areaTolerance) {
            collinearIndex = i;
            break;
          }
        }
        if (collinearIndex < 0) return fan();
        remaining.removeAt(collinearIndex);
      }
    }

    if (orientation *
            cross(
              projected[remaining[0]],
              projected[remaining[1]],
              projected[remaining[2]],
            ) <=
        areaTolerance) {
      return fan();
    }
    indices
      ..add(remaining[0])
      ..add(remaining[1])
      ..add(remaining[2]);
    return indices;
  }

  /// Create a plane through three points.
  static Object3D _createPlane(Point3D a, Point3D b, Point3D c) {
    final normal = _triangleUnitNormal(a, b, c);

    // Plane equation: normal · (x, y, z) = normal · a
    final d = normal.x * a.x + normal.y * a.y + normal.z * a.z;

    return Object3D.plane(
      a: normal.x,
      b: normal.y,
      c: normal.z,
      d: d,
      color: 0x402196F3,
      label: 'Plane',
    );
  }

  /// Create a circle from center and a point on the circle.
  static Object3D _createCircle(
    Point3D center,
    Point3D onCircle, {
    Vector3D? planeNormal,
    int color = 0xFF2196F3,
  }) {
    final radius = center.distanceTo(onCircle);
    // Generate circle vertices as a polyline
    final segments = 32;
    final points = <Point3D>[];
    // Direction from center to onCircle
    final dir = (onCircle - center).normalized();
    var perp = (planeNormal ?? Vector3D.unitZ).cross(dir).normalized();
    if (perp.magnitude < 1e-9) {
      perp = _stablePerpendicular(dir);
    }

    for (int i = 0; i <= segments; i++) {
      final theta = 2 * dart_math.pi * i / segments;
      final x =
          center.x +
          radius *
              (dart_math.cos(theta) * dir.x + dart_math.sin(theta) * perp.x);
      final y =
          center.y +
          radius *
              (dart_math.cos(theta) * dir.y + dart_math.sin(theta) * perp.y);
      final z =
          center.z +
          radius *
              (dart_math.cos(theta) * dir.z + dart_math.sin(theta) * perp.z);
      points.add(Point3D(x, y, z));
    }

    return Object3D.curve(
      points: points,
      conic: _circleConic(center, dir, perp, radius),
      color: color,
      label: 'Circle',
    );
  }

  static Conic3D _circleConic(
    Point3D center,
    Vector3D axisU,
    Vector3D axisV,
    double radius,
  ) => Conic3D(
    origin: center,
    axisU: axisU,
    axisV: axisV,
    quadraticX: 1,
    quadraticXY: 0,
    quadraticY: 1,
    linearX: 0,
    linearY: 0,
    constant: -radius * radius,
  );

  /// Create a cube from two base edge points.
  static Object3D _createCube(
    Point3D a,
    Point3D b, {
    Vector3D planeNormal = Vector3D.unitZ,
  }) {
    final edge = b - a;
    final height = edge.magnitude;

    // Build the 8 vertices of the cube
    final vx = edge.normalized();
    final up = planeNormal.normalized();
    var vz = up.cross(vx).normalized();
    if (vz.magnitude < 0.1) {
      vz = _stablePerpendicular(vx);
    }
    final vy = vz.cross(vx).normalized();

    final verts = <Point3D>[
      a,
      b,
      b + vz * height,
      a + vz * height,
      a + vy * height,
      b + vy * height,
      b + vy * height + vz * height,
      a + vy * height + vz * height,
    ];

    final indices = [
      // Bottom
      0, 1, 2, 0, 2, 3,
      // Top
      4, 6, 5, 4, 7, 6,
      // Front
      0, 4, 5, 0, 5, 1,
      // Back
      3, 2, 6, 3, 6, 7,
      // Left
      0, 3, 7, 0, 7, 4,
      // Right
      1, 5, 6, 1, 6, 2,
    ];

    return Object3D.polyhedron(
      vertices: verts,
      indices: indices,
      color: 0x80FF9800,
      label: 'Cube',
    );
  }

  static Object3D _createTriangularPrism(
    Point3D a,
    Point3D b,
    Point3D c,
    Point3D heightPoint,
  ) {
    final normal = _triangleUnitNormal(a, b, c);
    final height = (heightPoint - a).dot(normal);
    final offset = normal * height;
    final vertices = <Point3D>[a, b, c, a + offset, b + offset, c + offset];
    final indices = <int>[
      0,
      2,
      1,
      3,
      4,
      5,
      0,
      1,
      4,
      0,
      4,
      3,
      1,
      2,
      5,
      1,
      5,
      4,
      2,
      0,
      3,
      2,
      3,
      5,
    ];
    if (height < 0) {
      for (var i = 0; i < indices.length; i += 3) {
        final second = indices[i + 1];
        indices[i + 1] = indices[i + 2];
        indices[i + 2] = second;
      }
    }
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: 0x80FF9800,
      label: 'Prism',
    );
  }

  static Object3D _createPyramid(
    Point3D a,
    Point3D b,
    Point3D c,
    Point3D apex,
  ) {
    final indices = [0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3];
    final signedHeight = (apex - a).dot(_triangleUnitNormal(a, b, c));
    if (signedHeight < 0) {
      for (var i = 0; i < indices.length; i += 3) {
        final second = indices[i + 1];
        indices[i + 1] = indices[i + 2];
        indices[i + 2] = second;
      }
    }
    return Object3D.polyhedron(
      vertices: [a, b, c, apex],
      indices: indices,
      color: 0x80FF9800,
      label: 'Pyramid',
    );
  }

  static Object3D _createCone(
    Point3D center,
    Point3D radiusPoint,
    Point3D apex,
  ) {
    final axis = (apex - center).normalized();
    final rawRadius = radiusPoint - center;
    final radial = rawRadius - axis * rawRadius.dot(axis);
    final radius = radial.magnitude;
    final u = radial.normalized();
    final v = axis.cross(u).normalized();
    const segments = 24;
    final vertices = <Point3D>[center];
    for (var i = 0; i < segments; i++) {
      final angle = 2 * dart_math.pi * i / segments;
      final direction = u * dart_math.cos(angle) + v * dart_math.sin(angle);
      vertices.add(center + direction * radius);
    }
    final apexIndex = vertices.length;
    vertices.add(apex);
    final indices = <int>[];
    for (var i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      indices.addAll([0, next + 1, i + 1]);
      indices.addAll([i + 1, next + 1, apexIndex]);
    }
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: 0x80FF9800,
      label: 'Cone',
    );
  }

  static Object3D _createCylinder(
    Point3D center,
    Point3D radiusPoint,
    Point3D topCenter,
  ) {
    final axis = (topCenter - center).normalized();
    final rawRadius = radiusPoint - center;
    final radial = rawRadius - axis * rawRadius.dot(axis);
    final radius = radial.magnitude;
    final u = radial.normalized();
    final v = axis.cross(u).normalized();
    const segments = 24;
    final vertices = <Point3D>[center, topCenter];
    for (var i = 0; i < segments; i++) {
      final angle = 2 * dart_math.pi * i / segments;
      final direction = u * dart_math.cos(angle) + v * dart_math.sin(angle);
      vertices.add(center + direction * radius);
    }
    final topRingStart = vertices.length;
    for (var i = 0; i < segments; i++) {
      final angle = 2 * dart_math.pi * i / segments;
      final direction = u * dart_math.cos(angle) + v * dart_math.sin(angle);
      vertices.add(topCenter + direction * radius);
    }
    final indices = <int>[];
    for (var i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      final bottom = i + 2;
      final nextBottom = next + 2;
      final top = topRingStart + i;
      final nextTop = topRingStart + next;
      indices.addAll([0, nextBottom, bottom]);
      indices.addAll([1, top, nextTop]);
      indices.addAll([bottom, nextBottom, nextTop, bottom, nextTop, top]);
    }
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: 0x80FF9800,
      label: 'Cylinder',
    );
  }

  static bool _hasRoundSolidGeometry(
    Point3D center,
    Point3D radiusPoint,
    Point3D topPoint,
  ) {
    final axis = topPoint - center;
    if (axis.magnitude < 1e-9) return false;
    final axisUnit = axis.normalized();
    final radial = radiusPoint - center;
    return (radial - axisUnit * radial.dot(axisUnit)).magnitude >= 1e-9;
  }

  static Object3D _createPlaneFromNormal(Point3D point, Vector3D normal) {
    final unit = _stableNormalize(normal);
    if (unit.magnitude < 1e-9) return Object3D.point(point);
    return Object3D.plane(
      a: unit.x,
      b: unit.y,
      c: unit.z,
      d: unit.dot(point.toVector()),
      color: 0x402196F3,
      label: 'Plane',
    );
  }

  Object3D _createArc(Point3D center, Point3D start, Point3D end) {
    final startVector = start - center;
    final endVector = end - center;
    final radius = startVector.magnitude;
    final u = startVector.normalized();
    var normal = _stableNormalize(u.cross(endVector.normalized()));
    if (normal.magnitude == 0) {
      final workingNormal = _workingPlaneNormal.normalized();
      normal = workingNormal.cross(u).magnitude < 1e-9
          ? _stablePerpendicular(u)
          : workingNormal;
    }
    final v = normal.cross(u).normalized();
    final angle = dart_math.atan2(endVector.dot(v), endVector.dot(u));
    final sweep = angle <= 0 ? angle + 2 * dart_math.pi : angle;
    final points = List.generate(49, (i) {
      final theta = sweep * i / 48;
      return center +
          u * (radius * dart_math.cos(theta)) +
          v * (radius * dart_math.sin(theta));
    });
    return Object3D.curve(
      points: points,
      conic: _circleConic(center, u, v, radius),
      color: 0xFF2196F3,
    );
  }

  Point3D? _projectArcEndpoint(Point3D center, Point3D start, Point3D end) {
    final radius = center.distanceTo(start);
    final direction = end - center;
    if (radius < 1e-9 || direction.magnitude < 1e-9) return null;
    return center + direction.normalized() * radius;
  }

  static Point3D _circumcenter(Point3D a, Point3D b, Point3D c) {
    if (!_isNonCollinear(a, b, c)) return a;
    final edgeU = b - a;
    final edgeV = c - a;
    final unitU = _stableNormalize(edgeU);
    final unitV = _stableNormalize(edgeV);
    final normal = _stableNormalize(unitU.cross(unitV));
    final perpendicular = normal.cross(unitU);
    final halfU = (edgeU * 0.5).dot(unitU);
    final halfV = edgeV * 0.5;
    final parallel = halfV.dot(unitU);
    final across = halfV.dot(perpendicular);
    final difference = parallel - halfU;
    final perpendicularOffset = difference == 0
        ? across
        : across + (parallel / across) * difference;
    final offset = unitU * halfU + perpendicular * perpendicularOffset;
    return a + offset;
  }

  static bool _isNonCollinear(Point3D a, Point3D b, Point3D c) {
    final u = b - a;
    final v = c - a;
    if (u.magnitude < 1e-9 || v.magnitude < 1e-9) return false;
    return _stableNormalize(u).cross(_stableNormalize(v)).magnitude >= 1e-9;
  }

  static Vector3D _triangleUnitNormal(Point3D a, Point3D b, Point3D c) {
    return _stableNormalize(
      _stableNormalize(b - a).cross(_stableNormalize(c - a)),
    );
  }

  static Vector3D _stableNormalize(Vector3D vector) {
    final scale = dart_math
        .max(vector.x.abs(), dart_math.max(vector.y.abs(), vector.z.abs()))
        .toDouble();
    if (scale == 0 || !scale.isFinite) return Vector3D.zero;
    final scaled = Vector3D(
      vector.x / scale,
      vector.y / scale,
      vector.z / scale,
    );
    final magnitude = scaled.magnitude;
    if (magnitude == 0 || !magnitude.isFinite) return Vector3D.zero;
    return Vector3D(
      scaled.x / magnitude,
      scaled.y / magnitude,
      scaled.z / magnitude,
    );
  }

  Object3D _createCircumcircleArc(Point3D a, Point3D b, Point3D c) {
    final center = _circumcenter(a, b, c);
    final normal = _triangleUnitNormal(a, b, c);
    final u = (a - center).normalized();
    final v = normal.cross(u).normalized();
    double angleFor(Point3D point) {
      final radial = point - center;
      var angle = dart_math.atan2(radial.dot(v), radial.dot(u));
      if (angle < 0) angle += 2 * dart_math.pi;
      return angle;
    }

    final middleAngle = angleFor(b);
    final endAngle = angleFor(c);
    final sweep = middleAngle <= endAngle
        ? endAngle
        : endAngle - 2 * dart_math.pi;
    final radius = center.distanceTo(a);
    final points = List.generate(49, (i) {
      final theta = sweep * i / 48;
      return center +
          u * (radius * dart_math.cos(theta)) +
          v * (radius * dart_math.sin(theta));
    });
    return Object3D.curve(
      points: points,
      conic: _circleConic(center, u, v, radius),
      color: 0xFF2196F3,
    );
  }

  Object3D _createSector(Point3D center, Point3D start, Point3D end) {
    final arc = _createArc(center, start, end).vertices;
    final vertices = [center, ...arc];
    final indices = <int>[];
    for (var i = 1; i < vertices.length - 1; i++) {
      indices.addAll([0, i, i + 1]);
    }
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: 0x804CAF50,
      label: 'Sector',
    );
  }

  Object3D _createCircumcircleSector(Point3D a, Point3D b, Point3D c) {
    final center = _circumcenter(a, b, c);
    final arc = _createCircumcircleArc(a, b, c).vertices;
    final vertices = [center, ...arc];
    final indices = <int>[];
    for (var i = 1; i < vertices.length - 1; i++) {
      indices.addAll([0, i, i + 1]);
    }
    return Object3D.polyhedron(
      vertices: vertices,
      indices: indices,
      color: 0x804CAF50,
      label: 'Sector',
    );
  }

  Object3D _createEllipse(
    Point3D center,
    Point3D majorPoint,
    Point3D minorPoint,
  ) {
    final major = majorPoint - center;
    final majorUnit = major.normalized();
    final minorRaw = minorPoint - center;
    final minor = minorRaw - majorUnit * minorRaw.dot(majorUnit);
    final b = minor.magnitude;
    final minorUnit = minor.normalized();
    final points = List.generate(97, (i) {
      final theta = 2 * dart_math.pi * i / 96;
      return center +
          major * dart_math.cos(theta) +
          minorUnit * (b * dart_math.sin(theta));
    });
    return Object3D.curve(
      points: points,
      conic: Conic3D(
        origin: center,
        axisU: majorUnit,
        axisV: minorUnit,
        quadraticX: 1 / (major.magnitude * major.magnitude),
        quadraticXY: 0,
        quadraticY: 1 / (b * b),
        linearX: 0,
        linearY: 0,
        constant: -1,
      ),
      color: 0xFF2196F3,
    );
  }

  static ({Point3D origin, Vector3D u, Vector3D v, Vector3D normal})?
  _conicPlane(List<Point3D> points) {
    if (points.length < 3) return null;
    final anchor = points.first;
    var u = Vector3D.zero;
    var normal = Vector3D.zero;
    for (var i = 1; i < points.length && normal.magnitude < 1e-9; i++) {
      final firstEdge = points[i] - anchor;
      final firstDirection = firstEdge.normalized();
      if (firstDirection.magnitude < 1e-9) continue;
      for (var j = i + 1; j < points.length; j++) {
        final secondDirection = (points[j] - anchor).normalized();
        if (secondDirection.magnitude < 1e-9) continue;
        final candidate = firstDirection.cross(secondDirection);
        if (candidate.magnitude >= 1e-9) {
          u = firstDirection;
          normal = candidate.normalized();
          break;
        }
      }
    }
    if (normal.magnitude < 1e-9) return null;
    final extent = points.fold<double>(
      0,
      (maximum, point) =>
          dart_math.max(maximum, anchor.distanceTo(point)).toDouble(),
    );
    final coordinateScale = points.fold<double>(0, (maximum, point) {
      return dart_math
          .max(
            maximum,
            dart_math.max(
              point.x.abs(),
              dart_math.max(point.y.abs(), point.z.abs()),
            ),
          )
          .toDouble();
    });
    const machineEpsilon = 2.220446049250313e-16;
    final floatingPointTolerance = coordinateScale * machineEpsilon * 8;
    // Reject inputs whose coordinate precision cannot resolve the local plane.
    if (!extent.isFinite ||
        !floatingPointTolerance.isFinite ||
        floatingPointTolerance > extent * 1e-4) {
      return null;
    }
    final tolerance = dart_math.max(extent * 1e-7, floatingPointTolerance);
    if (points.any((point) => (point - anchor).dot(normal).abs() > tolerance)) {
      return null;
    }
    final v = normal.cross(u).normalized();
    return (origin: _centroid(points), u: u, v: v, normal: normal);
  }

  Object3D? _createConic(List<Point3D> points) {
    final plane = _conicPlane(points);
    if (plane == null) return null;
    final origin = plane.origin;
    final u = plane.u;
    final v = plane.v;
    final coordinates = points.map((point) {
      final delta = point - origin;
      return [delta.dot(u), delta.dot(v)];
    }).toList();
    final coordinateScale = coordinates.fold<double>(0, (maximum, point) {
      return dart_math
          .max(maximum, dart_math.max(point[0].abs(), point[1].abs()))
          .toDouble();
    });
    if (coordinateScale < 1e-15) return null;
    final matrix = coordinates.map((p) {
      final x = p[0] / coordinateScale;
      final y = p[1] / coordinateScale;
      return [x * x, x * y, y * y, x, y, 1.0];
    }).toList();
    final normalizedCoefficients = _nullSpaceVector(matrix);
    if (normalizedCoefficients == null) return null;
    final scaleSquared = coordinateScale * coordinateScale;
    final coefficients = [
      normalizedCoefficients[0] / scaleSquared,
      normalizedCoefficients[1] / scaleSquared,
      normalizedCoefficients[2] / scaleSquared,
      normalizedCoefficients[3] / coordinateScale,
      normalizedCoefficients[4] / coordinateScale,
      normalizedCoefficients[5],
    ];
    if (coefficients.any((coefficient) => !coefficient.isFinite)) return null;
    final a = normalizedCoefficients[0];
    final b = normalizedCoefficients[1];
    final c = normalizedCoefficients[2];
    final d = normalizedCoefficients[3];
    final e = normalizedCoefficients[4];
    final f = normalizedCoefficients[5];
    // A zero determinant of the homogeneous conic matrix describes a pair of
    // lines, a point, or another degenerate quadratic rather than one conic.
    final determinantTerms = [
      4 * a * c * f,
      -a * e * e,
      -c * d * d,
      -b * b * f,
      b * d * e,
    ];
    final conicDeterminant = determinantTerms.fold<double>(
      0,
      (sum, term) => sum + term,
    );
    final determinantScale = determinantTerms.fold<double>(
      0,
      (sum, term) => sum + term.abs(),
    );
    const determinantPrecision = 64 * 2.220446049250313e-16;
    if (!conicDeterminant.isFinite ||
        determinantScale == 0 ||
        conicDeterminant.abs() <= determinantScale * determinantPrecision) {
      return null;
    }

    final samples = <Point3D>[];
    final curveStarts = <int>[];
    final coefficientScale = normalizedCoefficients.take(3).fold<double>(0, (
      maximum,
      coefficient,
    ) {
      return dart_math.max(maximum, coefficient.abs()).toDouble();
    });
    final quadraticDiscriminant = coefficientScale == 0
        ? 0.0
        : (normalizedCoefficients[1] / coefficientScale) *
                  (normalizedCoefficients[1] / coefficientScale) -
              4 *
                  (normalizedCoefficients[0] / coefficientScale) *
                  (normalizedCoefficients[2] / coefficientScale);
    // A positive discriminant means an indefinite quadratic form. Avoid a
    // fixed tolerance here so very elongated hyperbolas keep both branches.
    final isHyperbola = quadraticDiscriminant > 0;
    final isParabola =
        !isHyperbola &&
        quadraticDiscriminant.abs() <= 8 * 2.220446049250313e-16;
    final hyperbolaPaths = List.generate(2, (_) => <List<Point3D>>[]);
    final activeHyperbolaPaths = List<List<Point3D>?>.filled(2, null);
    double? previousScaledRadius;
    int? previousRootIndex;
    int? rootAfterAsymptote;
    final coefficientMagnitude = normalizedCoefficients.fold<double>(
      0,
      (maximum, coefficient) =>
          dart_math.max(maximum, coefficient.abs()).toDouble(),
    );
    const coefficientPrecision = 32 * 2.220446049250313e-16;
    final originOnConic =
        normalizedCoefficients[5].abs() <=
        coefficientMagnitude * coefficientPrecision;

    double radialDiscriminantAt(double theta) {
      final cosine = dart_math.cos(theta);
      final sine = dart_math.sin(theta);
      final quadratic =
          normalizedCoefficients[0] * cosine * cosine +
          normalizedCoefficients[1] * cosine * sine +
          normalizedCoefficients[2] * sine * sine;
      final linear =
          normalizedCoefficients[3] * cosine + normalizedCoefficients[4] * sine;
      return linear * linear - 4 * quadratic * normalizedCoefficients[5];
    }

    final sampleAngles = <double>{};
    final baseSampleCount = isHyperbola ? 90 : 180;
    final sampleSpan = isHyperbola ? dart_math.pi : 2 * dart_math.pi;
    for (var i = 0; i <= baseSampleCount; i++) {
      sampleAngles.add(sampleSpan * i / baseSampleCount);
    }
    // Include the null direction of a parabolic quadratic form so a root
    // diverging between regular samples can be separated from its finite peer.
    if (isParabola) {
      final phase = dart_math.atan2(b, a - c);
      final mean = (a + c) / 2;
      var boundary = (phase + (mean >= 0 ? dart_math.pi : 0)) / 2;
      boundary %= dart_math.pi;
      if (boundary < 0) boundary += dart_math.pi;
      sampleAngles.add(boundary);
      sampleAngles.add(boundary + dart_math.pi);
    }
    if (isHyperbola) {
      // Close the diverging root's path at each radial asymptote.
      final quadraticMean =
          (normalizedCoefficients[0] + normalizedCoefficients[2]) / 2;
      final quadraticCosine =
          (normalizedCoefficients[0] - normalizedCoefficients[2]) / 2;
      final quadraticSine = normalizedCoefficients[1] / 2;
      final quadraticAmplitude = dart_math.sqrt(
        quadraticCosine * quadraticCosine + quadraticSine * quadraticSine,
      );
      if (quadraticAmplitude > 0 && quadraticAmplitude.isFinite) {
        final crossing = -quadraticMean / quadraticAmplitude;
        if (crossing >= -1 && crossing <= 1) {
          final phase = dart_math.atan2(quadraticSine, quadraticCosine);
          final offset = dart_math.acos(crossing);
          for (final sign in [-1.0, 1.0]) {
            var boundary = (phase + sign * offset) / 2;
            boundary %= dart_math.pi;
            if (boundary < 0) boundary += dart_math.pi;
            sampleAngles.add(boundary);
          }
        }
      }

      final constant = normalizedCoefficients[5];
      final discriminantX =
          normalizedCoefficients[3] * normalizedCoefficients[3] -
          4 * constant * normalizedCoefficients[0];
      final discriminantXY =
          2 * normalizedCoefficients[3] * normalizedCoefficients[4] -
          4 * constant * normalizedCoefficients[1];
      final discriminantY =
          normalizedCoefficients[4] * normalizedCoefficients[4] -
          4 * constant * normalizedCoefficients[2];
      final mean = (discriminantX + discriminantY) / 2;
      final cosineCoefficient = (discriminantX - discriminantY) / 2;
      final sineCoefficient = discriminantXY / 2;
      final amplitude = dart_math.sqrt(
        cosineCoefficient * cosineCoefficient +
            sineCoefficient * sineCoefficient,
      );
      if (amplitude > 0 && amplitude.isFinite) {
        final crossing = -mean / amplitude;
        if (crossing >= -1 && crossing <= 1) {
          final phase = dart_math.atan2(sineCoefficient, cosineCoefficient);
          final offset = dart_math.acos(crossing);
          final boundaries = <double>{};
          for (final sign in [-1.0, 1.0]) {
            var boundary = (phase + sign * offset) / 2;
            boundary %= dart_math.pi;
            if (boundary < 0) boundary += dart_math.pi;
            boundaries.add(boundary);
          }
          final orderedBoundaries = boundaries.toList()..sort();
          for (var i = 0; i < orderedBoundaries.length; i++) {
            final start = orderedBoundaries[i];
            var end = orderedBoundaries[(i + 1) % orderedBoundaries.length];
            if (end <= start) end += dart_math.pi;
            final midpoint = (start + end) / 2;
            if (radialDiscriminantAt(midpoint) <= 0) {
              sampleAngles.add(midpoint % dart_math.pi);
              continue;
            }
            const subdivisions = 32;
            for (var step = 0; step <= subdivisions; step++) {
              var angle = start + (end - start) * step / subdivisions;
              angle %= dart_math.pi;
              if (angle < 0) angle += dart_math.pi;
              sampleAngles.add(angle);
            }
          }
        }
      }
    }
    final orderedSampleAngles = sampleAngles.toList()..sort();
    for (final theta in orderedSampleAngles) {
      final cosine = dart_math.cos(theta);
      final sine = dart_math.sin(theta);
      final quadraticTerms = [
        normalizedCoefficients[0] * cosine * cosine,
        normalizedCoefficients[1] * cosine * sine,
        normalizedCoefficients[2] * sine * sine,
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
        normalizedCoefficients[3] * cosine,
        normalizedCoefficients[4] * sine,
      ];
      final linear = linearTerms.fold<double>(0, (sum, term) => sum + term);
      final linearScale = linearTerms.fold<double>(
        0,
        (sum, term) => sum + term.abs(),
      );
      final constant = normalizedCoefficients[5];
      final candidates = <({int index, double radius})>[];
      final quadraticIsNearZero =
          quadraticScale == 0 ||
          quadratic.abs() <=
              (isParabola ? coefficientScale : quadraticScale) * 1e-12;
      if (originOnConic && isHyperbola) {
        // With a zero constant, the root at radius zero is present at every
        // angle. Follow only the other root, keeping its identity through the
        // tangent direction where that root itself passes through the origin.
        if (!quadraticIsNearZero) {
          candidates.add((index: 0, radius: -linear / quadratic));
        }
      } else if (quadraticIsNearZero) {
        if (linearScale > 0 && linear.abs() > linearScale * 1e-12) {
          final candidate = -constant / linear;
          if (!originOnConic || candidate.abs() > 1e-10) {
            // Preserve the index of the quadratic root with this finite limit.
            candidates.add((index: linear > 0 ? 0 : 1, radius: candidate));
          }
        }
      } else {
        final discriminant = linear * linear - 4 * quadratic * constant;
        if (discriminant >= 0) {
          final root = dart_math.sqrt(discriminant);
          final stableNumerator =
              -0.5 * (linear + (linear >= 0 ? root : -root));
          final stableRoot = stableNumerator == 0
              ? -linear / (2 * quadratic)
              : stableNumerator / quadratic;
          final complementaryRoot = stableNumerator == 0
              ? stableRoot
              : constant / stableNumerator;
          final roots = linear >= 0
              ? [
                  (index: 0, radius: complementaryRoot),
                  (index: 1, radius: stableRoot),
                ]
              : [
                  (index: 0, radius: stableRoot),
                  (index: 1, radius: complementaryRoot),
                ];
          final quadraticRoots = roots
              .where(
                (candidate) => !originOnConic || candidate.radius.abs() > 1e-10,
              )
              .toList();
          candidates.addAll(quadraticRoots);
        }
      }
      if (isHyperbola) {
        for (var rootIndex = 0; rootIndex < 2; rootIndex++) {
          final candidateIndex = candidates.indexWhere(
            (candidate) => candidate.index == rootIndex,
          );
          if (candidateIndex == -1) {
            activeHyperbolaPaths[rootIndex] = null;
            continue;
          }
          final candidate = candidates[candidateIndex];
          final radius = candidate.radius * coordinateScale;
          if (!candidate.radius.isFinite || !radius.isFinite) {
            activeHyperbolaPaths[rootIndex] = null;
            continue;
          }
          var path = activeHyperbolaPaths[rootIndex];
          if (path == null) {
            path = <Point3D>[];
            hyperbolaPaths[rootIndex].add(path);
            activeHyperbolaPaths[rootIndex] = path;
          }
          path.add(origin + u * (radius * cosine) + v * (radius * sine));
        }
        continue;
      }

      double? scaledRadius;
      if (!quadraticIsNearZero && rootAfterAsymptote != null) {
        previousRootIndex = rootAfterAsymptote;
        rootAfterAsymptote = null;
        previousScaledRadius = null;
      }
      if (candidates.isNotEmpty) {
        final matchingIndex = candidates.indexWhere(
          (candidate) => candidate.index == previousRootIndex,
        );
        final selected = matchingIndex < 0
            ? candidates.first
            : candidates[matchingIndex];
        if (previousRootIndex != null && matchingIndex < 0) {
          if (isParabola && quadraticIsNearZero) {
            rootAfterAsymptote = previousRootIndex;
          }
          previousScaledRadius = null;
        }
        previousRootIndex = selected.index;
        scaledRadius = selected.radius;
      }
      if (scaledRadius == null || !scaledRadius.isFinite) {
        previousScaledRadius = null;
        previousRootIndex = null;
        continue;
      }
      final startsNewBranch =
          samples.isNotEmpty && previousScaledRadius == null;
      final radius = scaledRadius * coordinateScale;
      if (!radius.isFinite) {
        previousScaledRadius = null;
        previousRootIndex = null;
        continue;
      }
      if (startsNewBranch) curveStarts.add(samples.length);
      previousScaledRadius = scaledRadius;
      samples.add(origin + u * (radius * cosine) + v * (radius * sine));
    }
    if (isHyperbola) {
      for (final rootPaths in hyperbolaPaths) {
        for (final path in rootPaths) {
          if (path.length < 2) continue;
          if (samples.isNotEmpty) curveStarts.add(samples.length);
          samples.addAll(path);
        }
      }
    }
    if (samples.length < 2) return null;
    return Object3D.curve(
      points: samples,
      curveStarts: curveStarts,
      conic: Conic3D(
        origin: origin,
        axisU: u,
        axisV: v,
        quadraticX: coefficients[0],
        quadraticXY: coefficients[1],
        quadraticY: coefficients[2],
        linearX: coefficients[3],
        linearY: coefficients[4],
        constant: coefficients[5],
      ),
      color: 0xFF2196F3,
      label: 'Conic',
    );
  }

  List<double>? _nullSpaceVector(List<List<double>> source) {
    final matrix = source.map((row) => List<double>.from(row)).toList();
    final pivotColumns = <int>[];
    var pivotRow = 0;
    for (var column = 0; column < 6 && pivotRow < matrix.length; column++) {
      var best = pivotRow;
      for (var row = pivotRow + 1; row < matrix.length; row++) {
        if (matrix[row][column].abs() > matrix[best][column].abs()) best = row;
      }
      if (matrix[best][column].abs() < 1e-10) continue;
      final swap = matrix[pivotRow];
      matrix[pivotRow] = matrix[best];
      matrix[best] = swap;
      final divisor = matrix[pivotRow][column];
      for (var j = column; j < 6; j++) matrix[pivotRow][j] /= divisor;
      for (var row = 0; row < matrix.length; row++) {
        if (row == pivotRow) continue;
        final factor = matrix[row][column];
        for (var j = column; j < 6; j++) {
          matrix[row][j] -= factor * matrix[pivotRow][j];
        }
      }
      pivotColumns.add(column);
      pivotRow++;
    }
    if (pivotRow < 5) return null;
    final freeColumn = List.generate(
      6,
      (i) => i,
    ).firstWhere((column) => !pivotColumns.contains(column));
    final solution = List<double>.filled(6, 0)..[freeColumn] = 1;
    for (var row = pivotColumns.length - 1; row >= 0; row--) {
      final column = pivotColumns[row];
      var value = 0.0;
      for (var j = 0; j < 6; j++) {
        if (j != column) value += matrix[row][j] * solution[j];
      }
      solution[column] = -value;
    }
    return solution.every((value) => value.isFinite) ? solution : null;
  }

  Object3D _createParabola(
    Point3D focus,
    Point3D directrixA,
    Point3D directrixB,
  ) {
    final directrix = directrixB - directrixA;
    final lengthSquared = directrix.dot(directrix);
    if (directrix.magnitude < 1e-9)
      return Object3D.curve(points: [focus, directrixA]);
    final t = (focus - directrixA).dot(directrix) / lengthSquared;
    final foot = directrixA + directrix * t;
    final normal = (focus - foot).normalized();
    final axis = directrix.normalized();
    final p = focus.distanceTo(foot) / 2;
    if (p <= 0 || !p.isFinite) {
      return Object3D.curve(points: [focus, directrixA]);
    }
    final vertex = foot + normal * p;
    final range = p * 6;
    final samples = List.generate(97, (i) {
      final y = -range + 2 * range * i / 96;
      final x = y * y / (4 * p);
      return vertex + normal * x + axis * y;
    });
    return Object3D.curve(
      points: samples,
      conic: Conic3D(
        origin: vertex,
        axisU: normal,
        axisV: axis,
        quadraticX: 0,
        quadraticXY: 0,
        quadraticY: -1 / (4 * p),
        linearX: 1,
        linearY: 0,
        constant: 0,
      ),
      color: 0xFF2196F3,
    );
  }

  Object3D _createHyperbola(
    Point3D center,
    Point3D realPoint,
    Point3D otherPoint,
  ) {
    final real = realPoint - center;
    final realUnit = real.normalized();
    final other = otherPoint - center;
    final transverse = other - realUnit * other.dot(realUnit);
    final a = real.magnitude;
    final b = transverse.magnitude;
    final transverseUnit = transverse.normalized();
    final samples = <Point3D>[];
    final curveStarts = <int>[];
    for (final sign in [1.0, -1.0]) {
      if (samples.isNotEmpty) curveStarts.add(samples.length);
      for (var i = 0; i <= 96; i++) {
        final t = -2.4 + 4.8 * i / 96;
        final positiveExponential = dart_math.exp(t);
        final negativeExponential = dart_math.exp(-t);
        final hyperbolicCosine =
            (positiveExponential + negativeExponential) / 2;
        final hyperbolicSine = (positiveExponential - negativeExponential) / 2;
        samples.add(
          center +
              realUnit * (sign * a * hyperbolicCosine) +
              transverseUnit * (b * hyperbolicSine),
        );
      }
    }
    return Object3D.curve(
      points: samples,
      curveStarts: curveStarts,
      conic: Conic3D(
        origin: center,
        axisU: realUnit,
        axisV: transverseUnit,
        quadraticX: 1 / (a * a),
        quadraticXY: 0,
        quadraticY: -1 / (b * b),
        linearX: 0,
        linearY: 0,
        constant: -1,
      ),
      color: 0xFF2196F3,
      label: 'Hyperbola',
    );
  }

  Object3D _createSurfaceOfRevolution(
    Point3D axisStart,
    Point3D axisEnd,
    Point3D profileStart,
    Point3D profileEnd,
  ) {
    final axis = (axisEnd - axisStart).normalized();
    if (axis.magnitude < 1e-9) {
      return Object3D.curve(points: [profileStart, profileEnd]);
    }
    const rings = 16;
    const segments = 32;
    final vertices = <Point3D>[];
    for (var ring = 0; ring <= rings; ring++) {
      final t = ring / rings;
      final profile = profileStart + (profileEnd - profileStart) * t;
      final relative = profile - axisStart;
      final axial = relative.dot(axis);
      final radial = relative - axis * axial;
      final perpendicular = axis.cross(radial).normalized() * radial.magnitude;
      for (var segment = 0; segment < segments; segment++) {
        final theta = 2 * dart_math.pi * segment / segments;
        vertices.add(
          axisStart +
              axis * axial +
              radial * dart_math.cos(theta) +
              perpendicular * dart_math.sin(theta),
        );
      }
    }
    final indices = <int>[];
    for (var ring = 0; ring < rings; ring++) {
      for (var segment = 0; segment < segments; segment++) {
        final next = (segment + 1) % segments;
        final a = ring * segments + segment;
        final b = ring * segments + next;
        final c = (ring + 1) * segments + next;
        final d = (ring + 1) * segments + segment;
        indices.addAll([a, b, c, a, c, d]);
      }
    }
    return Object3D.surface(
      vertices: vertices,
      indices: indices,
      color: 0x804CAF50,
      label: 'Surface of revolution',
    );
  }

  static double _polygonArea(List<Point3D> points) {
    final origin = points.first.toVector();
    var sum = Vector3D.zero;
    for (var i = 0; i < points.length; i++) {
      final start = points[i].toVector() - origin;
      final end = points[(i + 1) % points.length].toVector() - origin;
      sum = sum + start.cross(end);
    }
    return sum.magnitude / 2;
  }

  double _closureTolerance() => 1e-9;

  bool _hasThreeDistinctVertices() {
    final distinctVertices = <Point3D>[];
    for (final point in _points) {
      if (distinctVertices.every((other) => other.distanceTo(point) >= 1e-9)) {
        distinctVertices.add(point);
        if (distinctVertices.length == 3) return true;
      }
    }
    return false;
  }

  static Point3D _centroid(List<Point3D> points) {
    if (points.isEmpty) return Point3D.origin;
    final anchor = points.first;
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    for (final point in points) {
      x += point.x - anchor.x;
      y += point.y - anchor.y;
      z += point.z - anchor.z;
    }
    return Point3D(
      anchor.x + x / points.length,
      anchor.y + y / points.length,
      anchor.z + z / points.length,
    );
  }

  static Point3D _polygonInteriorPoint(List<Point3D> points) {
    final plane = _conicPlane(points);
    if (plane == null) return _centroid(points);

    final coordinates = points.map((point) {
      final relative = point - plane.origin;
      return [relative.dot(plane.u), relative.dot(plane.v)];
    }).toList();
    var centerX = 0.0;
    var centerY = 0.0;
    for (final coordinate in coordinates) {
      centerX += coordinate[0];
      centerY += coordinate[1];
    }
    centerX /= coordinates.length;
    centerY /= coordinates.length;
    if (_containsPoint2D(centerX, centerY, coordinates)) {
      return plane.origin + plane.u * centerX + plane.v * centerY;
    }

    var interiorX = centerX;
    var interiorY = centerY;
    var widestInterior = 0.0;
    final levels = coordinates.map((point) => point[1]).toSet().toList()
      ..sort();
    for (var levelIndex = 1; levelIndex < levels.length; levelIndex++) {
      final y = (levels[levelIndex - 1] + levels[levelIndex]) / 2;
      final intersections = <double>[];
      for (var i = 0; i < coordinates.length; i++) {
        final start = coordinates[i];
        final end = coordinates[(i + 1) % coordinates.length];
        if ((start[1] > y) != (end[1] > y)) {
          intersections.add(
            start[0] +
                (y - start[1]) * (end[0] - start[0]) / (end[1] - start[1]),
          );
        }
      }
      intersections.sort();
      for (var i = 0; i + 1 < intersections.length; i += 2) {
        final width = intersections[i + 1] - intersections[i];
        if (width > widestInterior) {
          widestInterior = width;
          interiorX = (intersections[i] + intersections[i + 1]) / 2;
          interiorY = y;
        }
      }
    }
    if (widestInterior > 0) {
      return plane.origin + plane.u * interiorX + plane.v * interiorY;
    }
    return _centroid(points);
  }

  static bool _containsPoint2D(double x, double y, List<List<double>> polygon) {
    var inside = false;
    var previousIndex = polygon.length - 1;
    for (var currentIndex = 0; currentIndex < polygon.length; currentIndex++) {
      final current = polygon[currentIndex];
      final previous = polygon[previousIndex];
      if ((current[1] > y) != (previous[1] > y) &&
          x <
              (previous[0] - current[0]) *
                      (y - current[1]) /
                      (previous[1] - current[1]) +
                  current[0]) {
        inside = !inside;
      }
      previousIndex = currentIndex;
    }
    return inside;
  }

  static Vector3D _rotateAroundAxis(
    Vector3D vector,
    Vector3D axis,
    double angle,
  ) {
    final cosine = dart_math.cos(angle);
    final sine = dart_math.sin(angle);
    return vector * cosine +
        axis.cross(vector) * sine +
        axis * (axis.dot(vector) * (1 - cosine));
  }

  static Vector3D _stablePerpendicular(Vector3D vector) {
    final unit = vector.normalized();
    if (unit.magnitude < 1e-9) return Vector3D.zero;
    final axis = unit.x.abs() <= unit.y.abs() && unit.x.abs() <= unit.z.abs()
        ? Vector3D.unitX
        : unit.y.abs() <= unit.z.abs()
        ? Vector3D.unitY
        : Vector3D.unitZ;
    return unit.cross(axis).normalized();
  }

  /// Reset the construction state.
  void reset() {
    _points.clear();
    _result = null;
    _previewObject = null;
    _validationMessage = null;
    _workingPlaneNormal = Vector3D.unitZ;
    _stepIndex = 0;
  }

  ConstructionAction _reject(String message) {
    _validationMessage = message;
    return ConstructionAction.awaitInput;
  }

  static bool _isFinitePoint(Point3D point) =>
      point.x.isFinite && point.y.isFinite && point.z.isFinite;
}
