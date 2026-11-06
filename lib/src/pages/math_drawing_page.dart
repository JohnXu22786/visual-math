import 'dart:async';
import 'dart:math' as dart_math;

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/math_3d_object.dart';
import '../models/math_3d_scene.dart';
import '../models/math_3d_tool.dart';
import '../models/math_drawing_controller.dart';
import '../models/math_drawing_state.dart';
import '../models/math_expression.dart' show MathExpression;
import '../models/math_expression_3d.dart';
import '../models/math_parameter.dart';
import '../models/formula_entry.dart';
import '../widgets/math_canvas.dart';
import '../widgets/math_canvas_3d.dart';
import '../widgets/math_3d_toolbar.dart';
import '../widgets/math_formula_field.dart';
import '../widgets/math_keyboard.dart';
import '../widgets/math_parameter_controls.dart';
import '../widgets/math_ui_tokens.dart';

/// A complete math workspace with formula editing, graphing, and 3D geometry.
///
/// Use [initialExpression] to seed the first formula. On platforms where the
/// embedded MathLive WebView is unavailable, formula entry uses the built-in
/// source editor and formula preview fallback.
class MathDrawingPage extends StatefulWidget {
  /// Initial expression shown in the first formula row, if any.
  final String? initialExpression;

  /// Whether to show the platform WebView editor when it is supported.
  final bool initialShowWebView;

  /// Initial input mode; defaults to the platform's supported editor mode.
  final bool? initialMathematicalMode;

  /// Optional host controller for formulas, canvas state, commands, and events.
  final MathDrawingController? controller;

  /// Creates a math workspace.
  const MathDrawingPage({
    super.key,
    this.initialExpression,
    this.initialShowWebView = true,
    this.initialMathematicalMode,
    this.controller,
  });

  @override
  State<MathDrawingPage> createState() => _MathDrawingPageState();
}

