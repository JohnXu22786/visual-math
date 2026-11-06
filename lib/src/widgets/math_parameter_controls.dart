import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/math_expression.dart';
import '../models/math_parameter.dart';
import 'math_keyboard.dart';

/// Compact controls intended to share the formula list's scrolling viewport.
class MathParameterControls extends StatelessWidget {
  final Map<String, MathParameter> parameters;
  final void Function(String name, MathParameter parameter) onChanged;
  final String Function(String sourceText)? labelResolver;
  final Widget Function(BuildContext context, Widget dialog)? dialogBuilder;
  final Widget Function(BuildContext context, String message)? errorBuilder;

  const MathParameterControls({
    super.key,
    required this.parameters,
    required this.onChanged,
    this.labelResolver,
    this.dialogBuilder,
    this.errorBuilder,
  });

  Future<void> _configure(
      BuildContext context, String name, MathParameter parameter) async {
    final result = await showDialog<MathParameter>(
      context: context,
      builder: (dialogContext) {
        final dialog = _ParameterDialog(
          name: name,
          parameter: parameter,
          labelResolver: labelResolver,
          errorBuilder: errorBuilder,
        );
        return dialogBuilder?.call(dialogContext, dialog) ?? dialog;
      },
    );
    if (result != null && context.mounted) onChanged(name, result);
  }

