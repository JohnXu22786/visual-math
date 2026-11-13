import 'package:flutter/foundation.dart';

import 'formula_entry.dart';
import 'math_3d_object.dart';
import 'math_3d_relationship.dart';
import 'math_3d_scene.dart';
import 'math_3d_tool.dart';
import 'math_drawing_state.dart';
import 'math_parameter.dart';

/// Immutable state captured from the complete workspace for host save/restore.
///
/// Version 1 snapshots retain typed scene objects and parsed formulas in
/// memory. This is a package API version, not a promise of a portable file
/// format.
class MathDrawingSnapshot {
  static const int currentVersion = 1;

  final int version;
  final List<FormulaEntry> formulas;
  final Map<String, MathParameter> parameters;
  final ViewMode activeView;
  final ConstructionTool activeTool;
  final int polygonSides3D;
  final Viewport viewport2D;
  final Camera3D camera3D;
  final ProjectionType projection3D;
  final bool showAxes3D;
  final bool showPlane3D;
  final bool showGrid3D;
  final bool showLabels3D;
  final List<Object3D> scene3D;
  final List<PointAttachment> pointAttachments3D;
  final List<ConstructionDependency> constructionDependencies3D;
  final bool showAxes2D;
  final bool showGrid2D;
  final bool showZeros2D;
  final bool showExtrema2D;

  MathDrawingSnapshot({
    this.version = currentVersion,
    required List<FormulaEntry> formulas,
    required Map<String, MathParameter> parameters,
    required this.activeView,
    required this.activeTool,
    this.polygonSides3D = 6,
    required this.viewport2D,
    required this.camera3D,
    required this.projection3D,
    this.showAxes3D = true,
    this.showPlane3D = true,
    this.showGrid3D = false,
    this.showLabels3D = true,
    required List<Object3D> scene3D,
    List<PointAttachment> pointAttachments3D = const [],
    List<ConstructionDependency> constructionDependencies3D = const [],
    this.showAxes2D = true,
    this.showGrid2D = true,
    this.showZeros2D = false,
    this.showExtrema2D = false,
  }) : formulas = List.unmodifiable([
         for (final formula in formulas)
           formula.copyWith(
             parsed: formula.parsed?.immutableCopy(),
             hiddenPlot3D: formula.hiddenPlot3D?.immutableCopy(),
             parameterValues: Map.unmodifiable(formula.parameterValues),
           ),
       ]),
       parameters = Map.unmodifiable(parameters),
       scene3D = List.unmodifiable(
         scene3D.map((object) => object.immutableCopy()),
       ),
       pointAttachments3D = List.unmodifiable(pointAttachments3D),
       constructionDependencies3D = List.unmodifiable(
         constructionDependencies3D.map(
           (dependency) => ConstructionDependency(
             objectId: dependency.objectId,
             tool: dependency.tool,
             inputPoints: dependency.inputPoints,
             sourcePointIds: dependency.sourcePointIds,
             workingPlaneNormal: dependency.workingPlaneNormal,
             polygonSides: dependency.polygonSides,
           ),
         ),
       ) {
    if (polygonSides3D < 3 || polygonSides3D > 12) {
      throw ArgumentError.value(
        polygonSides3D,
        'polygonSides3D',
        'Use 3–12 sides',
      );
    }
    if (version != currentVersion) {
      throw ArgumentError.value(
        version,
        'version',
        'Unsupported snapshot version',
      );
    }
  }
}

/// Commands and lifecycle events for the complete math workspace.
///
/// Pass one controller to the page and retain it in the host. The controller
/// can be attached to only one live page at a time.
class MathDrawingController {
  MathDrawingSnapshot? _snapshot;
  MathDrawingSnapshot? _pendingRestore;
  Future<void> Function()? _plot;
  void Function()? _reset2D;
  void Function()? _reset3D;
  void Function()? _fit2D;
  void Function()? _zoomIn2D;
  void Function()? _zoomOut2D;
  void Function(Viewport)? _setViewport2D;
  void Function(Camera3D)? _setCamera3D;
  void Function(ProjectionType)? _setProjection3D;
  void Function(List<Object3D>)? _setScene3D;
  void Function(ConstructionTool)? _setTool;
  void Function(ViewMode)? _setView;
  void Function(List<FormulaEntry>)? _setFormulas;
  void Function(Map<String, MathParameter>)? _setParameters;
  void Function(MathDrawingSnapshot)? _restore;

  /// Called when a formula row is edited by the user.
  void Function(int index, String expression)? onFormulaEdited;

  /// Called when a shared parameter value or slider range changes.
  void Function(String name, MathParameter parameter)? onParameterChanged;

  /// Called after a plot completes successfully.
  ValueChanged<MathDrawingSnapshot>? onPlotted;

  /// Called when formula parsing or plotting fails.
  ValueChanged<String>? onError;

  /// Called when the active tool changes.
  ValueChanged<ConstructionTool>? onToolChanged;

  /// Called when the active 2D/3D workspace view changes.
  ValueChanged<ViewMode>? onViewChanged;

  /// Called when the 3D selection changes. Null means the selection cleared.
  ValueChanged<Object3D?>? onSelectionChanged;

  /// Called when a 3D object is created.
  ValueChanged<Object3D>? onObjectCreated;

  /// Called when the 3D scene's object list or object values change.
  ValueChanged<List<Object3D>>? onSceneChanged;

  /// Called after the 2D viewport or 3D camera/projection changes.
  ValueChanged<MathDrawingSnapshot>? onViewportChanged;

  /// Latest immutable snapshot, or null until the page has attached.
  MathDrawingSnapshot? get snapshot => _snapshot;