class _MathDrawingPageState extends State<MathDrawingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<MathCanvasState> _canvasKey = GlobalKey();
  final GlobalKey<MathCanvas3DState> _canvas3DKey = GlobalKey();

  ViewMode _currentView = ViewMode.mode2D;

  // 3D construction state
  ConstructionTool _current3DTool = ConstructionTool.move;
  int _polygonSides = 6;
  String _toolInstruction = '';

  /// All formula rows (each is equal).
  final List<_FormulaState> _formulas = [];
  final ScrollController _formulaScroll = ScrollController();
  _FormulaState? _activeFormula;
  bool _mathMode = true;
  bool _keyboardVisible = false;
  bool _modeTouched = false;
  static const _modePreference = 'math_drawing_mathematical_input';
  final Map<String, MathParameter> _parameters = {};
  Set<String> _activeParameterNames = {};
  List<FormulaEntry> _plottedFormulas = [];
  String? _plotError;
  List<Object3D> _lastReportedScene = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    _mathMode = widget.initialMathematicalMode ?? MathFormulaField.supported;
    if (widget.initialMathematicalMode == null && MathFormulaField.supported) {
      unawaited(_restoreMode());
    }
    // Start with one formula row
    _formulas.add(
      _FormulaState(
        controller: TextEditingController(text: widget.initialExpression ?? ''),
        color: formulaPalette[0],
        autoColor: true,
        visible: true,
      ),
    );
    widget.controller?.attach(
      initialSnapshot: _makeSnapshot(),
      plot: _plotAll,
      reset2D: () => _canvasKey.currentState?.resetView(),
      reset3D: () => _canvas3DKey.currentState?.resetView(),
      fit2D: () => _canvasKey.currentState?.fitToView(),
      zoomIn2D: () => _canvasKey.currentState?.zoomIn(),
      zoomOut2D: () => _canvasKey.currentState?.zoomOut(),
      fit3D: () => _canvas3DKey.currentState?.fitToView(),
      zoomIn3D: () => _canvas3DKey.currentState?.zoomIn(),
      zoomOut3D: () => _canvas3DKey.currentState?.zoomOut(),
      setViewport2D: (viewport) => _canvasKey.currentState?.setViewport(
        viewport.xMin,
        viewport.yMin,
        viewport.xMax,
        viewport.yMax,
      ),
      setCamera3D: (camera) => _canvas3DKey.currentState?.setCamera(camera),
      setProjection3D: (projection) =>
          _canvas3DKey.currentState?.setProjectionType(projection),
      setScene3D: _setScene3D,
      setTool: _setActiveTool,
      setView: _setActiveView,
      setFormulas: _setFormulas,
      setParameters: _setParameters,
      restore: _restoreSnapshot,
    );
    _syncController();
  }

  @override
  void didUpdateWidget(MathDrawingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(
        initialSnapshot: _makeSnapshot(),
        plot: _plotAll,
        reset2D: () => _canvasKey.currentState?.resetView(),
        reset3D: () => _canvas3DKey.currentState?.resetView(),
        fit2D: () => _canvasKey.currentState?.fitToView(),
        zoomIn2D: () => _canvasKey.currentState?.zoomIn(),
        zoomOut2D: () => _canvasKey.currentState?.zoomOut(),
        fit3D: () => _canvas3DKey.currentState?.fitToView(),
        zoomIn3D: () => _canvas3DKey.currentState?.zoomIn(),
        zoomOut3D: () => _canvas3DKey.currentState?.zoomOut(),
        setViewport2D: (viewport) => _canvasKey.currentState?.setViewport(
          viewport.xMin,
          viewport.yMin,
          viewport.xMax,
          viewport.yMax,
        ),
        setCamera3D: (camera) => _canvas3DKey.currentState?.setCamera(camera),
        setProjection3D: (projection) =>
            _canvas3DKey.currentState?.setProjectionType(projection),
        setScene3D: _setScene3D,
        setTool: _setActiveTool,
        setView: _setActiveView,
        setFormulas: _setFormulas,
        setParameters: _setParameters,
        restore: _restoreSnapshot,
      );
      _syncController();
    }
  }

  @override
  void dispose() {
    for (final f in _formulas) {
      f.controller.dispose();
    }
    _formulaScroll.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    widget.controller?.detach();
    super.dispose();
  }

  Future<void> _restoreMode() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted && !_modeTouched) {
      setState(() => _mathMode = preferences.getBool(_modePreference) ?? true);
    }
  }

  void _setMode(bool mathematical, _FormulaState formula) {
    _modeTouched = true;
    setState(() {
      _mathMode = mathematical;
      _activeFormula = formula;
      _keyboardVisible = mathematical;
    });
    if (mathematical) {
      _ensureFormulaVisible(formula);
    }
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_modePreference, mathematical),
      ),
    );
  }

  void _ensureFormulaVisible(_FormulaState formula) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = formula.rowKey.currentContext;
      if (mounted && rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void _activateFormula(_FormulaState formula) {
    if (!_mathMode) return;
    _modeTouched = true;
    final keyboardWasHidden = !_keyboardVisible;
    if (!keyboardWasHidden && _activeFormula == formula) return;
    setState(() {
      _activeFormula = formula;
      _keyboardVisible = true;
    });
    if (keyboardWasHidden) {
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
    _ensureFormulaVisible(formula);
  }

  Future<void> _flushEditors() async {
    for (final formula in List<_FormulaState>.of(_formulas)) {
      await formula.editorKey.currentState?.flush();
    }
  }

  MathDrawingSnapshot _makeSnapshot() {
    final formulas = [
      for (final formula in _formulas)
        FormulaEntry(
          rawExpression: formula.controller.text,
          parsed: MathExpression.fromInput(formula.controller.text),
          color: formula.color,
          autoColor: formula.autoColor,
          visible: formula.visible,
        ),
    ];
    final viewport =
        _canvasKey.currentState?.viewport ?? (-10.0, -10.0, 10.0, 10.0);
    return MathDrawingSnapshot(
      formulas: formulas,
      parameters: _parameters,
      activeView: _currentView,
      activeTool: _current3DTool,
      viewport2D: Viewport(
        xMin: viewport.$1,
        yMin: viewport.$2,
        xMax: viewport.$3,
        yMax: viewport.$4,
      ),
      camera3D: _canvas3DKey.currentState?.camera ?? const Camera3D(),
      projection3D:
          _canvas3DKey.currentState?.projectionType ?? ProjectionType.parallel,
      scene3D: _canvas3DKey.currentState?.objects ?? const [],
    );
  }

  void _syncController() {
    final controller = widget.controller;
    if (controller != null) controller.publish(_makeSnapshot());
  }

  void _setActiveTool(ConstructionTool tool) {
    if (tool == _current3DTool) {
      _canvas3DKey.currentState?.setTool(tool);
    }
    setState(() {
      _current3DTool = tool;
      _toolInstruction = '';
    });
    _syncController();
    widget.controller?.onToolChanged?.call(tool);
  }

  void _setActiveView(ViewMode view) {
    if (_tabController.index != (view == ViewMode.mode2D ? 0 : 1)) {
      _tabController.animateTo(view == ViewMode.mode2D ? 0 : 1);
    }
  }

  void _setScene3D(List<Object3D> objects) {
    _canvas3DKey.currentState?.setObjects(objects);
    _publish3DChange();
  }

  void _publish3DChange() {
    final controller = widget.controller;
    if (controller == null) return;
    final previousScene = _lastReportedScene;
    final currentScene =
        _canvas3DKey.currentState?.objects ?? const <Object3D>[];
    final previousSnapshot = controller.snapshot;
    final snapshot = _makeSnapshot();
    controller.publish(snapshot);
    final camera = snapshot.camera3D;
    final sceneChanged =
        previousScene.length != currentScene.length ||
        List.generate(
          previousScene.length,
          (index) => index,
        ).any((index) => !identical(previousScene[index], currentScene[index]));
    _lastReportedScene = List.of(currentScene);
    if (sceneChanged) controller.onSceneChanged?.call(snapshot.scene3D);
    final cameraChanged =
        previousSnapshot != null &&
        (previousSnapshot.camera3D.target != camera.target ||
            previousSnapshot.camera3D.distance != camera.distance ||
            previousSnapshot.camera3D.theta != camera.theta ||
            previousSnapshot.camera3D.phi != camera.phi ||
            previousSnapshot.projection3D != snapshot.projection3D);
    if (cameraChanged) controller.onViewportChanged?.call(snapshot);
  }

  void _setFormulas(List<FormulaEntry> formulas) {
    setState(() {
      for (final formula in _formulas) {
        formula.controller.dispose();
      }
      _formulas
        ..clear()
        ..addAll([
          for (final entry in formulas)
            _FormulaState(
              controller: TextEditingController(text: entry.rawExpression),
              color: entry.color,
              autoColor: entry.autoColor,
              visible: entry.visible,
            ),
        ]);
      _activeFormula = null;
      _keyboardVisible = false;
      if (_formulas.isEmpty) {
        _formulas.add(
          _FormulaState(
            controller: TextEditingController(),
            color: formulaPalette[0],
          ),
        );
      }
    });
    _syncController();
  }

  void _setParameters(Map<String, MathParameter> parameters) {
    setState(() {
      _parameters
        ..clear()
        ..addAll(parameters);
      _activeParameterNames = parameters.keys.toSet();
    });
    _refreshParameterCurves();
    _syncController();
  }

  void _restoreSnapshot(MathDrawingSnapshot snapshot) {
    final controller = widget.controller;
    setState(() {
      for (final formula in _formulas) {
        formula.controller.dispose();
      }
      _formulas
        ..clear()
        ..addAll([
          for (final entry in snapshot.formulas)
            _FormulaState(
              controller: TextEditingController(text: entry.rawExpression),
              color: entry.color,
              autoColor: entry.autoColor,
              visible: entry.visible,
            )..committedText = entry.rawExpression.trim(),
        ]);
      _activeFormula = null;
      _keyboardVisible = false;
      if (_formulas.isEmpty) {
        _formulas.add(
          _FormulaState(
            controller: TextEditingController(),
            color: formulaPalette[0],
          ),
        );
      }
      _parameters
        ..clear()
        ..addAll(snapshot.parameters);
      _currentView = snapshot.activeView;
      _current3DTool = snapshot.activeTool;
      _activeParameterNames = _parameters.keys.toSet();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _canvasKey.currentState?.setViewport(
        snapshot.viewport2D.xMin,
        snapshot.viewport2D.yMin,
        snapshot.viewport2D.xMax,
        snapshot.viewport2D.yMax,
      );
      _canvas3DKey.currentState?.setCamera(snapshot.camera3D);
      _canvas3DKey.currentState?.setProjectionType(snapshot.projection3D);
      _canvas3DKey.currentState?.setObjects(snapshot.scene3D);
      _canvas3DKey.currentState?.setTool(snapshot.activeTool);
      _publish3DChange();
      _tabController.animateTo(snapshot.activeView == ViewMode.mode2D ? 0 : 1);
      if (snapshot.activeView == ViewMode.mode2D) unawaited(_plotAll());
    });
    _syncController();
    controller?.publish(_makeSnapshot());
  }

  void _dismissKeyboard() {
    unawaited(_activeFormula?.editorKey.currentState?.dismiss());
    setState(() => _keyboardVisible = false);
  }

  Future<void> _onTabChanged() async {
    final target = _tabController.index == 0
        ? ViewMode.mode2D
        : ViewMode.mode3D;
    if (_tabController.indexIsChanging || target == _currentView) return;
    _dismissKeyboard();
    await _flushEditors();
    if (!mounted || (_tabController.index == 0) != (target == ViewMode.mode2D))
      return;
    setState(() => _currentView = target);
    _syncController();
    widget.controller?.onViewChanged?.call(target);
  }

  // ==================================================================
  // Formula management
  // ==================================================================

  bool get _canPlot {
    return _formulas.any((f) {
      final text = f.controller.text.trim();
      return text != f.committedText;
    });
  }

  /// Plot all visible formulas that have changes.
  Future<void> _plotAll() async {
    final view = _currentView;
    await _flushEditors();
    if (!mounted) return;
    _plotError = null;
    if (view == ViewMode.mode2D) {
      _plotAll2D();
    } else {
      _plotAll3D();
    }
    if (view == ViewMode.mode3D) {
      _publish3DChange();
    } else {
      _syncController();
    }
    if (_plotError == null) {
      widget.controller?.onPlotted?.call(_makeSnapshot());
    }
  }

  void _plotAll2D() {
    final entries = <FormulaEntry>[];
    for (final f in _formulas) {
      final text = f.controller.text.trim();
      if (text.isEmpty) continue;
      if (!f.visible) continue;

      final parsed = MathExpression.fromInput(text);
      if (!parsed.isValid) {
        _showError(
          text.contains(r'\placeholder')
              ? '公式仍有空槽，请填写后再绘图。'
              : '此公式暂不能绘图，编辑内容已保留。${parsed.parseError ?? ""}',
        );
        return;
      }
      entries.add(
        FormulaEntry(
          rawExpression: text,
          parsed: parsed,
          color: f.color,
          autoColor: f.autoColor,
        ),
      );
    }
    // Mark all rows as committed
    setState(() {
      _activeParameterNames = {
        for (final entry in entries)
          ...entry.parsed!.parameters.where(
            (name) => name != 'x' && name != 'y',
          ),
      };
      for (final name in _activeParameterNames) {
        _parameters.putIfAbsent(name, MathParameter.new);
      }
      _plottedFormulas = entries;
      for (final f in _formulas) {
        f.committedText = f.controller.text.trim();
      }
    });

    _refreshParameterCurves();
  }

  /// Keep slider redraws tied to the last plotted formulas, not editor drafts.
  void _refreshParameterCurves() {
    final entries = [
      for (final entry in _plottedFormulas)
        entry.copyWith(
          parameterValues: {
            for (final name in entry.parsed!.parameters)
              if (_parameters.containsKey(name)) name: _parameters[name]!.value,
          },
          parsed: entry.parsed!.withParameters({
            for (final name in entry.parsed!.parameters)
              if (_parameters.containsKey(name)) name: _parameters[name]!.value,
          }),
        ),
    ];
    _canvasKey.currentState?.setFormulas(entries);
  }

  void _updateParameter(String name, MathParameter parameter) {
    if (!mounted || !_activeParameterNames.contains(name)) return;
    setState(() => _parameters[name] = parameter);
    _refreshParameterCurves();
    _syncController();
    widget.controller?.onParameterChanged?.call(name, parameter);
  }

  void _plotAll3D() {
    final objects = <Object3D>[];
    for (final f in _formulas) {
      final text = f.controller.text.trim();
      if (text.isEmpty) continue;
      if (!f.visible) continue;

      final colorInt = f.color.toARGB32();

      // Try parsing as 3D surface z = f(x, y)
      final surfaceExpr = Expression3D.surface(text);
      if (surfaceExpr.isValid) {
        final mesh = surfaceExpr.sampleSurfaceGrid(
          xMin: -5,
          xMax: 5,
          yMin: -5,
          yMax: 5,
          gridX: 30,
          gridY: 30,
        );
        if (mesh.vertices.isNotEmpty) {
          objects.add(
            Object3D.surface(
              vertices: mesh.vertices,
              indices: mesh.indices,
              normals: mesh.normals,
              color: colorInt,
              opacity: 0.85,
              label: text,
            ),
          );
          continue;
        }
      }

      // Try parsing as parametric curve
      final curveExpr = Expression3D.parametricCurve(
        text,
        tMax: 2 * dart_math.pi,
      );
      if (curveExpr.isValid) {
        final segments = curveExpr.sampleCurveSegments(numSamples: 100);
        final points = <Point3D>[];
        final curveStarts = <int>[];
        for (final segment in segments) {
          if (segment.isEmpty) continue;
          if (points.isNotEmpty) curveStarts.add(points.length);
          points.addAll(segment);
        }
        if (points.isNotEmpty) {
          objects.add(
            Object3D.curve(
              points: points,
              curveStarts: curveStarts,
              color: colorInt,
              label: text,
            ),
          );
          continue;
        }
      }

      // If none matched, show error
      _showError('无法解析为3D表达式: $text');
      return;
    }

    setState(() {
      for (final f in _formulas) {
        f.committedText = f.controller.text.trim();
      }
    });

    if (objects.isEmpty) {
      _canvas3DKey.currentState?.clearObjects();
    } else {
      _canvas3DKey.currentState?.setObjects(objects);
    }
  }

  void _addFormula() {
    final used = _formulas
        .where((f) => f.autoColor)
        .map((f) => f.color)
        .toSet();
    final color = nextFormulaColor(used);

    setState(() {
      _formulas.add(
        _FormulaState(
          controller: TextEditingController(),
          color: color,
          autoColor: true,
          visible: true,
        ),
      );
    });
    _syncController();
  }

  Future<void> _removeFormula(_FormulaState removing) async {
    if (_formulas.length <= 1) return;
    await _flushEditors();
    if (!mounted || _formulas.length <= 1 || !_formulas.contains(removing))
      return;
    final index = _formulas.indexOf(removing);
    setState(() {
      if (_activeFormula == removing) {
        _activeFormula = null;
        _keyboardVisible = false;
      }
      _formulas[index].controller.dispose();
      _formulas.removeAt(index);
    });
    // Re-plot after deletion so the canvas reflects the remaining formulas
    _plotAll();
  }

  void _confirmRemove(_FormulaState removing) {
    final index = _formulas.indexOf(removing);
    if (index < 0 || _formulas.length <= 1) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除公式'),
        content: Text('确定要删除"公式 ${index + 1}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeFormula(removing);
            },
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleVisibility(int index) async {
    final formula = _formulas[index];
    await _flushEditors();
    if (!mounted || !_formulas.contains(formula)) return;
    setState(() {
      formula.visible = !formula.visible;
    });
    // Re-plot to update canvas
    _plotAll();
  }

  void _showColorPicker(int formulaIndex) {
    final currentColor = _formulas[formulaIndex].color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择颜色'),
        content: Wrap(
          spacing: MathUiTokens.canvasInset,
          runSpacing: MathUiTokens.canvasInset,
          children: [
            for (
              var swatchIndex = 0;
              swatchIndex < formulaPalette.length;
              swatchIndex++
            )
              Builder(
                builder: (context) {
                  final color = formulaPalette[swatchIndex];
                  final selected = currentColor == color;
                  final primary = Theme.of(context).colorScheme.primary;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: '公式颜色 ${swatchIndex + 1}',
                    child: SizedBox.square(
                      dimension: MathUiTokens.swatchTapTarget,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(() {
                            _formulas[formulaIndex].color = color;
                            _formulas[formulaIndex].autoColor = false;
                          });
                          Navigator.pop(ctx);
                          _plotAll();
                        },
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: selected
                                  ? Border.all(color: primary, width: 3)
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    _plotError = msg;
    widget.controller?.onError?.call(msg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================================================================
  // Build
  // ==================================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_keyboardVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _keyboardVisible) _dismissKeyboard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('数学绘图'),
          actions: [
            IconButton(
              icon: Icon(Icons.add, size: 24, color: cs.primary),
              tooltip: '添加公式',
              onPressed: _addFormula,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = (constraints.maxHeight - 48)
                .clamp(0.0, double.infinity)
                .toDouble();
            final formulaListBaseHeight =
                availableHeight * (_keyboardVisible ? 0.28 : 0.4);
            final keyboardBaseHeight = _keyboardVisible
                ? availableHeight * 0.56
                : 0.0;
            final keyboardMaxHeight = keyboardBaseHeight;

            return Column(
              children: [
                _buildTabBar(cs),
                // Formula list (always shown)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: formulaListBaseHeight),
                  child: _buildFormulaList(cs),
                ),
                // Canvas + 3D canvas kept alive via IndexedStack
                Expanded(
                  child: IndexedStack(
                    index: _currentView == ViewMode.mode2D ? 0 : 1,
                    children: [_buildCanvas(cs), _build3DCanvas(cs)],
                  ),
                ),
                if (_keyboardVisible && _activeFormula != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: keyboardMaxHeight),
                    child: MathKeyboard(
                      enabled:
                          _activeFormula?.editorKey.currentState?.ready ??
                          false,
                      supportsStructuralNavigation:
                          _activeFormula
                              ?.editorKey
                              .currentState
                              ?.supportsStructuralNavigation ??
                          false,
                      supportsStructuredEditing:
                          _activeFormula
                              ?.editorKey
                              .currentState
                              ?.supportsStructuredEditing ??
                          false,
                      activeLabel:
                          '公式 ${_formulas.indexOf(_activeFormula!) + 1}',
                      location:
                          _activeFormula?.editorKey.currentState?.location ??
                          '公式',
                      onCommand: (kind, value) async {
                        final formula = _activeFormula;
                        final editor = formula?.editorKey.currentState;
                        if (kind == 'clipboard') {
                          await editor?.clipboard(
                            value,
                            isTargetActive: () =>
                                mounted && _activeFormula == formula,
                          );
                        } else {
                          await editor?.command(kind, value);
                        }
                      },
                      onDismiss: _dismissKeyboard,
                      onPlot: _plotAll,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart, size: 18),
                SizedBox(width: 6),
                Text('2D'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_in_ar, size: 18),
                SizedBox(width: 6),
                Text('3D'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // Formula list
  // ==================================================================

  Widget _buildFormulaList(ColorScheme cs) {
    final parameterNames = _activeParameterNames.toList()..sort();
    final showParameters =
        _currentView == ViewMode.mode2D && parameterNames.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      shrinkWrap: true,
      controller: _formulaScroll,
      physics: const ClampingScrollPhysics(),
      itemCount: _formulas.length + (showParameters ? 1 : 0),
      itemBuilder: (_, index) => index < _formulas.length
          ? _buildFormulaRow(cs, index)
          : MathParameterControls(
              key: const ValueKey('math-parameter-controls'),
              parameters: {
                for (final name in parameterNames) name: _parameters[name]!,
              },
              onChanged: _updateParameter,
            ),
    );
  }

  Widget _buildFormulaRow(ColorScheme cs, int index) {
    final f = _formulas[index];
    final hasChanged =
        f.controller.text.trim().isNotEmpty &&
        f.controller.text.trim() != f.committedText;

    return Padding(
      key: f.rowKey,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // ---- Left spacing before color indicator ----
          const SizedBox(width: 4),

          // ---- Color indicator (tappable) ----
          GestureDetector(
            onTap: () => _showColorPicker(index),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: f.color,
                shape: BoxShape.circle,
                border: hasChanged
                    ? Border.all(color: cs.primary, width: 2)
                    : null,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // A retained editor per row keeps its structural cursor and undo.
          Expanded(
            child: MathFormulaField(
              key: f.editorKey,
              controller: f.controller,
              mathematical: _mathMode,
              allowModeSwitch: true,
              showWebView: widget.initialShowWebView,
              label: '公式 ${index + 1}',
              fillColor: f.color.withValues(alpha: 0.06),
              onModeChanged: (mode) => _setMode(mode, f),
              onActivate: () => _activateFormula(f),
              onChanged: () {
                setState(() {});
                _syncController();
                widget.controller?.onFormulaEdited?.call(
                  index,
                  f.controller.text,
                );
              },
              onSubmitted: _plotAll,
              onReadyChanged: () {
                if (mounted) setState(() {});
              },
              onCaretChanged: () {
                if (mounted && _activeFormula == f) setState(() {});
              },
              onRevert: hasChanged
                  ? () {
                      f.controller.text = f.committedText;
                      setState(() {});
                    }
                  : null,
            ),
          ),

          // ---- Action buttons ----
          // Each action button carries a uniform 12px leading gap. This also
          // matches the left-side gap between the color circle and the input.
          _buildActionButton(
            icon: f.visible ? Icons.visibility : Icons.visibility_off,
            iconSize: 20,
            color: f.visible ? cs.onSurface : cs.onSurfaceVariant,
            tooltip: f.visible ? '隐藏公式' : '显示公式',
            onPressed: () => _toggleVisibility(index),
          ),

          // ---- Remove formula (X) button ----
          if (_formulas.length > 1)
            _buildActionButton(
              icon: Icons.remove_circle_outline,
              iconSize: 16,
              color: cs.error.withValues(alpha: 0.7),
              tooltip: '删除公式',
              onPressed: () => _confirmRemove(f),
            ),

          // ---- Plot (✓) button ----
          _buildActionButton(
            icon: Icons.check_circle_outline,
            iconSize: 20,
            color: hasChanged
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.2),
            tooltip: '绘制',
            onPressed: _canPlot ? _plotAll : null,
          ),
        ],
      ),
    );
  }

  /// A compact 24x24 action button for a formula row, with a uniform 12px
  /// leading gap.
  ///
  /// Uses [MaterialTapTargetSize.shrinkWrap] + `fixedSize` instead of the
  /// `constraints` parameter: with Material 3, `constraints` is translated
  /// into the style's minimum/maximum size, while the button's outer block
  /// is padded up to the tap-target minimum (48dp minus the visual-density
  /// adjustment), so a `constraints`-only 24x24 still occupies a 40x40
  /// block and silently widens the right side of every formula row.
  Widget _buildActionButton({
    required IconData icon,
    required double iconSize,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(24, 24),
          fixedSize: const Size(24, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  // ==================================================================
  // Canvas (2D)
  // ==================================================================

  Widget _buildCanvas(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MathUiTokens.canvasInset),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant, width: 0.5),
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
                child: MathCanvas(
                  key: _canvasKey,
                  initialExpression: null,
                  onReady: () {
                    debugPrint('[MathDrawing] Canvas ready');
                    _syncController();
                  },
                  onViewportChange: (_, __, ___, ____) {
                    _syncController();
                    widget.controller?.onViewportChanged?.call(_makeSnapshot());
                  },
                  onError: (msg) {
                    debugPrint('[MathDrawing] Canvas error: $msg');
                    widget.controller?.onError?.call(msg);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _floatingControl(
                  icon: Icons.filter_center_focus,
                  tooltip: '缩放至适合',
                  onPressed: () {
                    final controller = widget.controller;
                    if (controller != null) {
                      controller.fitToView();
                    } else {
                      _canvasKey.currentState?.fitToView();
                    }
                  },
                ),
                _floatingControl(
                  icon: Icons.zoom_in,
                  tooltip: '放大',
                  onPressed: () {
                    final controller = widget.controller;
                    if (controller != null) {
                      controller.zoomIn();
                    } else {
                      _canvasKey.currentState?.zoomIn();
                    }
                  },
                ),
                _floatingControl(
                  icon: Icons.zoom_out,
                  tooltip: '缩小',
                  onPressed: () {
                    final controller = widget.controller;
                    if (controller != null) {
                      controller.zoomOut();
                    } else {
                      _canvasKey.currentState?.zoomOut();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingControl({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
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

  // ==================================================================
  // 3D canvas
  // ==================================================================

  Widget _build3DCanvas(ColorScheme cs) {
    return Column(
      children: [
        // Construction toolbar
        Math3DToolbar(
          activeTool: _current3DTool,
          polygonSides: _polygonSides,
          onPolygonSidesChanged: (sides) =>
              setState(() => _polygonSides = sides),
          instruction: _current3DTool != ConstructionTool.move
              ? (_canvas3DKey.currentState?.constructionInstruction ??
                    _toolInstruction)
              : null,
          onToolSelected: (tool) {
            if (ToolInfo.all[tool]!.behavior == ToolBehavior.command) {
              _canvas3DKey.currentState?.performToolCommand(tool);
              return;
            }
            _setActiveTool(tool);
          },
        ),
        // 3D canvas
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MathUiTokens.canvasInset,
              4,
              MathUiTokens.canvasInset,
              MathUiTokens.canvasInset,
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant, width: 0.5),
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
                child: MathCanvas3D(
                  key: _canvas3DKey,
                  currentTool: _current3DTool,
                  polygonSides: _polygonSides,
                  onViewportChange: _publish3DChange,
                  onSceneChanged: _publish3DChange,
                  onObjectCreated: (obj) {
                    widget.controller?.onObjectCreated?.call(obj);
                    _canvas3DKey.currentState?.setObjects([
                      ...?_canvas3DKey.currentState?.objects,
                      obj,
                    ]);
                    _publish3DChange();
                  },
                  onToolInstruction: (instruction) {
                    setState(() {
                      _toolInstruction = instruction;
                    });
                  },
                  onSelectionChanged: (object) =>
                      widget.controller?.onSelectionChanged?.call(object),
                  onReady: _syncController,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// State for a single formula row.
class _FormulaState {
  final TextEditingController controller;
  final GlobalKey rowKey = GlobalKey();
  final GlobalKey<MathFormulaFieldState> editorKey = GlobalKey();
  Color color;
  bool autoColor;
  String committedText;
  bool visible;

  _FormulaState({
    required this.controller,
    required this.color,
    this.autoColor = true,
    this.visible = true,
  }) : committedText = '';
}