  @override
  Widget build(BuildContext context) {
    if (parameters.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in parameters.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: () =>
                          _configure(context, entry.key, entry.value),
                      child: Text(
                        '${entry.key} = ${entry.value.formatValue()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: labelResolver?.call('设置参数 ${entry.key}') ??
                        '设置参数 ${entry.key}',
                    icon: const Icon(Icons.tune, size: 20),
                    onPressed: () =>
                        _configure(context, entry.key, entry.value),
                  ),
                ]),
                _ParameterSlider(
                  key: ValueKey(entry.key),
                  name: entry.key,
                  parameter: entry.value,
                  labelResolver: labelResolver,
                  onChanged: (parameter) => onChanged(entry.key, parameter),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ParameterSlider extends StatefulWidget {
  final String name;
  final MathParameter parameter;
  final ValueChanged<MathParameter> onChanged;
  final String Function(String sourceText)? labelResolver;

  const _ParameterSlider({
    super.key,
    required this.name,
    required this.parameter,
    required this.onChanged,
    this.labelResolver,
  });

  @override
  State<_ParameterSlider> createState() => _ParameterSliderState();
}

class _ParameterSliderState extends State<_ParameterSlider> {
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKeyEvent)
    ..addListener(_focusChanged);

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _changeValue(double value) {
    if (value != widget.parameter.value) {
      widget.onChanged(widget.parameter.withValue(value));
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final bool increase;
    if (key == LogicalKeyboardKey.arrowUp) {
      increase = true;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      increase = false;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      increase = Directionality.of(context) == TextDirection.ltr;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      increase = Directionality.of(context) == TextDirection.rtl;
    } else {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _changeValue(widget.parameter.adjacentValue(increase));
    }
    return KeyEventResult.handled;
  }

  String _announce(double value) =>
      '${widget.name} = ${widget.parameter.formatValue(value)}';

  @override
  Widget build(BuildContext context) {
    final parameter = widget.parameter;
    final increased = parameter.adjacentValue(true);
    final decreased = parameter.adjacentValue(false);
    return Semantics(
      container: true,
      excludeSemantics: true,
      slider: true,
      enabled: true,
      focusable: true,
      focused: _focusNode.hasFocus,
      label:
          widget.labelResolver?.call('参数 ${widget.name}') ??
          '参数 ${widget.name}',
      value: _announce(parameter.value),
      increasedValue: increased > parameter.value ? _announce(increased) : null,
      decreasedValue: decreased < parameter.value ? _announce(decreased) : null,
      onIncrease:
          increased > parameter.value ? () => _changeValue(increased) : null,
      onDecrease:
          decreased < parameter.value ? () => _changeValue(decreased) : null,
      onFocus: _focusNode.requestFocus,
      child: Slider(
        focusNode: _focusNode,
        value: parameter.value,
        min: parameter.min,
        max: parameter.max,
        label: parameter.formatValue(),
        onChanged: (value) => _changeValue(parameter.snap(value)),
      ),
    );
  }
}

class _ParameterDialog extends StatefulWidget {
  final String name;
  final MathParameter parameter;
  final String Function(String sourceText)? labelResolver;
  final Widget Function(BuildContext context, String message)? errorBuilder;

  const _ParameterDialog({
    required this.name,
    required this.parameter,
    this.labelResolver,
    this.errorBuilder,
  });

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  String _label(String source) => widget.labelResolver?.call(source) ?? source;

  late final Map<String, TextEditingController> _controllers = {
    'value': TextEditingController(text: widget.parameter.formatValue()),
    'min': TextEditingController(text: widget.parameter.min.toString()),
    'max': TextEditingController(text: widget.parameter.max.toString()),
    'step': TextEditingController(text: widget.parameter.step.toString()),
  };
  static const _labels = {
    'value': '数值',
    'min': '最小值',
    'max': '最大值',
    'step': '步长',
  };
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final errors = <String, String>{};
    final numbers = <String, double>{};
    for (final entry in _controllers.entries) {
      final number = _parseNumericExpression(entry.value.text);
      if (number == null || !number.isFinite) {
        errors[entry.key] = '请输入有限数值';
      } else {
        numbers[entry.key] = number;
      }
    }
    final min = numbers['min'];
    final max = numbers['max'];
    final step = numbers['step'];
    if (min != null && max != null) {
      if (min >= max) {
        errors['max'] = '最大值必须大于最小值';
      } else if (!(max - min).isFinite) {
        errors['max'] = '范围过大，请缩小边界';
      }
    }
    if (step != null) {
      if (step <= 0) {
        errors['step'] = '步长必须大于 0';
      } else if (min != null && max != null && min < max && step > max - min) {
        errors['step'] = '步长不能大于参数范围';
      }
    }
    MathParameter? result;
    if (errors.isEmpty) {
      try {
        result = widget.parameter.reconfigure(
          value: numbers['value']!,
          min: min!,
          max: max!,
          step: step!,
        );
      } on ArgumentError {
        errors['step'] = '步长过小，当前范围无法精确计算';
      }
    }
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() => _errors = errors);
    }
  }

  double? _parseNumericExpression(String source) {
    final direct = double.tryParse(source.trim());
    if (direct != null) return direct.isFinite ? direct : null;

    final numericSyntax = source.replaceAll(RegExp(r'\s+'), '');
    final token = RegExp(
        r'(?:sqrt|abs|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[+\-*/%^()])');
    var offset = 0;
    for (final match in token.allMatches(numericSyntax)) {
      if (match.start != offset) return null;
      offset = match.end;
    }
    if (offset != numericSyntax.length) return null;

    final expression = MathExpression.fromInput(source);
    if (!expression.isValid ||
        expression.type != MathExpressionType.explicit ||
        expression.parameters.isNotEmpty) {
      return null;
    }

    try {
      final value = expression.evaluator(0);
      return value.isFinite ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMathKeyboard(String key) async {
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => MathNumericKeyboard(
        activeLabel: _label(_labels[key]!),
        labelResolver: widget.labelResolver,
        onDismiss: () => Navigator.of(sheetContext).pop(),
        onInsert: (text, {cursorFromEnd}) =>
            _insertText(key, text, cursorFromEnd: cursorFromEnd),
        onBackspace: () => _deleteText(key),
        onMoveCaret: (direction) => _moveCaret(key, direction),
      ),
    );
  }

  TextSelection _selection(TextEditingValue value) {
    if (!value.selection.isValid) {
      return TextSelection.collapsed(offset: value.text.length);
    }
    return TextSelection(
      baseOffset:
          value.selection.baseOffset.clamp(0, value.text.length).toInt(),
      extentOffset:
          value.selection.extentOffset.clamp(0, value.text.length).toInt(),
    );
  }

  void _insertText(String key, String text, {int? cursorFromEnd}) {
    final controller = _controllers[key]!;
    final value = controller.value;
    final selection = _selection(value);
    final nextText = value.text.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    final caret = (selection.start + text.length - (cursorFromEnd ?? 0))
        .clamp(0, nextText.length)
        .toInt();
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() => _errors.remove(key));
  }

  void _deleteText(String key) {
    final controller = _controllers[key]!;
    final value = controller.value;
    final selection = _selection(value);
    if (selection.isCollapsed && selection.start == 0) return;
    final start = selection.isCollapsed ? selection.start - 1 : selection.start;
    final nextText = value.text.replaceRange(start, selection.end, '');
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start),
    );
    setState(() => _errors.remove(key));
  }

  void _moveCaret(String key, int direction) {
    final controller = _controllers[key]!;
    final value = controller.value;
    final selection = _selection(value);
    final offset = selection.isCollapsed
        ? selection.extentOffset + direction
        : direction < 0
            ? selection.start
            : selection.end;
    controller.selection = TextSelection.collapsed(
      offset: offset.clamp(0, value.text.length).toInt(),
    );
  }

  Widget _field(String key, String label, {bool last = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _controllers[key],
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: last ? (_) => _apply() : null,
          decoration: InputDecoration(
            labelText: _label(label),
            error: _errors[key] == null
                ? null
                : widget.errorBuilder?.call(context, _label(_errors[key]!)) ??
                    Text(
                      _label(_errors[key]!),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
            errorMaxLines: 2,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _label('使用数学键盘'),
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => _openMathKeyboard(key),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Text('${_label('设置参数')} ${widget.name}'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('value', '数值'),
              _field('min', '最小值'),
              _field('max', '最大值'),
              _field('step', '步长', last: true),
              Text(
                _label(
                  '滑块从最小值按步长递增；最大值不在步长刻度上时，最大值仍可作为最后一个较短步长到达。数值可直接输入。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_label('取消')),
          ),
          FilledButton(onPressed: _apply, child: Text(_label('应用'))),
        ],
      );
}
