import 'dart:async';
import 'dart:math' as dart_math;

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/math_3d_object.dart';
import '../models/math_3d_scene.dart';
import '../models/math_3d_tool.dart';
import '../models/math_drawing_controller.dart';
import '../models/math_drawing_document.dart';
import '../models/math_drawing_storage.dart';
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

  /// Saved document to open when the workspace is first created.
  final MathDrawingDocument? initialDocument;

  /// Whether to show the platform WebView editor when it is supported.
  final bool initialShowWebView;

  /// Initial input mode; defaults to the platform's supported editor mode.
  final bool? initialMathematicalMode;

  /// Optional host controller for formulas, canvas state, commands, and events.
  final MathDrawingController? controller;

  /// App-private drawing storage, replaceable by hosts with custom backends.
  final MathDrawingStorage documentStorage;

  /// Configures the available views and composable workspace regions.
  final MathWorkspaceOptions options;

  /// Creates a math workspace.
  const MathDrawingPage({
    super.key,
    this.initialExpression,
    this.initialDocument,
    this.initialShowWebView = true,
    this.initialMathematicalMode,
    this.controller,
    this.documentStorage = const MathDrawingStorage(),
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
  MathDrawingSnapshot? _restoredSnapshot;
  String? _currentDocumentName;
  Map<String, dynamic> _currentDocumentExtensions = const {};

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
    final document = widget.initialDocument;
    if (document != null) {
      _currentDocumentName = document.name;
      _currentDocumentExtensions = document.extensions;
      _restoreSnapshot(document.drawing);
    }
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
      for (final formula in _formulas) _formulaEntryForSnapshot(formula),
    ];
    final viewport =
        _canvasKey.currentState?.viewport ??
        (
          _restoredSnapshot?.viewport2D.xMin ?? -10.0,
          _restoredSnapshot?.viewport2D.yMin ?? -10.0,
          _restoredSnapshot?.viewport2D.xMax ?? 10.0,
          _restoredSnapshot?.viewport2D.yMax ?? 10.0,
        );
    _canvas3DKey.currentState?.ensureDocumentIds();
    return MathDrawingSnapshot(
      formulas: formulas,
      parameters: _parameters,
      activeView: _currentView,
      activeTool: _current3DTool,
      polygonSides3D: _polygonSides,
      viewport2D: Viewport(
        xMin: viewport.$1,
        yMin: viewport.$2,
        xMax: viewport.$3,
        yMax: viewport.$4,
      ),
      camera3D:
          _canvas3DKey.currentState?.camera ??
          _restoredSnapshot?.camera3D ??
          const Camera3D(),
      projection3D:
          _canvas3DKey.currentState?.projectionType ??
          _restoredSnapshot?.projection3D ??
          ProjectionType.parallel,
      showAxes3D:
          _canvas3DKey.currentState?.showAxes ??
          _restoredSnapshot?.showAxes3D ??
          true,
      showPlane3D:
          _canvas3DKey.currentState?.showPlane ??
          _restoredSnapshot?.showPlane3D ??
          true,
      showGrid3D:
          _canvas3DKey.currentState?.showGrid ??
          _restoredSnapshot?.showGrid3D ??
          false,
      showLabels3D:
          _canvas3DKey.currentState?.showLabels ??
          _restoredSnapshot?.showLabels3D ??
          true,
      scene3D:
          _canvas3DKey.currentState?.objects ??
          _restoredSnapshot?.scene3D ??
          const [],
      pointAttachments3D:
          _canvas3DKey.currentState?.documentPointAttachments ??
          _restoredSnapshot?.pointAttachments3D ??
          const [],
      constructionDependencies3D:
          _canvas3DKey.currentState?.documentConstructionDependencies ??
          _restoredSnapshot?.constructionDependencies3D ??
          const [],
      showAxes2D:
          _canvasKey.currentState?.showAxes ??
          _restoredSnapshot?.showAxes2D ??
          true,
      showGrid2D:
          _canvasKey.currentState?.showGrid ??
          _restoredSnapshot?.showGrid2D ??
          true,
      showZeros2D:
          _canvasKey.currentState?.showZeros ??
          _restoredSnapshot?.showZeros2D ??
          false,
      showExtrema2D:
          _canvasKey.currentState?.showExtrema ??
          _restoredSnapshot?.showExtrema2D ??
          false,
    );
  }

  FormulaEntry _formulaEntryForSnapshot(_FormulaState formula) {
    final parsed = MathExpression.fromInput(formula.controller.text);
    final parameterNames = {
      ...parsed.parameters,
      ..._domainParameterNames(
        formula.domainStartExpression,
        formula.domainEndExpression,
      ),
    };
    return FormulaEntry(
      id: formula.id,
      rawExpression: formula.controller.text,
      parsed: parsed,
      color: formula.color,
      autoColor: formula.autoColor,
      visible: formula.visible,
      domainStartExpression: formula.domainStartExpression,
      domainEndExpression: formula.domainEndExpression,
      includeDomainStart: formula.includeDomainStart,
      includeDomainEnd: formula.includeDomainEnd,
      parameterValues: {
        for (final name in parameterNames)
          if (_parameters.containsKey(name)) name: _parameters[name]!.value,
      },
    );
  }

  Set<String> _domainParameterNames(String? start, String? end) => {
    for (final source in [start, end])
      if (source != null && source.trim().isNotEmpty)
        ...MathExpression.fromInput(source).parameters
            .where((name) => name != 'x' && name != 'y'),
  };

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
    final previousSnapshot = controller.snapshot;
    final snapshot = _makeSnapshot();
    // Snapshot capture may assign stable document IDs and replace scene
    // objects with immutable copies. Compare the post-capture scene so that
    // this bookkeeping does not report one edit twice.
    final currentScene =
        _canvas3DKey.currentState?.objects ?? const <Object3D>[];
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
              id: entry.id.isEmpty ? null : entry.id,
              color: entry.color,
              autoColor: entry.autoColor,
              visible: entry.visible,
              domainStartExpression: entry.domainStartExpression ?? '',
              domainEndExpression: entry.domainEndExpression ?? '',
              includeDomainStart: entry.includeDomainStart,
              includeDomainEnd: entry.includeDomainEnd,
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
    _restoredSnapshot = snapshot;
    final controller = widget.controller;
    final restoredView = switch (snapshot.activeView) {
      ViewMode.mode2D when widget.options.show2D => ViewMode.mode2D,
      ViewMode.mode3D when widget.options.show3D => ViewMode.mode3D,
      _ => widget.options.initialView,
    };
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
              id: entry.id.isEmpty ? null : entry.id,
              color: entry.color,
              autoColor: entry.autoColor,
              visible: entry.visible,
              domainStartExpression: entry.domainStartExpression ?? '',
              domainEndExpression: entry.domainEndExpression ?? '',
              includeDomainStart: entry.includeDomainStart,
              includeDomainEnd: entry.includeDomainEnd,
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
      _currentView = restoredView;
      _current3DTool = snapshot.activeTool;
      _polygonSides = snapshot.polygonSides3D;
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
      _canvas3DKey.currentState?.setDisplaySettings(
        showAxes: snapshot.showAxes3D,
        showPlane: snapshot.showPlane3D,
        showGrid: snapshot.showGrid3D,
        showLabels: snapshot.showLabels3D,
      );
      _canvasKey.currentState?.setDisplaySettings(
        showAxes: snapshot.showAxes2D,
        showGrid: snapshot.showGrid2D,
        showZeros: snapshot.showZeros2D,
        showExtrema: snapshot.showExtrema2D,
      );
      _canvas3DKey.currentState?.setObjects(snapshot.scene3D);
      _canvas3DKey.currentState?.restoreDocumentRelationships(
        pointAttachments: snapshot.pointAttachments3D,
        constructionDependencies: snapshot.constructionDependencies3D,
      );
      _canvas3DKey.currentState?.setTool(snapshot.activeTool);
      _publish3DChange();
      _tabController.animateTo(restoredView == ViewMode.mode2D ? 0 : 1);
      _plottedFormulas = [];
      unawaited(_canvasKey.currentState?.setFormulas([]) ?? Future.value());
      if (restoredView == ViewMode.mode2D) {
        unawaited(_plotAll());
      } else {
        // Keep the offstage 2D canvas synchronized too, so switching views
        // after reopening a 3D drawing cannot reveal the previously open plot.
        _plotAll2D();
        _syncController();
      }
    });
    _syncController();
    controller?.publish(_makeSnapshot());
  }

  Future<String?> _askDocumentName() async {
    var value = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存绘图'),
        content: TextField(
          autofocus: true,
          onChanged: (text) => value = text,
          decoration: InputDecoration(
            labelText: '名称',
            hintText: _currentDocumentName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDrawing() async {
    await _flushEditors();
    if (!mounted) return;
    var name = await _askDocumentName();
    if (!mounted || name == null || name.isEmpty) return;
    final document = MathDrawingDocument(
      name: name,
      drawing: _makeSnapshot(),
      extensions: _currentDocumentExtensions,
    );
    try {
      await widget.documentStorage.save(document);
    } on DuplicateDrawingException {
      if (!mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同名绘图已存在'),
          content: Text('要覆盖“$name”吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
      try {
        await widget.documentStorage.save(document, overwrite: true);
      } catch (error) {
        _showError('无法保存绘图：$error');
        return;
      }
    } catch (error) {
      _showError('无法保存绘图：$error');
      return;
    }
    if (mounted) setState(() => _currentDocumentName = name);
  }

  Future<void> _openDrawingList() async {
    final List<String> names;
    try {
      names = await widget.documentStorage.listNames();
    } catch (error) {
      _showError('无法读取绘图列表：$error');
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('打开绘图'),
        children: names.isEmpty
            ? const [
                Padding(padding: EdgeInsets.all(20), child: Text('没有已保存的绘图')),
              ]
            : [
                for (final name in names)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, name),
                    child: Text(name),
                  ),
              ],
      ),
    );
    if (!mounted || selected == null) return;
    try {
      final document = await widget.documentStorage.load(selected);
      if (!mounted || document == null) return;
      _restoreSnapshot(document.drawing);
      setState(() {
        _currentDocumentName = document.name;
        _currentDocumentExtensions = document.extensions;
      });
    } catch (error) {
      if (!mounted) return;
      _showError('无法打开绘图：$error');
    }
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
    _syncController();
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
    for (final f in _formulas) {
      final text = f.controller.text.trim();
      if (text.isEmpty) continue;
      if (!f.visible) continue;

      final sourceExpression = MathExpression.fromInput(text);
      final domainParameters = _domainParameterNames(
        f.domainStartExpression,
        f.domainEndExpression,
      );
      final names = {...sourceExpression.parameters, ...domainParameters};
      final parameterValues = {
        for (final name in names)
          if (name != 'x' && name != 'y')
            name: (_parameters[name] ?? MathParameter()).value,
      };
      final parsed = MathExpression.fromInput(
        text,
        parameterValues: parameterValues,
      );
      if (!parsed.isValid) {
        _showError(
          text.contains(r'\placeholder')
              ? '公式仍有空槽，请填写后再绘图。'
              : '此公式暂不能绘图，编辑内容已保留。${parsed.parseError ?? ""}',
        );
        return;
      }
      final domainStart = _parseDomainBound(
        f.domainStartExpression,
        parameterValues,
      );
      final domainEnd = _parseDomainBound(
        f.domainEndExpression,
        parameterValues,
      );
      if ((f.domainStartExpression.trim().isNotEmpty && domainStart == null) ||
          (f.domainEndExpression.trim().isNotEmpty && domainEnd == null) ||
          (domainStart != null &&
              domainEnd != null &&
              domainStart >= domainEnd)) {
        _showError('定义域表达式无效或下界不小于上界，公式已保留。');
        return;
      }
      entries.add(
        FormulaEntry(
          rawExpression: text,
          parsed: parsed,
          color: f.color,
          autoColor: f.autoColor,
          parameterValues: parameterValues,
          domainStartExpression: f.domainStartExpression,
          domainEndExpression: f.domainEndExpression,
          includeDomainStart: f.includeDomainStart,
          includeDomainEnd: f.includeDomainEnd,
        ),
      );
    }
    // Mark all rows as committed
    setState(() {
      _activeParameterNames = {
        for (final entry in entries) ...{
          ...entry.parsed!.parameters.where(
            (name) => name != 'x' && name != 'y',
          ),
          ..._domainParameterNames(
            entry.domainStartExpression,
            entry.domainEndExpression,
          ),
        },
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
            for (final name in {
              ...entry.parsed!.parameters,
              ..._domainParameterNames(
                entry.domainStartExpression,
                entry.domainEndExpression,
              ),
            })
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

  double? _parseDomainBound(
    String source,
    Map<String, double> parameterValues,
  ) {
    if (source.trim().isEmpty) return null;
    final expression = MathExpression.fromInput(
      source,
      parameterValues: parameterValues,
    );
    if (!expression.isValid) return null;
    final value = expression.evaluator(0);
    return value.isFinite ? value : null;
  }

  Object3D? _sampleFormula3D(String text, int color) {
    final surface = Expression3D.surface(text);
    if (surface.isValid) {
      final mesh = surface.sampleSurfaceGrid(
        xMin: -5,
        xMax: 5,
        yMin: -5,
        yMax: 5,
        gridX: 30,
        gridY: 30,
      );
      if (mesh.vertices.isNotEmpty) {
        return Object3D.surface(
          vertices: mesh.vertices,
          indices: mesh.indices,
          normals: mesh.normals,
          color: color,
          opacity: 0.85,
          label: text,
        );
      }
    }
    final curve = Expression3D.parametricCurve(text, tMax: 2 * dart_math.pi);
    if (curve.isValid) {
      final points = <Point3D>[];
      final starts = <int>[];
      for (final segment in curve.sampleCurveSegments(numSamples: 100)) {
        if (segment.isEmpty) continue;
        if (points.isNotEmpty) starts.add(points.length);
        points.addAll(segment);
      }
      if (points.isNotEmpty) {
        return Object3D.curve(
          points: points,
          curveStarts: starts,
          color: color,
          label: text,
        );
      }
    }
    return null;
  }

  void _plotAll3D() {
    final objects = <Object3D>[];
    final current = _canvas3DKey.currentState?.objects ?? const <Object3D>[];
    final usedIds = current.map((object) => object.documentId).toSet();
    for (final f in _formulas) {
      final text = f.controller.text.trim();
      if (text.isEmpty) continue;
      if (!f.visible) continue;

      final object = _sampleFormula3D(text, f.color.toARGB32());
      if (object != null) {
        final previous = current.where((item) => item.formulaRowId == f.id);
        var id = previous.isEmpty
            ? 'formula-plot-3d:${f.id}'
            : previous.first.documentId;
        if (previous.isEmpty) {
          while (usedIds.contains(id)) {
            id = '$id:';
          }
        }
        usedIds.add(id);
        objects.add(object.copyWith(documentId: id, formulaRowId: f.id));
        continue;
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

    _canvas3DKey.currentState?.replaceFormulaObjects(objects);
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

  Future<void> _showFormulaDomain(int formulaIndex) async {
    final formula = _formulas[formulaIndex];
    var start = formula.domainStartExpression;
    var end = formula.domainEndExpression;
    var includeStart = formula.includeDomainStart;
    var includeEnd = formula.includeDomainEnd;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('公式 ${formulaIndex + 1} 定义域'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: start,
                decoration: const InputDecoration(labelText: '下界表达式'),
                onChanged: (value) => start = value,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含下界'),
                value: includeStart,
                onChanged: (value) =>
                    setDialogState(() => includeStart = value ?? false),
              ),
              TextFormField(
                initialValue: end,
                decoration: const InputDecoration(labelText: '上界表达式'),
                onChanged: (value) => end = value,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含上界'),
                value: includeEnd,
                onChanged: (value) =>
                    setDialogState(() => includeEnd = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      formula.domainStartExpression = start;
      formula.domainEndExpression = end;
      formula.includeDomainStart = includeStart;
      formula.includeDomainEnd = includeEnd;
    });
    await _plotAll();
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
          icon: const Icon(Icons.folder_open),
          tooltip: '打开绘图',
          onPressed: _openDrawingList,
        ),
        IconButton(
          icon: const Icon(Icons.save_outlined),
          tooltip: '保存绘图',
          onPressed: _saveDrawing,
        ),
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
          _buildActionButton(
            icon: Icons.tune,
            iconSize: 18,
            color: cs.onSurfaceVariant,
            tooltip: '设置公式定义域',
            onPressed: () => _showFormulaDomain(index),
          ),
          // Each action button carries a uniform 12px leading gap. This also
          // matches the left-side gap between the color circle and the input.
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
    void toggleDisplaySetting(String setting) {
      final canvas = _canvasKey.currentState;
      if (canvas == null) return;
      canvas.setDisplaySettings(
        showAxes: setting == 'axes' ? !canvas.showAxes : canvas.showAxes,
        showGrid: setting == 'grid' ? !canvas.showGrid : canvas.showGrid,
        showZeros: setting == 'zeros' ? !canvas.showZeros : canvas.showZeros,
        showExtrema: setting == 'extrema'
            ? !canvas.showExtrema
            : canvas.showExtrema,
      );
      _syncController();
    }

    final defaultActions = _workspaceRegion(
      widget.options.canvas2DActionsBuilder,
      widget.options.show2DCanvasActions
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: '2D显示设置',
                  onSelected: toggleDisplaySetting,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'axes',
                      child: Text(
                        '${_canvasKey.currentState?.showAxes == true ? '✓ ' : ''}坐标轴',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'grid',
                      child: Text(
                        '${_canvasKey.currentState?.showGrid == true ? '✓ ' : ''}网格',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'zeros',
                      child: Text(
                        '${_canvasKey.currentState?.showZeros == true ? '✓ ' : ''}零点',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'extrema',
                      child: Text(
                        '${_canvasKey.currentState?.showExtrema == true ? '✓ ' : ''}极值点',
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.tune),
                  ),
                ),
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
                    onPolygonSidesChanged: _setPolygonSides,
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

/// State for a single formula row.
class _FormulaState {
  static int _nextId = 0;
  static final Set<String> _knownIds = {};
  final String id;
  final TextEditingController controller;
  final GlobalKey rowKey = GlobalKey();
  final GlobalKey<MathFormulaFieldState> editorKey = GlobalKey();
  Color color;
  bool autoColor;
  String committedText;
  bool visible;
  String domainStartExpression;
  String domainEndExpression;
  bool includeDomainStart;
  bool includeDomainEnd;

  _FormulaState({
    required this.controller,
    required this.color,
    String? id,
    this.autoColor = true,
    this.visible = true,
    this.domainStartExpression = '',
    this.domainEndExpression = '',
    this.includeDomainStart = true,
    this.includeDomainEnd = true,
  }) : id = id ?? _newId(),
       committedText = '' {
    _knownIds.add(this.id);
  }

  static String _newId() {
    String candidate;
    do {
      candidate = 'row-${_nextId++}';
    } while (_knownIds.contains(candidate));
    return candidate;
  }
}
