import 'dart:async';
import 'dart:math' as dart_math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/math_3d_object.dart';
import '../models/math_3d_tool.dart';
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

  /// Creates a math workspace.
  const MathDrawingPage({
    super.key,
    this.initialExpression,
    this.initialShowWebView = true,
    this.initialMathematicalMode,
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
    if (view == ViewMode.mode2D) {
      _plotAll2D();
    } else {
      _plotAll3D();
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
      _showError('参数变化后，定义域左端点必须小于右端点。');
    }
  }

  bool _hasInvalidDomainOrder() {
    for (final entry in _plottedFormulas) {
      final lower = _resolveDomainEndpoint(entry.domainMinExpression);
      final upper = _resolveDomainEndpoint(entry.domainMaxExpression);
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
      if (formula.committedText.isNotEmpty) _plotAll();
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
              onChanged: () => setState(() {}),
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
                  onReady: () => debugPrint('[MathDrawing] Canvas ready'),
                  onError: (msg) {
                    debugPrint('[MathDrawing] Canvas error: $msg');
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
                  onPressed: () => _canvasKey.currentState?.fitToView(),
                ),
                _floatingControl(
                  icon: Icons.zoom_in,
                  tooltip: '放大',
                  onPressed: () => _canvasKey.currentState?.zoomIn(),
                ),
                _floatingControl(
                  icon: Icons.zoom_out,
                  tooltip: '缩小',
                  onPressed: () => _canvasKey.currentState?.zoomOut(),
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
            setState(() {
              _current3DTool = tool;
              _toolInstruction = '';
            });
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
                  onReady: () {},
                  onViewportChange: () {},
                  onObjectCreated: (obj) {
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
    final keyboardHeight = (viewportHeight - 340).clamp(220.0, 420.0);
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
    this.autoColor = true,
    this.visible = true,
  }) : identity = 'formula-${_nextIdentity++}',
       committedText = '';
}