  /// Current formulas, parameters, view, tool, and canvases.
  List<FormulaEntry> get formulas => _snapshot?.formulas ?? const [];
  Map<String, MathParameter> get parameters =>
      _snapshot?.parameters ?? const {};
  ViewMode get activeView => _snapshot?.activeView ?? ViewMode.mode2D;
  ConstructionTool get activeTool =>
      _snapshot?.activeTool ?? ConstructionTool.move;
  Viewport get viewport2D =>
      _snapshot?.viewport2D ?? Viewport.defaultViewport();
  Camera3D get camera3D => _snapshot?.camera3D ?? const Camera3D();
  ProjectionType get projection3D =>
      _snapshot?.projection3D ?? ProjectionType.parallel;
  List<Object3D> get scene3D => _snapshot?.scene3D ?? const [];

  /// Plot the current formulas.
  Future<void> plot() async {
    final plot = _plot;
    if (plot != null) await plot();
  }

  /// Reset the active canvas view.
  void resetView() {
    if (activeView == ViewMode.mode2D) {
      _reset2D?.call();
    } else {
      _reset3D?.call();
    }
  }

  /// Fit the active canvas contents into view.
  void fitToView() {
    if (activeView == ViewMode.mode2D) {
      _fit2D?.call();
    } else {
      // The page's 3D canvas owns the fit operation.
      _fit3D?.call();
    }
  }

  /// Zoom the active canvas in by one toolbar step.
  void zoomIn() =>
      activeView == ViewMode.mode2D ? _zoomIn2D?.call() : _zoomIn3D?.call();

  /// Zoom the active canvas out by one toolbar step.
  void zoomOut() =>
      activeView == ViewMode.mode2D ? _zoomOut2D?.call() : _zoomOut3D?.call();

  /// Set explicit 2D viewport bounds.
  void setViewport2D(Viewport viewport) => _setViewport2D?.call(viewport);

  /// Set the 3D camera.
  void setCamera3D(Camera3D camera) => _setCamera3D?.call(camera);

  /// Set the 3D projection type.
  void setProjection3D(ProjectionType projection) =>
      _setProjection3D?.call(projection);

  /// Replace the 3D scene objects.
  void setScene3D(List<Object3D> objects) => _setScene3D?.call(objects);

  /// Select the active 3D construction tool.
  void setActiveTool(ConstructionTool tool) => _setTool?.call(tool);

  /// Select the active workspace view.
  void setActiveView(ViewMode view) => _setView?.call(view);

  /// Replace the workspace formula rows.
  void setFormulas(List<FormulaEntry> formulas) =>
      _setFormulas?.call(List.unmodifiable(formulas));

  /// Replace shared parameter values and slider ranges.
  void setParameters(Map<String, MathParameter> parameters) =>
      _setParameters?.call(Map.unmodifiable(parameters));

  /// Restore a snapshot created by this package's supported version.
  void restore(MathDrawingSnapshot snapshot) {
    final restore = _restore;
    if (restore == null) {
      _pendingRestore = snapshot;
    } else {
      restore(snapshot);
    }
  }

  void Function()? _fit3D;
  void Function()? _zoomIn3D;
  void Function()? _zoomOut3D;

  /// Package-internal page lifecycle binding.
  void attach({
    required MathDrawingSnapshot initialSnapshot,
    required Future<void> Function() plot,
    required void Function() reset2D,
    required void Function() reset3D,
    required void Function() fit2D,
    required void Function() zoomIn2D,
    required void Function() zoomOut2D,
    required void Function() fit3D,
    required void Function() zoomIn3D,
    required void Function() zoomOut3D,
    required void Function(Viewport) setViewport2D,
    required void Function(Camera3D) setCamera3D,
    required void Function(ProjectionType) setProjection3D,
    required void Function(List<Object3D>) setScene3D,
    required void Function(ConstructionTool) setTool,
    required void Function(ViewMode) setView,
    required void Function(List<FormulaEntry>) setFormulas,
    required void Function(Map<String, MathParameter>) setParameters,
    required void Function(MathDrawingSnapshot) restore,
  }) {
    if (_plot != null) throw StateError('Controller is already attached');
    _snapshot = initialSnapshot;
    _plot = plot;
    _reset2D = reset2D;
    _reset3D = reset3D;
    _fit2D = fit2D;
    _zoomIn2D = zoomIn2D;
    _zoomOut2D = zoomOut2D;
    _fit3D = fit3D;
    _zoomIn3D = zoomIn3D;
    _zoomOut3D = zoomOut3D;
    _setViewport2D = setViewport2D;
    _setCamera3D = setCamera3D;
    _setProjection3D = setProjection3D;
    _setScene3D = setScene3D;
    _setTool = setTool;
    _setView = setView;
    _setFormulas = setFormulas;
    _setParameters = setParameters;
    _restore = restore;
    final pendingRestore = _pendingRestore;
    _pendingRestore = null;
    if (pendingRestore != null) restore(pendingRestore);
  }

  void publish(MathDrawingSnapshot snapshot) => _snapshot = snapshot;

  void detach() {
    _snapshot = null;
    _plot = null;
    _reset2D = _reset3D = _fit2D = _zoomIn2D = _zoomOut2D = null;
    _fit3D = _zoomIn3D = _zoomOut3D = null;
    _setViewport2D = null;
    _setCamera3D = null;
    _setProjection3D = null;
    _setScene3D = null;
    _setTool = null;
    _setView = null;
    _setFormulas = null;
    _setParameters = null;
    _restore = null;
  }
}
