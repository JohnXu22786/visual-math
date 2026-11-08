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
import 'math_workspace_options.dart';

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

  /// Configures the available views and composable workspace regions.
  final MathWorkspaceOptions options;

  /// Creates a math workspace.
  const MathDrawingPage({
    super.key,
    this.initialExpression,
    this.initialShowWebView = true,
    this.initialMathematicalMode,
    this.controller,
    this.options = const MathWorkspaceOptions(),
  });

  @override
  State<MathDrawingPage> createState() => _MathDrawingPageState();
}

class _MathDrawingPageState extends State<MathDrawingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<MathCanvasState> _canvasKey = GlobalKey();
  final GlobalKey<MathCanvas3DState> _canvas3DKey = GlobalKey();
  final GlobalKey<MathFormulaFieldState> _fallbackEditorKey = GlobalKey();

  late ViewMode _currentView;

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
    _currentView = widget.options.initialView;
    _tabController = TabController(
      length: 2,
      initialIndex: _currentView == ViewMode.mode2D ? 0 : 1,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);

    _mathMode = widget.initialMathematicalMode ?? MathFormulaField.supported;
    if (widget.initialMathematicalMode == null &&
        MathFormulaField.supported &&
        widget.options.persistence.enabled) {
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
      setView: _controllerSetActiveView,
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
        setView: _controllerSetActiveView,
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
      f.domainMinController.dispose();
      f.domainMaxController.dispose();
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
      setState(
        () => _mathMode =
            preferences.getBool(
              widget.options.persistence.key(_modePreference),
            ) ??
            true,
      );
    }
  }

  void _setMode(bool mathematical, _FormulaState formula) {
    _modeTouched = true;
    setState(() {
      _mathMode = mathematical;
      _activeFormula = formula;
      _keyboardVisible =
          mathematical &&
          (widget.options.showKeyboard ||
              widget.options.keyboardBuilder != null);
    });
    if (mathematical) {
      _ensureFormulaVisible(formula);
    }
    if (widget.options.persistence.enabled) {
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setBool(
            widget.options.persistence.key(_modePreference),
            mathematical,
          ),
        ),
      );
    }
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
      _keyboardVisible =
          widget.options.showKeyboard || widget.options.keyboardBuilder != null;
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
          domainMin: _resolveDomainEndpoint(formula.domainMinController.text),
          domainMax: _resolveDomainEndpoint(formula.domainMaxController.text),
          domainMinExpression: formula.domainMinController.text,
          domainMaxExpression: formula.domainMaxController.text,
          includeDomainMin: formula.includeDomainMin,
          includeDomainMax: formula.includeDomainMax,
          identity: formula.identity,
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

  void _controllerSetActiveView(ViewMode view) {
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
        formula.domainMinController.dispose();
        formula.domainMaxController.dispose();
      }
      _formulas
        ..clear()
        ..addAll([
          for (final entry in formulas) _formulaStateFromEntry(entry),
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
    final wasInvalid = _hasInvalidDomainOrder();
    setState(() {
      _parameters
        ..clear()
        ..addAll(parameters);
      _activeParameterNames = parameters.keys.toSet();
    });
    _refreshParameterCurves();
    if (!wasInvalid && _hasInvalidDomainOrder()) {
      _showError('参数变化后，定义域端点或范围无效。');
    }
    _syncController();
  }

  void _restoreSnapshot(MathDrawingSnapshot snapshot) {
    final controller = widget.controller;
    final restoredView = switch (snapshot.activeView) {
      ViewMode.mode2D when widget.options.show2D => ViewMode.mode2D,
      ViewMode.mode3D when widget.options.show3D => ViewMode.mode3D,
      _ => widget.options.initialView,
    };
    setState(() {
      for (final formula in _formulas) {
        formula.controller.dispose();
        formula.domainMinController.dispose();
        formula.domainMaxController.dispose();
      }
      _formulas
        ..clear()
        ..addAll([
          for (final entry in snapshot.formulas)
            _formulaStateFromEntry(entry)
              ..committedText = entry.rawExpression.trim(),
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
      _currentView = restoredView;
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
      _tabController.animateTo(restoredView == ViewMode.mode2D ? 0 : 1);
      if (restoredView == ViewMode.mode2D) unawaited(_plotAll());
    });
    _syncController();
    controller?.publish(_makeSnapshot());
  }

  _FormulaState _formulaStateFromEntry(FormulaEntry entry) {
    final formula = _FormulaState(
      controller: TextEditingController(text: entry.rawExpression),
      color: entry.color,
      autoColor: entry.autoColor,
      visible: entry.visible,
      identity: entry.identity,
    );
    formula.domainMinController.text = entry.domainMinExpression.isNotEmpty
        ? entry.domainMinExpression
        : entry.domainMin?.toString() ?? '';
    formula.domainMaxController.text = entry.domainMaxExpression.isNotEmpty
        ? entry.domainMaxExpression
        : entry.domainMax?.toString() ?? '';
    formula.includeDomainMin = entry.includeDomainMin;
    formula.includeDomainMax = entry.includeDomainMax;
    return formula;
  }

  void _dismissKeyboard() {
    unawaited(_activeEditor?.dismiss());
    setState(() => _keyboardVisible = false);
  }

  Future<void> _setActiveView(ViewMode view) async {
    final isAvailable = switch (view) {
      ViewMode.mode2D => widget.options.show2D,
      ViewMode.mode3D => widget.options.show3D,
    };
    if (!isAvailable || view == _currentView) return;
    _dismissKeyboard();
    await _flushEditors();
    if (!mounted) return;
    setState(() {
      _currentView = view;
      _tabController.index = view == ViewMode.mode2D ? 0 : 1;
    });
    _syncController();
    widget.controller?.onViewChanged?.call(view);
  }

  void _setFormulaExpression(int index, String expression) {
    if (index < 0 || index >= _formulas.length) return;
    final formula = _formulas[index];
    if (formula.controller.text == expression) return;
    setState(() => formula.controller.text = expression);
    _syncController();
    widget.controller?.onFormulaEdited?.call(index, expression);
  }

  void _activateFormulaByIndex(int index) {
    if (index < 0 || index >= _formulas.length) return;
    final formula = _formulas[index];
    if (_mathMode) {
      _activateFormula(formula);
    } else {
      _setMode(true, formula);
    }
  }

  void _select3DTool(ConstructionTool tool) {
    if (ToolInfo.all[tool]!.behavior == ToolBehavior.command) {
      _canvas3DKey.currentState?.performToolCommand(tool);
      return;
    }
    _setActiveTool(tool);
  }

  void _setPolygonSides(int sides) {
    setState(() => _polygonSides = sides);
  }

  MathWorkspaceRegionActions get _regionActions {
    final parameterNames = _activeParameterNames.toList()..sort();
    final editor = _activeEditor;
    return MathWorkspaceRegionActions(
      activeView: _currentView,
      setActiveView: _setActiveView,
      active3DTool: _current3DTool,
      formulaCount: _formulas.length,
      polygonSides: _polygonSides,
      toolInstruction: _current3DTool == ConstructionTool.move
          ? null
          : (_canvas3DKey.currentState?.constructionInstruction ??
                _toolInstruction),
      parameters: {for (final name in parameterNames) name: _parameters[name]!},
      editorReady: editor?.ready ?? _fallbackEditorAvailable,
      supportsStructuralNavigation:
          editor?.supportsStructuralNavigation ?? false,
      supportsStructuredEditing: editor?.supportsStructuredEditing ?? false,
      activeFormulaLabel: _activeFormula == null
          ? null
          : '公式 ${_formulas.indexOf(_activeFormula!) + 1}',
      editorLocation:
          editor?.location ?? (_fallbackEditorAvailable ? '公式' : null),
      select3DTool: _select3DTool,
      setPolygonSides: _setPolygonSides,
      setFormulaExpression: _setFormulaExpression,
      formulaExpression: (index) => index >= 0 && index < _formulas.length
          ? _formulas[index].controller.text
          : null,
      addFormula: _addFormula,
      activateFormula: _activateFormulaByIndex,
      toggleFormulaVisibility: _toggleVisibility,
      removeFormula: (index) {
        if (index >= 0 && index < _formulas.length) {
          _confirmRemove(_formulas[index]);
        }
      },
      plot: _plotAll,
      setParameter: _updateParameter,
      dismissKeyboard: _dismissKeyboard,
      sendEditorCommand: _sendEditorCommand,
      fit2DCanvas: () => _canvasKey.currentState?.fitToView(),
      zoomIn2DCanvas: () => _canvasKey.currentState?.zoomIn(),
      zoomOut2DCanvas: () => _canvasKey.currentState?.zoomOut(),
      fit3DCanvas: () => _canvas3DKey.currentState?.fitToView(),
      zoomIn3DCanvas: () => _canvas3DKey.currentState?.zoomIn(),
      zoomOut3DCanvas: () => _canvas3DKey.currentState?.zoomOut(),
    );
  }

  Future<void> _onTabChanged() async {
    if (!widget.options.show2D || !widget.options.show3D) return;
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
    final endpointParameters = _formulas
        .where((f) => f.visible && f.controller.text.trim().isNotEmpty)
        .expand((f) => [f.domainMinController.text, f.domainMaxController.text])
        .where((input) => input.trim().isNotEmpty)
        .expand((input) => MathExpression.fromInput(input).parameters)
        .where((name) => name != 'x' && name != 'y');
    for (final name in endpointParameters) {
      _parameters.putIfAbsent(name, MathParameter.new);
    }
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
      final lower = f.domainMinController.text.trim();
      final upper = f.domainMaxController.text.trim();
      for (final endpoint in [lower, upper].where((value) => value.isNotEmpty)) {
        final endpointExpression = MathExpression.fromInput(endpoint);
        if (!endpointExpression.isValid) {
          _showError('定义域端点无法解析，请检查表达式。');
          return;
        }
        if (RegExp(r'\b[xy]\b').hasMatch(endpointExpression.normalizedExpression)) {
          _showError('定义域端点不能依赖坐标变量 x 或 y。');
          return;
        }
      }
      final lowerValue = _resolveDomainEndpoint(lower);
      final upperValue = _resolveDomainEndpoint(upper);
      if ((lower.isNotEmpty && lowerValue == null) ||
          (upper.isNotEmpty && upperValue == null)) {
        _showError('定义域端点必须计算为有限数值。');
        return;
      }
      final hasAdjustableEndpoint = [lower, upper]
          .where((input) => input.isNotEmpty)
          .expand((input) => MathExpression.fromInput(input).parameters)
          .any((name) => name != 'x' && name != 'y');
      if (lowerValue != null &&
          upperValue != null &&
          lowerValue >= upperValue &&
          !hasAdjustableEndpoint) {
        _showError('定义域左端点必须小于右端点。');
        return;
      }
      entries.add(
        FormulaEntry(
          rawExpression: text,
          parsed: parsed,
          color: f.color,
          autoColor: f.autoColor,
          domainMinExpression: lower,
          domainMaxExpression: upper,
          identity: f.identity,
          includeDomainMin: f.includeDomainMin,
          includeDomainMax: f.includeDomainMax,
          domainMin: lowerValue,
          domainMax: upperValue,
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
        ...entries
            .expand((entry) => [entry.domainMinExpression, entry.domainMaxExpression])
            .where((input) => input.isNotEmpty)
            .expand((input) => MathExpression.fromInput(input).parameters)
            .where((name) => name != 'x' && name != 'y'),
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
    if (_hasInvalidDomainOrder()) {
      _showError('参数当前值使定义域无效，请调整参数范围。');
    }
  }

  double? _resolveDomainEndpoint(String input) {
    if (input.trim().isEmpty) return null;
    final expression = MathExpression.fromInput(input);
    if (!expression.isValid) return null;
    final values = {
      for (final name in expression.parameters)
        if (_parameters.containsKey(name)) name: _parameters[name]!.value,
    };
    try {
      final value = expression.withParameters(values).evaluator(0);
      return value.isFinite ? value : null;
    } catch (_) {
      return null;
    }
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
          domainMin: _resolveDomainEndpoint(entry.domainMinExpression),
          domainMax: _resolveDomainEndpoint(entry.domainMaxExpression),
          clearDomainMin: entry.domainMinExpression.isNotEmpty &&
              _resolveDomainEndpoint(entry.domainMinExpression) == null,
          clearDomainMax: entry.domainMaxExpression.isNotEmpty &&
              _resolveDomainEndpoint(entry.domainMaxExpression) == null,
        ),
    ];
    _canvasKey.currentState?.setFormulas(entries);
  }

  void _updateParameter(String name, MathParameter parameter) {
    if (!mounted || !_activeParameterNames.contains(name)) return;
    final wasInvalid = _hasInvalidDomainOrder();
    setState(() => _parameters[name] = parameter);
    _refreshParameterCurves();
    if (!wasInvalid && _hasInvalidDomainOrder()) {
      _showError('参数变化后，定义域端点或范围无效。');
    }
    _syncController();
    widget.controller?.onParameterChanged?.call(name, parameter);
  }

  bool _hasInvalidDomainOrder() {
    for (final entry in _plottedFormulas) {
      final lower = _resolveDomainEndpoint(entry.domainMinExpression);
      final upper = _resolveDomainEndpoint(entry.domainMaxExpression);
      if ((entry.domainMinExpression.isNotEmpty && lower == null) ||
          (entry.domainMaxExpression.isNotEmpty && upper == null)) {
        return true;
      }
      if (lower != null && upper != null && lower >= upper) return true;
    }
    return false;
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

  Future<void> _editDomain(_FormulaState formula, int index) async {
    final result = await showDialog<(String, String, bool, bool)?>(
      context: context,
      builder: (_) => _DomainEditorDialog(
        title: '公式 ${index + 1} 定义域',
        lowerExpression: formula.domainMinController.text,
        upperExpression: formula.domainMaxController.text,
        includeLower: formula.includeDomainMin,
        includeUpper: formula.includeDomainMax,
        mathematical: _mathMode,
        showWebView: widget.initialShowWebView,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        formula.domainMinController.text = result.$1;
        formula.domainMaxController.text = result.$2;
        formula.includeDomainMin = result.$3;
        formula.includeDomainMax = result.$4;
      });
      if (formula.committedText.isNotEmpty) {
        _plotAll();
      } else {
        _syncController();
      }
    }
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
      _formulas[index].domainMinController.dispose();
      _formulas[index].domainMaxController.dispose();
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
      builder: (ctx) => widget.options.presentation.buildDialog(
        ctx,
        AlertDialog(
          title: Text(
            widget.options.presentation.labels.resolve(
              widget.options.presentation.labels.removeFormulaTitle,
            ),
          ),
          content: Text(
            widget.options.presentation.labels.withIndex(
              widget.options.presentation.labels.confirmRemoveFormula,
              index + 1,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                widget.options.presentation.labels.resolve(
                  widget.options.presentation.labels.cancel,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _removeFormula(removing);
              },
              child: Text(
                widget.options.presentation.labels.resolve(
                  widget.options.presentation.labels.removeFormula,
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
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
      builder: (ctx) => widget.options.presentation.buildDialog(
        ctx,
        AlertDialog(
          title: Text(
            widget.options.presentation.labels.resolve(
              widget.options.presentation.labels.selectColorTitle,
            ),
          ),
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
                      label: widget.options.presentation.labels.withIndex(
                        widget.options.presentation.labels.formulaColorLabel,
                        swatchIndex + 1,
                      ),
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
              child: Text(
                widget.options.presentation.labels.resolve(
                  widget.options.presentation.labels.cancel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    _plotError = msg;
    widget.controller?.onError?.call(msg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: widget.options.presentation.buildError(
          context,
          widget.options.presentation.labels.resolve(msg),
        ),
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
    final labels = widget.options.presentation.labels;

    final defaultAppBar = AppBar(
      title: Text(labels.resolve(labels.pageTitle)),
      actions: [
        IconButton(
          icon: Icon(Icons.add, size: 24, color: cs.primary),
          tooltip: labels.resolve(labels.addFormula),
          onPressed: _addFormula,
        ),
      ],
    );
    final appBar =
        widget.options.appBarBuilder?.call(
          context,
          widget.options.showAppBar
              ? defaultAppBar
              : const PreferredSize(
                  preferredSize: Size.zero,
                  child: SizedBox.shrink(),
                ),
        ) ??
        defaultAppBar;

    final workspace = LayoutBuilder(
      builder: (context, constraints) {
        final compact = widget.options.presentation.isCompactForWidth(
          constraints.maxWidth,
        );
        final hasViewSelector =
            widget.options.show2D &&
            widget.options.show3D &&
            (widget.options.showViewSelector ||
                widget.options.viewSelectorBuilder != null);
        final availableHeight =
            (constraints.maxHeight - (hasViewSelector ? 48 : 0))
                .clamp(0.0, double.infinity)
                .toDouble();
        final formulaListBaseHeight =
            availableHeight *
            (_keyboardVisible
                ? (compact ? 0.24 : 0.28)
                : (compact ? 0.32 : 0.4));
        final keyboardBaseHeight = _keyboardVisible
            ? availableHeight * (compact ? 0.5 : 0.56)
            : 0.0;
        final keyboardMaxHeight = keyboardBaseHeight;

        return Column(
          children: [
            if (hasViewSelector)
              _workspaceRegion(
                widget.options.viewSelectorBuilder,
                widget.options.showViewSelector
                    ? _buildTabBar(cs)
                    : const SizedBox.shrink(),
              ),
            if (widget.options.showFormulaEditor ||
                widget.options.showParameterControls ||
                widget.options.formulaEditorBuilder != null ||
                widget.options.parameterControlsBuilder != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: formulaListBaseHeight),
                child: _buildFormulaPanel(cs),
              ),
            Expanded(child: _buildAvailableCanvases(cs)),
            if (_keyboardVisible &&
                (widget.options.showKeyboard ||
                    widget.options.keyboardBuilder != null) &&
                _activeFormula != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: keyboardMaxHeight),
                child: _workspaceRegion(
                  widget.options.keyboardBuilder,
                  widget.options.showKeyboard
                      ? _buildKeyboard()
                      : const SizedBox.shrink(),
                ),
              ),
            if (_keyboardVisible && _activeFormula != null)
              _buildFallbackEditor(),
          ],
        );
      },
    );

    return PopScope(
      canPop: !_keyboardVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _keyboardVisible) _dismissKeyboard();
      },
      child: widget.options.showScaffold
          ? Scaffold(
              appBar:
                  widget.options.showAppBar ||
                      widget.options.appBarBuilder != null
                  ? appBar
                  : null,
              body: workspace,
            )
          : workspace,
    );
  }

  Widget _workspaceRegion(
    MathWorkspaceRegionBuilder? builder,
    Widget defaultContent,
  ) => builder?.call(context, defaultContent, _regionActions) ?? defaultContent;

  Widget _buildFormulaPanel(ColorScheme cs) {
    final formulaBuilder = widget.options.formulaEditorBuilder;
    if (formulaBuilder == null) return _buildFormulaList(cs);

    final parameterControls = _buildParameterControls(cs);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: _workspaceRegion(
            formulaBuilder,
            widget.options.showFormulaEditor
                ? _buildFormulaList(cs, includeParameters: false)
                : const SizedBox.shrink(),
          ),
        ),
        if (parameterControls != null) parameterControls,
      ],
    );
  }

  Widget _buildAvailableCanvases(ColorScheme cs) {
    if (widget.options.show2D && widget.options.show3D) {
      return IndexedStack(
        index: _currentView == ViewMode.mode2D ? 0 : 1,
        children: [_buildCanvas(cs), _build3DCanvas(cs)],
      );
    }
    return widget.options.show2D ? _buildCanvas(cs) : _build3DCanvas(cs);
  }

  Widget _buildKeyboard() {
    final editor = _activeEditor;
    return MathKeyboard(
      enabled: editor?.ready ?? _fallbackEditorAvailable,
      supportsStructuralNavigation:
          editor?.supportsStructuralNavigation ?? false,
      supportsStructuredEditing: editor?.supportsStructuredEditing ?? false,
      activeLabel: widget.options.presentation.labels.withIndex(
        widget.options.presentation.labels.formulaLabel,
        _formulas.indexOf(_activeFormula!) + 1,
      ),
      location: widget.options.presentation.labels.resolve(
        editor?.location ?? '公式',
      ),
      onCommand: _sendEditorCommand,
      onDismiss: _dismissKeyboard,
      onPlot: _plotAll,
      labelResolver: widget.options.presentation.labels.resolve,
      dialogBuilder: widget.options.presentation.buildDialog,
      persistenceEnabled: widget.options.persistence.enabled,
      preferenceNamespace: widget.options.persistence.namespace,
    );
  }

  Widget _buildFallbackEditor() => Offstage(
    offstage: true,
    child: Material(
      type: MaterialType.transparency,
      child: MathFormulaField(
        key: _fallbackEditorKey,
        controller: _activeFormula!.controller,
        mathematical: true,
        allowModeSwitch: false,
        showWebView: false,
        label: widget.options.presentation.labels.withIndex(
          widget.options.presentation.labels.formulaLabel,
          _formulas.indexOf(_activeFormula!) + 1,
        ),
        labelResolver: widget.options.presentation.labels.resolve,
        errorBuilder: widget.options.presentation.errorBuilder,
        onModeChanged: (_) {},
        onActivate: () => _activateFormula(_activeFormula!),
        onChanged: () {
          if (mounted) setState(() {});
        },
        onSubmitted: _plotAll,
        onReadyChanged: () {
          if (mounted) setState(() {});
        },
        onCaretChanged: () {
          if (mounted) setState(() {});
        },
      ),
    ),
  );

  MathFormulaFieldState? get _activeEditor =>
      _activeFormula?.editorKey.currentState ?? _fallbackEditorKey.currentState;

  bool get _fallbackEditorAvailable =>
      _keyboardVisible && _activeFormula != null;

  Future<void> _sendEditorCommand(String kind, String value) async {
    final formula = _activeFormula;
    final editor =
        formula?.editorKey.currentState ?? _fallbackEditorKey.currentState;
    if (kind == 'clipboard') {
      try {
        await editor?.clipboard(
          value,
          isTargetActive: () => mounted && _activeFormula == formula,
          clipboardReader: widget.options.clipboardReader,
          clipboardWriter: widget.options.clipboardWriter,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: widget.options.presentation.buildError(
              context,
              '剪贴板操作失败：$error',
            ),
          ),
        );
      }
    } else {
      await editor?.command(kind, value);
    }
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      child: TabBar(
        controller: _tabController,
        tabs: [
          Tab(
            child: Semantics(
              label: widget.options.presentation.labels.resolve(
                widget.options.presentation.labels.view2D,
              ),
              button: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, size: 18),
                  SizedBox(width: 6),
                  Text(
                    widget.options.presentation.labels.resolve(
                      widget.options.presentation.labels.view2D,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Tab(
            child: Semantics(
              label: widget.options.presentation.labels.resolve(
                widget.options.presentation.labels.view3D,
              ),
              button: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.view_in_ar, size: 18),
                  SizedBox(width: 6),
                  Text(
                    widget.options.presentation.labels.resolve(
                      widget.options.presentation.labels.view3D,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // Formula list
  // ==================================================================

  Widget _buildFormulaList(ColorScheme cs, {bool includeParameters = true}) {
    final parameterNames = _activeParameterNames.toList()..sort();
    final showParameters =
        includeParameters &&
        (widget.options.showParameterControls ||
            widget.options.parameterControlsBuilder != null) &&
        _currentView == ViewMode.mode2D &&
        parameterNames.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      shrinkWrap: true,
      controller: _formulaScroll,
      physics: const ClampingScrollPhysics(),
      itemCount:
          (widget.options.showFormulaEditor ? _formulas.length : 0) +
          (showParameters ? 1 : 0),
      itemBuilder: (_, index) =>
          widget.options.showFormulaEditor && index < _formulas.length
          ? _buildFormulaRow(cs, index)
          : _workspaceRegion(
              widget.options.parameterControlsBuilder,
              widget.options.showParameterControls
                  ? MathParameterControls(
                      key: const ValueKey('math-parameter-controls'),
                      parameters: {
                        for (final name in parameterNames)
                          name: _parameters[name]!,
                      },
                      onChanged: _updateParameter,
                      labelResolver: widget.options.presentation.labels.resolve,
                      dialogBuilder: widget.options.presentation.buildDialog,
                      errorBuilder: widget.options.presentation.errorBuilder,
                    )
                  : const SizedBox.shrink(),
            ),
    );
  }

  Widget? _buildParameterControls(ColorScheme cs) {
    final parameterNames = _activeParameterNames.toList()..sort();
    final showParameters =
        (widget.options.showParameterControls ||
            widget.options.parameterControlsBuilder != null) &&
        _currentView == ViewMode.mode2D &&
        parameterNames.isNotEmpty;
    if (!showParameters) return null;

    return _workspaceRegion(
      widget.options.parameterControlsBuilder,
      widget.options.showParameterControls
          ? MathParameterControls(
              key: const ValueKey('math-parameter-controls'),
              parameters: {
                for (final name in parameterNames) name: _parameters[name]!,
              },
              onChanged: _updateParameter,
              labelResolver: widget.options.presentation.labels.resolve,
              dialogBuilder: widget.options.presentation.buildDialog,
              errorBuilder: widget.options.presentation.errorBuilder,
            )
          : const SizedBox.shrink(),
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
              label: widget.options.presentation.labels.withIndex(
                widget.options.presentation.labels.formulaLabel,
                index + 1,
              ),
              labelResolver: widget.options.presentation.labels.resolve,
              errorBuilder: widget.options.presentation.errorBuilder,
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
            icon: Icons.tune,
            iconSize: 18,
            color: cs.onSurfaceVariant,
            tooltip: '设置定义域',
            onPressed: () => _editDomain(f, index),
          ),
          _buildActionButton(
            icon: f.visible ? Icons.visibility : Icons.visibility_off,
            iconSize: 20,
            color: f.visible ? cs.onSurface : cs.onSurfaceVariant,
            tooltip: f.visible
                ? widget.options.presentation.labels.resolve(
                    widget.options.presentation.labels.hideFormula,
                  )
                : widget.options.presentation.labels.resolve(
                    widget.options.presentation.labels.showFormula,
                  ),
            onPressed: () => _toggleVisibility(index),
          ),

          // ---- Remove formula (X) button ----
          if (_formulas.length > 1)
            _buildActionButton(
              icon: Icons.remove_circle_outline,
              iconSize: 16,
              color: cs.error.withValues(alpha: 0.7),
              tooltip: widget.options.presentation.labels.resolve(
                widget.options.presentation.labels.removeFormulaTooltip,
              ),
              onPressed: () => _confirmRemove(f),
            ),

          // ---- Plot (✓) button ----
          _buildActionButton(
            icon: Icons.check_circle_outline,
            iconSize: 20,
            color: hasChanged
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.2),
            tooltip: widget.options.presentation.labels.resolve(
              widget.options.presentation.labels.plotFormula,
            ),
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
    final defaultActions = _workspaceRegion(
      widget.options.canvas2DActionsBuilder,
      widget.options.show2DCanvasActions
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _floatingControl(
                  icon: Icons.filter_center_focus,
                  tooltip: widget.options.presentation.labels.resolve(
                    widget.options.presentation.labels.fit2DCanvas,
                  ),
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
                  tooltip: widget.options.presentation.labels.resolve(
                    widget.options.presentation.labels.zoomIn,
                  ),
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
                  tooltip: widget.options.presentation.labels.resolve(
                    widget.options.presentation.labels.zoomOut,
                  ),
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
            )
          : const SizedBox.shrink(),
    );
    final defaultOverlay =
        widget.options.show2DCanvasActions ||
            widget.options.canvas2DActionsBuilder != null
        ? Positioned(
            left:
                widget.options.presentation.controlPlacement ==
                    MathWorkspaceControlPlacement.bottomStart
                ? widget.options.presentation.controlInset.left
                : null,
            right:
                widget.options.presentation.controlPlacement ==
                    MathWorkspaceControlPlacement.bottomEnd
                ? widget.options.presentation.controlInset.right
                : null,
            bottom: widget.options.presentation.controlInset.bottom,
            child: defaultActions,
          )
        : const SizedBox.shrink();
    return Padding(
      padding: widget.options.presentation.canvasInset2D,
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
                  allowTouchGestures: widget
                      .options
                      .presentation
                      .interactionPolicy
                      .allowTouchGestures,
                  allowMouseGestures: widget
                      .options
                      .presentation
                      .interactionPolicy
                      .allowMouseGestures,
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
                          content: widget.options.presentation.buildError(
                            context,
                            widget.options.presentation.labels.resolve(msg),
                          ),
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
          _workspaceRegion(
            widget.options.canvas2DOverlayBuilder,
            defaultOverlay,
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
      padding: EdgeInsets.only(
        top: widget.options.presentation.density == MathWorkspaceDensity.compact
            ? 4
            : 8,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(
            icon,
            size:
                widget.options.presentation.density ==
                    MathWorkspaceDensity.compact
                ? 19
                : 21,
          ),
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize:
                widget.options.presentation.density ==
                    MathWorkspaceDensity.compact
                ? const Size(36, 36)
                : const Size(40, 40),
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
        if (widget.options.show3DTools ||
            widget.options.threeDToolsBuilder != null)
          _workspaceRegion(
            widget.options.threeDToolsBuilder,
            widget.options.show3DTools
                ? Math3DToolbar(
                    activeTool: _current3DTool,
                    polygonSides: _polygonSides,
                    labelResolver: widget.options.presentation.labels.resolve,
                    onPolygonSidesChanged: (sides) =>
                        setState(() => _polygonSides = sides),
                    instruction: _current3DTool != ConstructionTool.move
                        ? (_canvas3DKey.currentState?.constructionInstruction ??
                              _toolInstruction)
                        : null,
                    onToolSelected: (tool) {
                      if (ToolInfo.all[tool]!.behavior ==
                          ToolBehavior.command) {
                        _canvas3DKey.currentState?.performToolCommand(tool);
                        return;
                      }
                      _setActiveTool(tool);
                    },
                  )
                : const SizedBox.shrink(),
          ),
        // 3D canvas
        Expanded(
          child: Padding(
            padding: widget.options.presentation.canvasInset3D,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant, width: 0.5),
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MathCanvas3D(
                        key: _canvas3DKey,
                        currentTool: _current3DTool,
                        polygonSides: _polygonSides,
                        allowTouchGestures: widget
                            .options
                            .presentation
                            .interactionPolicy
                            .allowTouchGestures,
                        allowMouseGestures: widget
                            .options
                            .presentation
                            .interactionPolicy
                            .allowMouseGestures,
                        labelResolver:
                            widget.options.presentation.labels.resolve,
                        dialogBuilder: widget.options.presentation.buildDialog,
                        errorBuilder: widget.options.presentation.errorBuilder,
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
                    Positioned.fill(
                      child: _workspaceRegion(
                        widget.options.canvas3DOverlayBuilder,
                        const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DomainEditorDialog extends StatefulWidget {
  final String title;
  final String lowerExpression;
  final String upperExpression;
  final bool includeLower;
  final bool includeUpper;
  final bool mathematical;
  final bool showWebView;

  const _DomainEditorDialog({
    required this.title,
    required this.lowerExpression,
    required this.upperExpression,
    required this.includeLower,
    required this.includeUpper,
    required this.mathematical,
    required this.showWebView,
  });

  @override
  State<_DomainEditorDialog> createState() => _DomainEditorDialogState();
}

class _DomainEditorDialogState extends State<_DomainEditorDialog> {
  final GlobalKey<MathFormulaFieldState> _lowerEditorKey =
      GlobalKey<MathFormulaFieldState>();
  final GlobalKey<MathFormulaFieldState> _upperEditorKey =
      GlobalKey<MathFormulaFieldState>();
  late final TextEditingController _lower;
  late final TextEditingController _upper;
  late bool _mathematical;
  late bool _includeLower;
  late bool _includeUpper;
  bool _keyboardVisible = false;
  bool _editingLower = true;

  @override
  void initState() {
    super.initState();
    _lower = TextEditingController(text: widget.lowerExpression);
    _upper = TextEditingController(text: widget.upperExpression);
    _mathematical = widget.mathematical;
    _includeLower = widget.includeLower;
    _includeUpper = widget.includeUpper;
  }

  @override
  void dispose() {
    _lower.dispose();
    _upper.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await _lowerEditorKey.currentState?.flush();
    await _upperEditorKey.currentState?.flush();
    if (!mounted) return;
    Navigator.pop(context, (
      _lower.text,
      _upper.text,
      _includeLower,
      _includeUpper,
    ));
  }

  void _openEndpointKeyboard() => setState(() {
    _editingLower = true;
    _keyboardVisible = _mathematical;
  });

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = (viewportHeight - 250).clamp(220.0, 420.0);
    return Dialog(
      child: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: viewportHeight * 0.9),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('源码输入')),
                      ButtonSegment(value: true, label: Text('数学键盘输入')),
                    ],
                    selected: {_mathematical},
                    onSelectionChanged: (selection) => setState(() {
                      _mathematical = selection.first;
                      if (!_mathematical) _keyboardVisible = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Tooltip(
                        message: _includeLower
                            ? '包含左端点；点击改为开区间'
                            : '不包含左端点；点击改为闭区间',
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _includeLower = !_includeLower),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(36, 48),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            _includeLower ? '[' : '(',
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            MathFormulaField(
                              key: _lowerEditorKey,
                              controller: _lower,
                              mathematical: _mathematical,
                              allowModeSwitch: false,
                              showWebView: widget.showWebView,
                              onReadyChanged: () {
                                if (mounted) setState(() {});
                              },
                              label: _lower.text.isEmpty ? '−∞' : '左端点',
                              onModeChanged: (_) {},
                              onActivate: () => setState(() {
                                _editingLower = true;
                                _keyboardVisible = _mathematical;
                              }),
                              onChanged: () => setState(() {}),
                              onSubmitted: () {},
                            ),
                            if (_mathematical && _lower.text.isEmpty)
                              Positioned(
                                left: 8,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow,
                                    ),
                                    child: Text(
                                      '−∞',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(',', style: TextStyle(fontSize: 22)),
                      ),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            MathFormulaField(
                              key: _upperEditorKey,
                              controller: _upper,
                              mathematical: _mathematical,
                              allowModeSwitch: false,
                              showWebView: widget.showWebView,
                              onReadyChanged: () {
                                if (mounted) setState(() {});
                              },
                              label: _upper.text.isEmpty ? '+∞' : '右端点',
                              onModeChanged: (_) {},
                              onActivate: () => setState(() {
                                _editingLower = false;
                                _keyboardVisible = _mathematical;
                              }),
                              onChanged: () => setState(() {}),
                              onSubmitted: () {},
                            ),
                            if (_mathematical && _upper.text.isEmpty)
                              Positioned(
                                left: 8,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow,
                                    ),
                                    child: Text(
                                      '+∞',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: _includeUpper
                            ? '包含右端点；点击改为开区间'
                            : '不包含右端点；点击改为闭区间',
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _includeUpper = !_includeUpper),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(36, 48),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            _includeUpper ? ']' : ')',
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('空端点表示无界区间；端点支持公式参数。'),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('点击括号切换开闭区间。'),
                  ),
                  if (_mathematical)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openEndpointKeyboard,
                        icon: const Icon(Icons.keyboard),
                        label: const Text('打开端点数学键盘'),
                      ),
                    ),
                  if (_mathematical && _keyboardVisible)
                    SizedBox(
                      height: keyboardHeight,
                      child: MathKeyboard(
                        enabled:
                            (_editingLower
                                    ? _lowerEditorKey.currentState
                                    : _upperEditorKey.currentState)
                                ?.ready ??
                            false,
                        supportsStructuralNavigation:
                            (_editingLower
                                    ? _lowerEditorKey.currentState
                                    : _upperEditorKey.currentState)
                                ?.supportsStructuralNavigation ??
                            false,
                        supportsStructuredEditing:
                            (_editingLower
                                    ? _lowerEditorKey.currentState
                                    : _upperEditorKey.currentState)
                                ?.supportsStructuredEditing ??
                            false,
                        activeLabel: _editingLower ? '左端点' : '右端点',
                        location:
                            (_editingLower
                                    ? _lowerEditorKey.currentState
                                    : _upperEditorKey.currentState)
                                ?.location ??
                            '定义域端点',
                        onCommand: (kind, value) async {
                          final editor = (_editingLower
                              ? _lowerEditorKey.currentState
                              : _upperEditorKey.currentState);
                          await editor?.command(kind, value);
                        },
                        onDismiss: () =>
                            setState(() => _keyboardVisible = false),
                        onPlot: _apply,
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _apply, child: const Text('应用')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// State for a single formula row.
class _FormulaState {
  static int _nextIdentity = 0;

  final String identity;
  final TextEditingController controller;
  final TextEditingController domainMinController = TextEditingController();
  final TextEditingController domainMaxController = TextEditingController();
  final GlobalKey rowKey = GlobalKey();
  final GlobalKey<MathFormulaFieldState> editorKey = GlobalKey();
  Color color;
  bool autoColor;
  String committedText;
  bool visible;
  bool includeDomainMin = true;
  bool includeDomainMax = true;

  _FormulaState({
    required this.controller,
    required this.color,
    String? identity,
    this.autoColor = true,
    this.visible = true,
  }) : identity = identity ?? 'formula-${_nextIdentity++}',
       committedText = '';
}
