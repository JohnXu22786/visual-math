import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'math_ui_tokens.dart';

/// A formula editor with source and mathematical input modes.
///
/// Native platforms with an embedded WebView use the bundled MathLive editor.
/// Web and Linux render a formula preview with source editing instead.
class MathFormulaField extends StatefulWidget {
  final TextEditingController controller;
  final bool mathematical;
  final bool showWebView;
  final String label;
  final bool allowModeSwitch;
  final VoidCallback? onRevert;
  final VoidCallback? onReadyChanged;
  final VoidCallback? onCaretChanged;
  final Color? fillColor;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onActivate;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  const MathFormulaField({
    super.key,
    required this.controller,
    required this.mathematical,
    required this.onModeChanged,
    required this.onActivate,
    required this.onChanged,
    required this.onSubmitted,
    required this.label,
    this.showWebView = true,
    this.allowModeSwitch = true,
    this.onRevert,
    this.onReadyChanged,
    this.onCaretChanged,
    this.fillColor,
  });

  /// Whether this platform can run the embedded MathLive WebView.
  static bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.linux &&
      defaultTargetPlatform != TargetPlatform.fuchsia;

  @override
  State<MathFormulaField> createState() => MathFormulaFieldState();
}

class MathFormulaFieldState extends State<MathFormulaField>
    with AutomaticKeepAliveClientMixin {
  // The math container adds a one-pixel border on both sides; keep the full
  // row at the same 48dp height as the source TextField.
  static const double _formulaInputHeight = 46;
  static const double _formulaRowHeight = 48;

  @override
  bool get wantKeepAlive => true;
  InAppWebViewController? _web;
  final FocusNode _sourceFocus = FocusNode();
  Future<void> _pending = Future.value();
  bool _ready = false;
  bool _receiving = false;
  bool _applyingFallbackEdit = false;
  bool _applyingFallbackNavigation = false;
  bool _hasUnsupportedSyntax = false;
  int _revision = 0;
  int _sequence = -1;
  String _lastSource = '';
  late TextSelection _lastSelection;
  int? _preferredVerticalColumn;
  String? _failure;
  ColorScheme? _colorScheme;
  String _location = '公式';
  final List<TextEditingValue> _fallbackUndo = [];
  final List<TextEditingValue> _fallbackRedo = [];
  String get location => _location;
  int get revision => _revision;
  bool get _usesFallback => !widget.showWebView || !MathFormulaField.supported;
  bool get ready => (_ready && _failure == null) || _usesFallback;
  bool get supportsStructuralNavigation => !_usesFallback;
  bool get supportsStructuredEditing => !_usesFallback;

  @override
  void initState() {
    super.initState();
    _lastSource = widget.controller.text;
    _lastSelection = widget.controller.selection;
    widget.controller.addListener(_sourceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    if (colors != _colorScheme) {
      _colorScheme = colors;
      unawaited(_syncTheme());
    }
  }

  Future<void> _syncTheme() {
    if (!_ready) return Future.value();
    final colors = _colorScheme!;
    String css(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    return _enqueue(() async {
      await _web!.evaluateJavascript(
        source:
            'window.stroomMath.theme(${jsonEncode(css(colors.onSurface))},'
            '${jsonEncode(css(colors.primary))})',
      );
    });
  }

  @override
  void didUpdateWidget(MathFormulaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sourceChanged);
      widget.controller.addListener(_sourceChanged);
      _fallbackUndo.clear();
      _fallbackRedo.clear();
      _lastSource = widget.controller.text;
      _lastSelection = widget.controller.selection;
      _preferredVerticalColumn = null;
      _revision++;
      unawaited(_syncSource());
    }
  }

  void _sourceChanged() {
    final controller = widget.controller;
    final textChanged = controller.text != _lastSource;
    final selectionChanged = controller.selection != _lastSelection;
    if (_receiving || (!textChanged && !selectionChanged)) return;
    _lastSelection = controller.selection;
    if (textChanged) {
      _lastSource = controller.text;
      _revision++;
      _sequence = -1;
      _preferredVerticalColumn = null;
      if (!_applyingFallbackEdit) {
        _fallbackUndo.clear();
        _fallbackRedo.clear();
      }
      unawaited(_syncSource());
    }
    if (selectionChanged && !_applyingFallbackNavigation) {
      _preferredVerticalColumn = null;
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      if (!mounted) return;
      try {
        await action();
      } catch (_) {
        if (mounted) setState(() => _failure = '公式编辑器加载失败，可切换到源码继续编辑。');
        widget.onReadyChanged?.call();
      }
    });
    return _pending;
  }

  Future<void> _syncSource() {
    final source = widget.controller.text;
    final version = _revision;
    return _enqueue(() async {
      if (!_ready || version != _revision) return;
      final result = await _web!.evaluateJavascript(
        source: 'window.stroomMath.setSource(${jsonEncode(source)}, $version)',
      );
      _acceptResult(result);
    });
  }

  @visibleForTesting
  void acceptSnapshot(Map<String, dynamic> snapshot) {
    if (!mounted || snapshot['revision'] != _revision) return;
    final sequence = snapshot['sequence'];
    if (sequence is int) {
      if (sequence < _sequence) return;
      _sequence = sequence;
    }
    final errors = snapshot['errors'];
    if (errors is List) {
      final hasErrors = errors.isNotEmpty;
      if (hasErrors != _hasUnsupportedSyntax) {
        setState(() => _hasUnsupportedSyntax = hasErrors);
      }
    }
    if (snapshot['location'] is String && snapshot['location'] != _location) {
      _location = snapshot['location'];
      widget.onCaretChanged?.call();
    }
    final latex = snapshot['latex'];
    if (snapshot['edited'] == true && latex is String && latex != _lastSource) {
      _receiving = true;
      _lastSource = latex;
      widget.controller.value = TextEditingValue(
        text: latex,
        selection: TextSelection.collapsed(offset: latex.length),
      );
      _receiving = false;
      widget.onChanged();
    }
  }

  void _acceptResult(dynamic value) {
    if (value is String) value = jsonDecode(value);
    if (value is Map) acceptSnapshot(Map<String, dynamic>.from(value));
  }

  /// Queue commands and consume their returned snapshot before page actions.
  Future<void> command(String kind, String value) {
    if (_usesFallback) {
      _fallbackCommand(kind, value);
      return Future.value();
    }
    return _enqueue(() async {
      if (!_ready || _failure != null) return;
      final result = await _web!.evaluateJavascript(
        source:
            'window.stroomMath.command(${jsonEncode(kind)}, ${jsonEncode(value)})',
      );
      _acceptResult(result);
    });
  }

  void _fallbackCommand(String kind, String value) {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length).toInt()
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length).toInt()
        : text.length;
    final characterBoundary = CharacterBoundary(text);

    if (kind == 'navigate') {
      final caret = selection.isValid ? selection.extentOffset : text.length;
      final isVertical = value == 'up' || value == 'down';
      if (isVertical) {
        _preferredVerticalColumn ??= _graphemeColumn(
          text,
          _lineStart(text, caret),
          caret,
        );
      } else {
        _preferredVerticalColumn = null;
      }
      final offset = switch (value) {
        'left' =>
          start == end
              ? characterBoundary.getLeadingTextBoundaryAt(start - 1) ?? 0
              : start,
        'right' =>
          start == end
              ? characterBoundary.getTrailingTextBoundaryAt(end) ?? text.length
              : end,
        'up' => _verticalOffset(
          text,
          caret,
          _preferredVerticalColumn!,
          down: false,
        ),
        'down' => _verticalOffset(
          text,
          caret,
          _preferredVerticalColumn!,
          down: true,
        ),
        'out' => text.length,
        _ => null,
      };
      if (offset != null) {
        _applyingFallbackNavigation = isVertical;
        try {
          controller.selection = TextSelection.collapsed(
            offset: offset.clamp(0, text.length).toInt(),
          );
        } finally {
          _applyingFallbackNavigation = false;
        }
      }
      return;
    }

    if (kind == 'insert') {
      _replaceFallbackText(text, start, end, value);
      return;
    }
    if (kind != 'command') return;

    switch (value) {
      case 'deleteBackward':
        final replaceStart = start == end && start > 0
            ? characterBoundary.getLeadingTextBoundaryAt(start - 1) ?? start
            : start;
        _replaceFallbackText(text, replaceStart, end, '');
      case 'deleteForward':
        final replaceEnd = start == end && end < text.length
            ? characterBoundary.getTrailingTextBoundaryAt(end) ?? end
            : end;
        _replaceFallbackText(text, start, replaceEnd, '');
      case 'selectAll':
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      case 'undo':
        _restoreFallbackValue(_fallbackUndo, _fallbackRedo);
      case 'redo':
        _restoreFallbackValue(_fallbackRedo, _fallbackUndo);
    }
  }

  int _lineStart(String text, int offset) {
    final newline = offset == 0 ? -1 : text.lastIndexOf('\n', offset - 1);
    return newline < 0 ? 0 : newline + 1;
  }

  int _verticalOffset(
    String text,
    int offset,
    int column, {
    required bool down,
  }) {
    final currentLineStart = _lineStart(text, offset);
    if (down) {
      final currentLineEnd = text.indexOf('\n', currentLineStart);
      if (currentLineEnd < 0) return offset;
      final nextLineStart = currentLineEnd + 1;
      final nextLineEnd = text.indexOf('\n', nextLineStart);
      final maxOffset = nextLineEnd < 0 ? text.length : nextLineEnd;
      return _offsetForColumn(text, nextLineStart, maxOffset, column);
    }

    if (currentLineStart == 0) return offset;
    final previousLineEnd = currentLineStart - 1;
    final previousLineStart = _lineStart(text, previousLineEnd);
    return _offsetForColumn(text, previousLineStart, previousLineEnd, column);
  }

  int _graphemeColumn(String text, int lineStart, int offset) {
    final boundary = CharacterBoundary(text);
    var position = lineStart;
    var column = 0;
    while (position < offset) {
      final next = boundary.getTrailingTextBoundaryAt(position);
      if (next == null || next <= position || next > offset) break;
      position = next;
      column++;
    }
    return column;
  }

  int _offsetForColumn(String text, int lineStart, int lineEnd, int column) {
    final boundary = CharacterBoundary(text);
    var position = lineStart;
    for (var i = 0; i < column && position < lineEnd; i++) {
      final next = boundary.getTrailingTextBoundaryAt(position);
      if (next == null || next <= position || next > lineEnd) break;
      position = next;
    }
    return position;
  }

  void _replaceFallbackText(
    String text,
    int start,
    int end,
    String replacement,
  ) {
    final updated = text.replaceRange(start, end, replacement);
    if (updated == text) {
      widget.controller.selection = TextSelection.collapsed(
        offset: start + replacement.length,
      );
      return;
    }
    _fallbackUndo.add(widget.controller.value);
    _fallbackRedo.clear();
    _applyFallbackValue(
      TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      ),
    );
  }

  void _restoreFallbackValue(
    List<TextEditingValue> source,
    List<TextEditingValue> destination,
  ) {
    if (source.isEmpty) return;
    destination.add(widget.controller.value);
    _applyFallbackValue(source.removeLast());
  }

  void _applyFallbackValue(TextEditingValue value) {
    _applyingFallbackEdit = true;
    try {
      widget.controller.value = value;
    } finally {
      _applyingFallbackEdit = false;
    }
    widget.onChanged();
  }

  Future<void> clipboard(String action) async {
    if (_usesFallback) {
      final controller = widget.controller;
      final value = controller.value;
      final text = value.text;
      final selection = value.selection;
      final start = selection.isValid
          ? selection.start.clamp(0, text.length).toInt()
          : 0;
      final end = selection.isValid
          ? selection.end.clamp(0, text.length).toInt()
          : text.length;
      if (action == 'paste') {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (mounted &&
            data?.text != null &&
            identical(widget.controller, controller) &&
            controller.value == value) {
          _fallbackCommand('insert', data!.text!);
        }
      } else if (action == 'copy' && selection.isValid && start != end) {
        await Clipboard.setData(
          ClipboardData(text: text.substring(start, end)),
        );
      } else if (action == 'cut' && selection.isValid && start != end) {
        final selectedValue = controller.value;
        await Clipboard.setData(
          ClipboardData(text: text.substring(start, end)),
        );
        if (mounted &&
            identical(widget.controller, controller) &&
            controller.value == selectedValue) {
          _replaceFallbackText(text, start, end, '');
        }
      }
      return;
    }
    if (action == 'paste') {
      dynamic capturedValue;
      await _enqueue(() async {
        if (!_ready || _failure != null) return;
        capturedValue = await _web!.evaluateJavascript(
          source: 'window.stroomMath.capturePaste()',
        );
      });
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || data?.text == null || capturedValue is! String) return;
      final state = Map<String, dynamic>.from(
        jsonDecode(capturedValue) as Map,
      );
      final revision = state['revision'];
      final sequence = state['sequence'];
      final latex = state['latex'];
      final selection = state['selection'];
      if (revision is! int ||
          sequence is! int ||
          latex is! String ||
          selection is! String) {
        return;
      }
      await _enqueue(() async {
        if (!_ready || _failure != null) return;
        _acceptResult(
          await _web!.evaluateJavascript(
            source:
                'window.stroomMath.pasteIfUnchanged('
                '$revision, $sequence, ${jsonEncode(latex)}, '
                '${jsonEncode(selection)}, ${jsonEncode(data!.text!)})',
          ),
        );
      });
      return;
    }
    await _enqueue(() async {
      if (!_ready) return;
      final value = await _web!.evaluateJavascript(
        source: 'window.stroomMath.cutSelection()',
      );
      if (value is String) {
        final selection = Map<String, dynamic>.from(jsonDecode(value) as Map);
        final latex = selection['latex'];
        final capturedSelection = selection['selection'];
        if (latex is String && latex.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: latex));
          if (action == 'cut' && mounted && capturedSelection is String) {
            _acceptResult(
              await _web!.evaluateJavascript(
                source:
                    'window.stroomMath.deleteSelection('
                    '${jsonEncode(capturedSelection)}, ${jsonEncode(latex)})',
              ),
            );
          }
        }
      }
    });
  }

  Future<void> flush() => _enqueue(() async {
    if (!_ready) return;
    _acceptResult(
      await _web!.evaluateJavascript(source: 'window.stroomMath.snapshot()'),
    );
  });

  Future<void> activate() async {
    super.activate();
    _sourceFocus.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    widget.onActivate();
    await _enqueue(() async {
      if (_ready)
        await _web!.evaluateJavascript(source: 'window.stroomMath.activate()');
    });
  }

  Future<void> dismiss() => _enqueue(() async {
    if (_ready)
      await _web!.evaluateJavascript(source: 'window.stroomMath.blur()');
  });

  Future<void> _toggle() async {
    await flush();
    if (!mounted) return;
    final next = !widget.mathematical;
    widget.onModeChanged(next);
    if (next) {
      await activate();
    } else {
      await dismiss();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sourceFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sourceChanged);
    _sourceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final mathematicalMode = widget.mathematical;
    final usesFallback = _usesFallback;
    final toggle = !widget.allowModeSwitch
        ? const SizedBox.shrink()
        : IconButton(
            icon: Icon(
              mathematicalMode ? Icons.keyboard : Icons.calculate_outlined,
              size: 20,
            ),
            tooltip: usesFallback
                ? mathematicalMode
                      ? '切换到 LaTeX 源码输入'
                      : '切换到数学键盘（内置公式预览）'
                : mathematicalMode
                ? '切换到系统键盘 / LaTeX 源码'
                : '切换到数学键盘',
            onPressed: _toggle,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Offstage preserves structured selection and undo history in MathLive.
        Offstage(
          offstage: !mathematicalMode,
          child: Container(
            height: _formulaRowHeight,
            decoration: BoxDecoration(
              color: widget.fillColor ?? cs.surfaceContainerLow,
              border: Border.all(color: cs.outline),
              borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _formulaInputHeight,
                    child: !widget.showWebView || !MathFormulaField.supported
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: activate,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Math.tex(
                                  widget.controller.text.isEmpty
                                      ? r'\square'
                                      : widget.controller.text,
                                  textStyle: TextStyle(
                                    fontSize: 18,
                                    color: cs.onSurface,
                                  ),
                                  onErrorFallback: (_) => Text(widget.label),
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              InAppWebView(
                                initialFile: 'packages/visual_math/assets/vendor/mathlive/editor.html',
                                initialSettings: InAppWebViewSettings(
                                  javaScriptEnabled: true,
                                  transparentBackground: true,
                                  disableContextMenu: false,
                                  supportZoom: false,
                                ),
                                onWebViewCreated: (controller) {
                                  _web = controller;
                                  controller.addJavaScriptHandler(
                                    handlerName: 'StroomMathEditor',
                                    callback: (args) {
                                      if (!mounted ||
                                          args.isEmpty ||
                                          args[0] is! Map)
                                        return null;
                                      final message = Map<String, dynamic>.from(
                                        args[0] as Map,
                                      );
                                      acceptSnapshot(message);
                                      if (message['revision'] == _revision &&
                                          (message['type'] == 'focus' ||
                                              message['type'] == 'tap') &&
                                          widget.mathematical) {
                                        widget.onActivate();
                                      }
                                      if (message['type'] == 'submit')
                                        widget.onSubmitted();
                                      return null;
                                    },
                                  );
                                },
                                onLoadStop: (controller, _) async {
                                  if (!mounted) return;
                                  _ready = true;
                                  await _syncSource();
                                  if (!mounted) return;
                                  await _syncTheme();
                                  if (mounted) {
                                    setState(() {});
                                    widget.onReadyChanged?.call();
                                  }
                                },
                                onReceivedError: (_, request, error) {
                                  if (request.isForMainFrame == true &&
                                      mounted) {
                                    setState(
                                      () => _failure = '公式编辑器加载失败，可切换到源码继续编辑。',
                                    );
                                    widget.onReadyChanged?.call();
                                  }
                                },
                              ),
                              if (!_ready || _failure != null)
                                Center(
                                  child: _failure == null
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Text(
                                            _failure!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.error,
                                            ),
                                          ),
                                        ),
                                ),
                              if (_hasUnsupportedSyntax)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      alignment: Alignment.centerLeft,
                                      color: cs.surfaceContainerLow,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        '暂不支持此语法，请切换源码',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                toggle,
              ],
            ),
          ),
        ),
        Offstage(
          offstage: mathematicalMode,
          child: TextField(
            controller: widget.controller,
            focusNode: _sourceFocus,
            decoration: InputDecoration(
              hintText: widget.label,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              ),
              filled: true,
              fillColor: widget.fillColor,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onRevert != null)
                    IconButton(
                      tooltip: '撤销修改',
                      icon: const Icon(Icons.undo, size: 16),
                      onPressed: widget.onRevert,
                    ),
                  toggle,
                ],
              ),
            ),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: cs.onSurface,
            ),
            onChanged: (_) => widget.onChanged(),
            onSubmitted: (_) => widget.onSubmitted(),
          ),
        ),
      ],
    );
  }
}
