import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/math_input_catalog.dart';
import 'math_ui_tokens.dart';

/// All editing is structural: templates use MathLive's selection/placeholder
/// arguments, and navigation operates on the rendered document, not text.
class MathKeyboard extends StatefulWidget {
  final Future<void> Function(String kind, String value) onCommand;
  final VoidCallback onDismiss;
  final VoidCallback onPlot;
  final String activeLabel;
  final bool enabled;
  final bool supportsStructuralNavigation;
  final bool supportsStructuredEditing;
  final String location;
  final bool persistenceEnabled;
  final String preferenceNamespace;
  final String Function(String sourceText)? labelResolver;
  final Widget Function(BuildContext context, Widget dialog)? dialogBuilder;
  const MathKeyboard({
    super.key,
    required this.onCommand,
    required this.onDismiss,
    required this.onPlot,
    required this.activeLabel,
    this.enabled = true,
    this.supportsStructuralNavigation = true,
    this.supportsStructuredEditing = true,
    this.location = '公式',
    this.persistenceEnabled = true,
    this.preferenceNamespace = '',
    this.labelResolver,
    this.dialogBuilder,
  });

  @override
  State<MathKeyboard> createState() => _MathKeyboardState();
}

class _MathKeyboardState extends State<MathKeyboard> {
  String _category = '常用';
  List<String> _categoryOrder = _defaultCategoryOrder;
  late final Future<void> _categoryOrderLoad;
  int _page = 0;
  bool _shifted = false;
  final _categoryScrollController = ScrollController();
  final _keyScrollController = ScrollController();
  double _keyGridDragDistance = 0;
  final _categoryKeys = {
    for (final category in _groups.keys) category: GlobalKey(),
  };

  String get _categoryOrderPreferenceKey => widget.preferenceNamespace.isEmpty
      ? 'math_keyboard_category_order_v1'
      : 'visual_math.${widget.preferenceNamespace}.math_keyboard_category_order_v1';

  String _label(String source) => widget.labelResolver?.call(source) ?? source;

  Widget _dialog(BuildContext context, Widget child) =>
      widget.dialogBuilder?.call(context, child) ?? child;

  @override
  void initState() {
    super.initState();
    _categoryOrderLoad = _loadCategoryOrder();
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _keyScrollController.dispose();
    super.dispose();
  }

  void _selectCategory(String category) {
    setState(() {
      _category = category;
      _page = 0;
    });
    if (_keyScrollController.hasClients) {
      _keyScrollController.jumpTo(0);
    }
    _ensureCategoryVisible(category);
  }

  Future<void> _loadCategoryOrder() async {
    if (!widget.persistenceEnabled) return;
    final preferences = await SharedPreferences.getInstance();
    final storedOrder = preferences.getStringList(_categoryOrderPreferenceKey);
    if (!mounted) return;
    setState(() => _categoryOrder = _mergeCategoryOrder(storedOrder));
    _ensureCategoryVisible(_category);
  }

  List<String> _mergeCategoryOrder(List<String>? storedOrder) {
    final order = <String>[];
    for (final category in storedOrder ?? const <String>[]) {
      if (_groups.containsKey(category) && !order.contains(category)) {
        order.add(category);
      }
    }
    for (final category in _defaultCategoryOrder) {
      if (!order.contains(category)) order.add(category);
    }
    for (final category in _groups.keys) {
      if (!order.contains(category)) order.add(category);
    }
    return order;
  }

  Future<void> _saveCategoryOrder() async {
    if (!widget.persistenceEnabled) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _categoryOrderPreferenceKey,
      _categoryOrder,
    );
  }

  void _ensureCategoryVisible(String category) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chipContext = _categoryKeys[category]?.currentContext;
      final renderObject = chipContext?.findRenderObject();
      if (chipContext != null && renderObject != null) {
        Scrollable.of(chipContext).position.ensureVisible(
          renderObject,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _reorderCategories(
    int oldIndex,
    int newIndex,
    StateSetter setDialogState,
  ) {
    if (oldIndex == newIndex) return;
    final nextOrder = List<String>.of(_categoryOrder);
    final category = nextOrder.removeAt(oldIndex);
    nextOrder.insert(newIndex, category);
    setState(() => _categoryOrder = nextOrder);
    setDialogState(() {});
    _ensureCategoryVisible(_category);
    unawaited(_saveCategoryOrder());
  }

  Future<void> _showCategoryOrderDialog() async {
    await _categoryOrderLoad;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _dialog(
        dialogContext,
        StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Text(_label('选择符号分类')),
              content: SizedBox(
                width: 320,
                height: 420,
                child: ReorderableListView.builder(
                  itemCount: _categoryOrder.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) =>
                      _reorderCategories(oldIndex, newIndex, setDialogState),
                  itemBuilder: (context, index) {
                    final category = _categoryOrder[index];
                    return ListTile(
                      key: ValueKey('category-row-$category'),
                      selected: category == _category,
                      selectedTileColor: cs.secondaryContainer,
                      title: Text(_label(category)),
                      subtitle: Text(
                        _label(_categoryDescriptions[category]!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        _selectCategory(category);
                        Navigator.of(dialogContext).pop();
                      },
                      trailing: ReorderableDragStartListener(
                        key: ValueKey('category-order-handle-$category'),
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final defaults = List<String>.of(_defaultCategoryOrder);
                    setState(() => _categoryOrder = defaults);
                    setDialogState(() {});
                    _ensureCategoryVisible(_category);
                    unawaited(_saveCategoryOrder());
                  },
                  child: Text(_label('恢复默认')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_label('完成')),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _changePage(int pageCount, int direction) {
    if (pageCount < 2) return;
    setState(() => _page = (_page + direction + pageCount) % pageCount);
    if (_keyScrollController.hasClients) {
      _keyScrollController.jumpTo(0);
    }
  }

  void _updateKeyGridDrag(DragUpdateDetails details) {
    _keyGridDragDistance += details.primaryDelta ?? 0;
  }

  void _endKeyGridDrag(int pageCount) {
    final distance = _keyGridDragDistance;
    _keyGridDragDistance = 0;
    if (distance.abs() < 40) return;
    _changePage(pageCount, distance < 0 ? 1 : -1);
  }

  KeyEventResult _handleKeyGridKeyEvent(int pageCount, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _changePage(pageCount, -1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _changePage(pageCount, 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static const _numbers = [
    '7',
    '8',
    '9',
    '4',
    '5',
    '6',
    '1',
    '2',
    '3',
    '0',
    '.',
    '⌫',
  ];

  static const _latinRows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

  static const _greekUpperLatin = {
    'Alpha': 'A',
    'Beta': 'B',
    'Epsilon': 'E',
    'Zeta': 'Z',
    'Eta': 'H',
    'Iota': 'I',
    'Kappa': 'K',
    'Mu': 'M',
    'Nu': 'N',
    'Omicron': 'O',
    'Rho': 'P',
    'Tau': 'T',
    'Chi': 'X',
  };

  static final _greekUpperKeys = [
    for (final name in mathGreekUpperNames)
      _MathKey(
        _greekUpperLatin[name] ?? '\\$name',
        _greekUpperLatin[name] ?? '\\$name',
        description: name,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAlphabetCategory = _category == '字母';
    final keys = _category == '希腊字母' && _shifted
        ? _greekUpperKeys
        : _groups[_category]!;
    final pageCount = isAlphabetCategory ? 1 : (keys.length / 12).ceil();
    final keysPerPage = (keys.length / pageCount).ceil();
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heading = <Widget>[
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Tooltip(
                        message: _label('点击公式定位，长按选择；左右逐项移动，上下切换结构层'),
                        child: Text(
                          widget.enabled
                              ? '${widget.activeLabel} · ${widget.location}'
                              : '${widget.activeLabel} · ${_label('正在准备数学输入…')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    _action(Icons.undo, '撤销', 'undo'),
                    _action(Icons.redo, '重做', 'redo'),
                    PopupMenuButton<String>(
                      tooltip: _label('选择与剪贴板'),
                      enabled: widget.enabled,
                      onSelected: (action) => widget.onCommand(
                        action == 'selectAll' ? 'command' : 'clipboard',
                        action,
                      ),
                      itemBuilder: (_) => [
                        for (final entry in {
                          'selectAll': _label('全选'),
                          'copy': _label('复制 LaTeX'),
                          'cut': _label('剪切'),
                          'paste': _label('粘贴公式'),
                        }.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                    ),
                    IconButton(
                      onPressed: widget.onDismiss,
                      tooltip: _label('收起数学键盘'),
                      icon: const Icon(Icons.keyboard_hide),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _categoryScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            for (final category in _categoryOrder)
                              Padding(
                                key: _categoryKeys[category],
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(_label(category)),
                                  selected: category == _category,
                                  selectedColor: cs.primaryContainer,
                                  labelStyle: TextStyle(
                                    color: category == _category
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                  showCheckmark: false,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  onSelected: (_) => _selectCategory(category),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _label('全部符号分类'),
                      icon: const Icon(Icons.apps, size: 20),
                      onPressed: _showCategoryOrderDialog,
                    ),
                  ],
                ),
              ),
            ];
            final compact =
                constraints.hasBoundedHeight && constraints.maxHeight < 180;
            final input = compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...heading,
                      _keyArea(keys, pageCount, keysPerPage),
                    ],
                  )
                : _keyArea(keys, pageCount, keysPerPage);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact) ...heading,
                if (constraints.hasBoundedHeight)
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _keyScrollController,
                      child: input,
                    ),
                  )
                else
                  input,
                // Navigation remains reachable even when tall keys scroll.
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      _navigate(Icons.chevron_left, '光标左移', 'left'),
                      _navigate(Icons.chevron_right, '光标右移', 'right'),
                      _navigate(Icons.arrow_upward, '光标上移 / 切换上层', 'up'),
                      _navigate(Icons.arrow_downward, '光标下移 / 切换下层', 'down'),
                      _navigate(Icons.north_east, '退出当前结构', 'out'),
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onPlot,
                        child: Text(_label('绘图')),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _keyArea(List<_MathKey> keys, int pageCount, int keysPerPage) {
    final canSwipePages = pageCount > 1 && _category != '字母';
    final canNavigate = widget.enabled && widget.supportsStructuralNavigation;
    final keyGrid = Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: _category == '字母'
          ? _latinKeys()
          : Column(
              children: [
                for (var row = 0; row < 4; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 6; col++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: _key(
                              col < 3
                                  ? (row * 3 + col < keysPerPage &&
                                            _page * keysPerPage +
                                                    row * 3 +
                                                    col <
                                                keys.length
                                        ? keys[_page * keysPerPage +
                                              row * 3 +
                                              col]
                                        : null)
                                  : _MathKey(
                                      _numbers[row * 3 + col - 3],
                                      _numbers[row * 3 + col - 3],
                                      command:
                                          _numbers[row * 3 + col - 3] == '⌫'
                                          ? 'deleteBackward'
                                          : null,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
    final previousButton = TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
      onPressed: canNavigate ? () => widget.onCommand('previous', '') : null,
      child: Text(_label('上一项')),
    );
    final nextButton = TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
      onPressed: canNavigate ? () => widget.onCommand('next', '') : null,
      child: Text(_label('下一项')),
    );
    final isAlphabetCategory = _category == '字母';
    final currentPage = isAlphabetCategory ? 1 : _page + 1;
    final pageIndicator = pageCount > 1 || isAlphabetCategory
        ? IgnorePointer(
            child: Semantics(
              label: _label('第 $currentPage 页，共 $pageCount 页'),
              child: Text('$currentPage/$pageCount'),
            ),
          )
        : null;
    final pageNavigation = canSwipePages
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _label('上一页'),
                onPressed: () => _changePage(pageCount, -1),
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                padding: EdgeInsets.zero,
              ),
              pageIndicator!,
              IconButton(
                tooltip: _label('下一页'),
                onPressed: () => _changePage(pageCount, 1),
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                padding: EdgeInsets.zero,
              ),
            ],
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: _label('符号键盘'),
          value: canSwipePages ? '${_page + 1}/$pageCount' : null,
          increasedValue: canSwipePages
              ? '${(_page + 1) % pageCount + 1}/$pageCount'
              : null,
          decreasedValue: canSwipePages
              ? '${(_page - 1 + pageCount) % pageCount + 1}/$pageCount'
              : null,
          hint: canSwipePages ? _label('使用增减操作切换符号页') : null,
          onIncrease: canSwipePages ? () => _changePage(pageCount, 1) : null,
          onDecrease: canSwipePages ? () => _changePage(pageCount, -1) : null,
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: canSwipePages
                ? (_, event) => _handleKeyGridKeyEvent(pageCount, event)
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: canSwipePages
                  ? (_) => _keyGridDragDistance = 0
                  : null,
              onHorizontalDragUpdate: canSwipePages ? _updateKeyGridDrag : null,
              onHorizontalDragEnd: canSwipePages
                  ? (_) => _endKeyGridDrag(pageCount)
                  : null,
              onHorizontalDragCancel: canSwipePages
                  ? () => _keyGridDragDistance = 0
                  : null,
              child: keyGrid,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_category == '希腊字母')
                SizedBox(
                  width: constraints.maxWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.start,
                      spacing: 4,
                      overflowAlignment: OverflowBarAlignment.start,
                      overflowDirection: VerticalDirection.down,
                      children: [
                        SizedBox(width: 44, child: _shiftKey()),
                        Text(_label('大小写')),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                width: constraints.maxWidth,
                child: OverflowBar(
                  alignment: MainAxisAlignment.center,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.center,
                  overflowDirection: VerticalDirection.down,
                  children: [
                    previousButton,
                    if (pageNavigation != null)
                      pageNavigation
                    else if (pageIndicator != null)
                      pageIndicator,
                    nextButton,
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _latinKeys() => Column(
    children: [
      Row(
        children: [
          for (final number in '1234567890'.split(''))
            _latinCell(_key(_MathKey(number, number))),
        ],
      ),
      for (var row = 0; row < _latinRows.length; row++)
        Row(
          children: [
            if (row == 1) const Spacer(),
            if (row == 2) _latinCell(_shiftKey(), flex: 3),
            for (final letter in _latinRows[row].split(''))
              _latinCell(
                _key(
                  _MathKey(
                    _shifted ? letter.toUpperCase() : letter,
                    _shifted ? letter.toUpperCase() : letter,
                  ),
                ),
                flex: row == 0 ? 1 : 2,
              ),
            if (row == 1) const Spacer(),
            if (row == 2)
              _latinCell(
                _key(const _MathKey('.', '.', description: '小数点')),
                flex: 2,
              ),
            if (row == 2)
              _latinCell(
                _key(const _MathKey('⌫', '', command: 'deleteBackward')),
                flex: 3,
              ),
          ],
        ),
    ],
  );

  Widget _latinCell(Widget child, {int flex = 1}) => Expanded(
    flex: flex,
    child: Padding(padding: const EdgeInsets.all(2), child: child),
  );

  void _toggleShift() => setState(() => _shifted = !_shifted);

  Widget _shiftKey() => Semantics(
    key: const ValueKey('math-keyboard-shift'),
    label: _label('Shift'),
    button: true,
    enabled: widget.enabled,
    toggled: _shifted,
    excludeSemantics: true,
    onTap: widget.enabled ? _toggleShift : null,
    child: Tooltip(
      excludeFromSemantics: true,
      message: _label(_shifted ? 'Shift：大写已开启，切换小写' : 'Shift：小写，切换大写'),
      child: SizedBox(
        height: 44,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: _shifted
                ? Theme.of(context).colorScheme.primary
                : null,
            foregroundColor: _shifted
                ? Theme.of(context).colorScheme.onPrimary
                : null,
            padding: const EdgeInsets.all(2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
            ),
          ),
          onPressed: widget.enabled ? _toggleShift : null,
          child: Icon(_shifted ? Icons.keyboard_capslock : Icons.arrow_upward),
        ),
      ),
    ),
  );

  Widget _navigate(IconData icon, String label, String direction) => IconButton(
    icon: Icon(icon, size: 20),
    tooltip: _label(label),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    onPressed: widget.enabled
        ? () => widget.onCommand('navigate', direction)
        : null,
  );

  Widget _action(IconData icon, String label, String command) => IconButton(
    icon: Icon(icon, size: 20),
    tooltip: _label(label),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    onPressed: widget.enabled
        ? () => widget.onCommand('command', command)
        : null,
  );

  Widget _key(_MathKey? key) => SizedBox(
    height: 44,
    child: key == null
        ? const SizedBox.shrink()
        : Tooltip(
            message: _label(key.description ?? key.label),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    MathUiTokens.cornerRadius,
                  ),
                ),
              ),
              onPressed:
                  !widget.enabled ||
                      (!widget.supportsStructuredEditing &&
                          key.requiresStructuredEditing)
                  ? null
                  : () => widget.onCommand(
                      key.command == null ? 'insert' : 'command',
                      key.command ?? key.value,
                    ),
              child: key.label == '⌫'
                  ? const Icon(Icons.backspace_outlined, size: 20)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Math.tex(
                        key.label,
                        textStyle: const TextStyle(fontSize: 18),
                        onErrorFallback: (_) => Text(
                          _label(key.label),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
            ),
          ),
  );
}

class _MathKey {
  final String label, value;
  final String? command, description;
  const _MathKey(this.label, this.value, {this.command, this.description});

  bool get requiresStructuredEditing =>
      value.contains('#') ||
      const {
        'addRowAfter',
        'addColumnAfter',
        'removeRow',
        'removeColumn',
      }.contains(command);
}

typedef NumericMathInsert = void Function(String text, {int? cursorFromEnd});

/// Numeric-only text input for parameter expressions. The keys expose no
/// variables or named constants; function names are inserted only by the
/// square-root and absolute-value templates.
class MathNumericKeyboard extends StatelessWidget {
  final String activeLabel;
  final String Function(String sourceText)? labelResolver;
  final NumericMathInsert onInsert;
  final VoidCallback onBackspace;
  final ValueChanged<int> onMoveCaret;
  final VoidCallback onDismiss;

  const MathNumericKeyboard({
    super.key,
    required this.activeLabel,
    this.labelResolver,
    required this.onInsert,
    required this.onBackspace,
    required this.onMoveCaret,
    required this.onDismiss,
  });

  static const _rows = <List<_NumericMathKey>>[
    [
      _NumericMathKey('7', '7'),
      _NumericMathKey('8', '8'),
      _NumericMathKey('9', '9'),
      _NumericMathKey('+', '+'),
      _NumericMathKey('−', '-'),
      _NumericMathKey('×', '*'),
    ],
    [
      _NumericMathKey('4', '4'),
      _NumericMathKey('5', '5'),
      _NumericMathKey('6', '6'),
      _NumericMathKey('÷', '/'),
      _NumericMathKey('(', '('),
      _NumericMathKey(')', ')'),
    ],
    [
      _NumericMathKey('1', '1'),
      _NumericMathKey('2', '2'),
      _NumericMathKey('3', '3'),
      _NumericMathKey('√', 'sqrt()', cursorFromEnd: 1, description: '平方根'),
      _NumericMathKey('|□|', 'abs()', cursorFromEnd: 1, description: '绝对值'),
      _NumericMathKey('^', '^()', cursorFromEnd: 1, description: '乘方'),
    ],
    [
      _NumericMathKey('0', '0'),
      _NumericMathKey('.', '.'),
      _NumericMathKey.action('⌫', _NumericMathAction.backspace),
      _NumericMathKey('□/□', '()/()', cursorFromEnd: 4, description: '分数'),
      _NumericMathKey.action('←', _NumericMathAction.moveLeft),
      _NumericMathKey.action('→', _NumericMathAction.moveRight),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String label(String source) => labelResolver?.call(source) ?? source;
    return Material(
      color: colors.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$activeLabel · ${label('数学键盘（仅数值）')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onDismiss,
                        tooltip: label('收起数学键盘'),
                        icon: const Icon(Icons.keyboard_hide),
                      ),
                    ],
                  ),
                ),
                for (final row in _rows)
                  Row(
                    children: [
                      for (final key in row)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: SizedBox(
                              height: 44,
                              child: Tooltip(
                                message: label(key.description ?? key.label),
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.all(2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        MathUiTokens.cornerRadius,
                                      ),
                                    ),
                                  ),
                                  onPressed: () => _press(key),
                                  child:
                                      key.action == _NumericMathAction.backspace
                                      ? const Icon(
                                          Icons.backspace_outlined,
                                          size: 20,
                                        )
                                      : Text(
                                          key.label,
                                          maxLines: 1,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _press(_NumericMathKey key) {
    switch (key.action) {
      case _NumericMathAction.backspace:
        onBackspace();
        return;
      case _NumericMathAction.moveLeft:
        onMoveCaret(-1);
        return;
      case _NumericMathAction.moveRight:
        onMoveCaret(1);
        return;
      case null:
        onInsert(key.value!, cursorFromEnd: key.cursorFromEnd);
        return;
    }
  }
}

enum _NumericMathAction { backspace, moveLeft, moveRight }

class _NumericMathKey {
  final String label;
  final String? value;
  final int? cursorFromEnd;
  final _NumericMathAction? action;
  final String? description;

  const _NumericMathKey(
    this.label,
    this.value, {
    this.cursorFromEnd,
    this.description,
  }) : action = null;

  const _NumericMathKey.action(this.label, this.action)
    : value = null,
      cursorFromEnd = null,
      description = null;
}

const _defaultCategoryOrder = <String>[
  '常用',
  '字母',
  '指数/对数',
  '函数',
  '常量',
  '括号/区间',
  '关系',
  '希腊字母',
  '希腊变体',
  '微积分',
  '集合/逻辑',
  '矩阵',
  '箭头',
  '样式',
];

const _categoryDescriptions = {
  '常用': '四则运算、分数、根式与下标',
  '指数/对数': '指数、自然常数 e 与不同底数的对数',
  '函数': '三角、双曲与其他常用函数',
  '常量': '圆周率、自然常数与常用数值',
  '括号/区间': '成对括号、绝对值与区间',
  '关系': '等式、不等式与常用关系符号',
  '微积分': '求和、积分、极限与导数',
  '集合/逻辑': '数集、集合运算与逻辑符号',
  '矩阵': '矩阵、行列式、分段式与行列编辑',
  '箭头': '方向、映射与带注释的箭头',
  '样式': '重音、上下标注与数学字体',
  '字母': 'QWERTY 全部 26 个拉丁字母，Shift 切换大小写',
  '希腊字母': '全部 24 个希腊字母，Shift 切换大小写',
  '希腊变体': '常用希腊字母变体',
};

const _exponentialDescriptions = {
  'e': '自然常数 e',
  'exp': '指数函数 exp（底数 e）',
  'ln': '自然对数 ln',
  'log10': '常用对数（底数 10）',
  'log2': '二进制对数（底数 2）',
  'logbase': '指定底数的对数：先填底数',
  'power': '幂：选区或左侧完整项作为底数',
  'power2': '2 的幂',
  'power10': '10 的幂',
};

const _inverseFunctionLabels = {
  'arccot': 'acot',
  'arcsec': 'asec',
  'arccsc': 'acsc',
  'arsinh': 'asinh',
  'arcosh': 'acosh',
  'artanh': 'atanh',
};

final Map<String, List<_MathKey>> _groups = {
  '常用': const [
    _MathKey(r'\frac{a}{b}', r'\frac{#0}{#?}', description: '分数：选区放入分子'),
    _MathKey('x', 'x'),
    _MathKey('+', '+', description: '加法'),
    _MathKey(r'x^n', r'#@^{#?}', description: '幂：进入指数'),
    _MathKey('y', 'y'),
    _MathKey('−', '-', description: '减法'),
    _MathKey(r'\sqrt{x}', r'\sqrt{#0}'),
    _MathKey('e', 'e'),
    _MathKey('×', r'\times', description: '乘法'),
    _MathKey(r'\left(x\right)', r'\left(#0\right)'),
    _MathKey('=', '=', description: '等于'),
    _MathKey('÷', r'\div', description: '除法'),
    _MathKey(r'\cdot', r'\cdot', description: '乘法（点号）'),
    _MathKey(r'\pi', r'\pi'),
    _MathKey(r'x^2', r'#@^{2}', description: '平方：选区或左侧完整项'),
    _MathKey(r'\sqrt[n]{x}', r'\sqrt[#?]{#0}'),
    _MathKey(r'x_n', r'#@_{#?}'),
    _MathKey(r'\left|x\right|', r'\left|#0\right|'),
    _MathKey(r'\pm', r'\pm'),
    _MathKey(r'\%', r'\%', description: '百分比：左侧表达式除以 100'),
    _MathKey(r'\operatorname{mod}', r'\bmod', description: '余数 / 取模'),
    _MathKey(r'\infty', r'\infty'),
    _MathKey(', ', ','),
    _MathKey(r'\mp', r'\mp'),
  ],
  '指数/对数': [
    for (final input in mathExponentialInputs)
      _MathKey(
        input.label,
        input.latex,
        description: _exponentialDescriptions[input.name] ?? input.name,
      ),
    // Legacy bare log keeps its natural-log meaning in the numeric evaluator.
    _MathKey(r'\log', r'\log\left(#0\right)', description: '对数 log（默认自然底数 e）'),
  ],
  '函数': [
    for (final input in mathUnaryInputs)
      if (!['ln', 'log', 'exp'].contains(input.name))
        _MathKey(
          input.label,
          input.latex,
          description:
              [
                'sin',
                'cos',
                'tan',
                'cot',
                'sec',
                'csc',
                'asin',
                'acos',
                'atan',
              ].contains(input.name)
              ? '${input.name}（角度用弧度）'
              : input.name,
        ),
    for (final input in mathBinaryInputs)
      if (!['log', 'pow'].contains(input.name))
        _MathKey(input.label, input.latex, description: input.name),
    for (final name in ['min', 'max', 'gcd'])
      _MathKey('\\$name', '\\$name\\left(#0,#?\\right)'),
    for (final name in ['arg', 'Re', 'Im'])
      _MathKey('\\$name', '\\$name\\left(#0\\right)'),
    for (final name in [
      'arccot',
      'arcsec',
      'arccsc',
      'arsinh',
      'arcosh',
      'artanh',
    ])
      _MathKey(
        '\\operatorname{${_inverseFunctionLabels[name]!}}',
        '\\operatorname{$name}\\left(#0\\right)',
        description: '${_inverseFunctionLabels[name]}（公式排版）',
      ),
  ],
  '常量': [
    for (final input in mathConstantInputs)
      _MathKey(input.label, input.latex, description: input.name),
    const _MathKey(r'\infty', r'\infty'),
  ],
  '希腊字母': [
    for (final name in mathGreekLowerNames)
      _MathKey('\\$name', '\\$name', description: name),
  ],
  '希腊变体': [
    for (final name in mathGreekVariantNames)
      _MathKey('\\$name', '\\$name', description: name),
  ],
  '微积分': const [
    _MathKey(r'\sum', r'\sum_{#?}^{#?}#0'),
    _MathKey(r'\prod', r'\prod_{#?}^{#?}#0'),
    _MathKey(r'\int', r'\int_{#?}^{#?}#0\,\mathrm{d}x'),
    _MathKey(r'\iint', r'\iint_{#?}#0'),
    _MathKey(r'\oint', r'\oint_{#?}#0'),
    _MathKey(r'\lim', r'\lim_{x\to#?}#0'),
    _MathKey(
      r'\frac{\mathrm{d}}{\mathrm{d}x}',
      r'\frac{\mathrm{d}}{\mathrm{d}x}\left(#0\right)',
    ),
    _MathKey(r'\frac{\partial}{\partial x}', r'\frac{\partial #0}{\partial x}'),
    _MathKey(r'\partial', r'\partial'),
    _MathKey(r'\nabla', r'\nabla'),
    _MathKey(r'x^{\prime}', r'#@^{\prime}', description: '导数撇号：选区或左侧完整项'),
    _MathKey(r'\limsup', r'\limsup_{x\to#?}#0'),
    _MathKey(r'\liminf', r'\liminf_{x\to#?}#0'),
    _MathKey(r'\iiint', r'\iiint_{#?}#0'),
  ],
  '矩阵': const [
    _MathKey(
      r'\begin{pmatrix}a&b\\c&d\end{pmatrix}',
      r'\begin{pmatrix}#?&#?\\#?&#?\end{pmatrix}',
      description: '圆括号矩阵（2×2）',
    ),
    _MathKey(
      r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
      r'\begin{bmatrix}#?&#?\\#?&#?\end{bmatrix}',
      description: '方括号矩阵（2×2）',
    ),
    _MathKey(
      r'\begin{matrix}a&b\\c&d\end{matrix}',
      r'\begin{matrix}#?&#?\\#?&#?\end{matrix}',
      description: '无括号矩阵（2×2）',
    ),
    _MathKey(
      r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
      r'\begin{vmatrix}#?&#?\\#?&#?\end{vmatrix}',
      description: '行列式（2×2）',
    ),
    _MathKey(
      r'\begin{Vmatrix}a&b\\c&d\end{Vmatrix}',
      r'\begin{Vmatrix}#?&#?\\#?&#?\end{Vmatrix}',
      description: '双竖线矩阵（2×2）',
    ),
    _MathKey(
      r'\begin{cases}a&x>0\\b&x\le0\end{cases}',
      r'\begin{cases}#?&#?\\#?&#?\end{cases}',
      description: '分段式：每行填表达式和条件',
    ),
    _MathKey(r'\binom{n}{k}', r'\binom{#0}{#?}'),
    _MathKey('加行', '', command: 'addRowAfter', description: '在矩阵当前行后加行'),
    _MathKey('加列', '', command: 'addColumnAfter', description: '在矩阵当前列后加列'),
    _MathKey('删行', '', command: 'removeRow', description: '删除矩阵当前行'),
    _MathKey('删列', '', command: 'removeColumn', description: '删除矩阵当前列'),
  ],
  '集合/逻辑': [
    for (final letter in ['N', 'Z', 'Q', 'R', 'C'])
      _MathKey('\\mathbb{$letter}', '\\mathbb{$letter}'),
    for (final symbol in [
      r'\in',
      r'\notin',
      r'\subset',
      r'\subseteq',
      r'\supset',
      r'\supseteq',
      r'\cup',
      r'\cap',
      r'\setminus',
      r'\emptyset',
      r'\forall',
      r'\exists',
      r'\neg',
      r'\land',
      r'\lor',
      r'\mid',
    ])
      _MathKey(symbol, symbol),
    _MathKey(r'\bigcup', r'\bigcup_{#?}^{#?}#0'),
    _MathKey(r'\bigcap', r'\bigcap_{#?}^{#?}#0'),
    _MathKey(r'\coprod', r'\coprod_{#?}^{#?}#0'),
  ],
  '关系': [
    for (final symbol in [
      r'\ne',
      r'\le',
      r'\ge',
      '<',
      '>',
      r'\approx',
      r'\equiv',
      r'\propto',
      r'\sim',
      r'\simeq',
      r'\cong',
      r'\ll',
      r'\gg',
      r'\perp',
      r'\parallel',
      r'\angle',
      r'\circ',
      r'\cdots',
      r'\vdots',
      r'\ddots',
      r'\colon',
    ])
      _MathKey(symbol, symbol),
  ],
  '箭头': [
    for (final symbol in [
      r'\to',
      r'\leftarrow',
      r'\leftrightarrow',
      r'\Rightarrow',
      r'\Leftarrow',
      r'\Leftrightarrow',
      r'\mapsto',
      r'\uparrow',
      r'\downarrow',
      r'\updownarrow',
    ])
      _MathKey(symbol, symbol),
    const _MathKey(
      r'\xrightarrow[b]{a}',
      r'\xrightarrow[#?]{#0}',
      description: '右箭头：选区作为上方标注，再填下方标注',
    ),
    const _MathKey(
      r'\xleftarrow[b]{a}',
      r'\xleftarrow[#?]{#0}',
      description: '左箭头：选区作为上方标注，再填下方标注',
    ),
  ],
  '括号/区间': const [
    _MathKey(r'\left(x\right)', r'\left(#0\right)'),
    _MathKey(r'\left[x\right]', r'\left[#0\right]'),
    _MathKey(r'\left\{x\right\}', r'\left\{#0\right\}'),
    _MathKey(r'\langle x\rangle', r'\left\langle#0\right\rangle'),
    _MathKey(r'\left|x\right|', r'\left|#0\right|'),
    _MathKey(r'\left\|x\right\|', r'\left\|#0\right\|'),
    _MathKey(r'[a,b]', r'\left[#0,#?\right]', description: '闭区间 [a,b]'),
    _MathKey(r'(a,b)', r'\left(#0,#?\right)', description: '开区间 (a,b)'),
    _MathKey(r'[a,b)', r'\left[#0,#?\right)', description: '左闭右开区间 [a,b)'),
    _MathKey(r'(a,b]', r'\left(#0,#?\right]', description: '左开右闭区间 (a,b]'),
    _MathKey(r'\lfloor x\rfloor', r'\left\lfloor#0\right\rfloor'),
    _MathKey(r'\lceil x\rceil', r'\left\lceil#0\right\rceil'),
  ],
  '样式': [
    for (final name in [
      'vec',
      'hat',
      'bar',
      'dot',
      'ddot',
      'overline',
      'underline',
      'overbrace',
      'underbrace',
      'overrightarrow',
      'overleftarrow',
      'widetilde',
      'widehat',
    ])
      _MathKey('\\$name{x}', '\\$name{#0}'),
    const _MathKey(
      r'\overset{a}{x}',
      r'\overset{#?}{#0}',
      description: '上方标注：选区作为主体',
    ),
    const _MathKey(
      r'\underset{a}{x}',
      r'\underset{#?}{#0}',
      description: '下方标注：选区作为主体',
    ),
    for (final name in [
      'mathrm',
      'mathbf',
      'mathit',
      'mathbb',
      'mathcal',
      'mathfrak',
      'mathsf',
      'mathtt',
    ])
      _MathKey('\\$name{A}', '\\$name{#0}'),
  ],
  '字母': [
    for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split(''))
      _MathKey(letter, letter),
  ],
};
