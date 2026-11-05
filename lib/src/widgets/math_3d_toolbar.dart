import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/math_3d_tool.dart';

/// The 3D toolbox keeps categories in a horizontal strip and scrolls long tool
/// rows horizontally on touch, trackpad, and mouse wheel input.
class Math3DToolbar extends StatefulWidget {
  final ConstructionTool activeTool;
  final String? instruction;
  final ValueChanged<ConstructionTool> onToolSelected;
  final int polygonSides;
  final ValueChanged<int>? onPolygonSidesChanged;

  const Math3DToolbar({
    super.key,
    required this.activeTool,
    this.instruction,
    required this.onToolSelected,
    this.polygonSides = 6,
    this.onPolygonSidesChanged,
  });

  @override
  State<Math3DToolbar> createState() => _Math3DToolbarState();
}

class _Math3DToolbarState extends State<Math3DToolbar> {
  late ToolGroup _group = ToolInfo.all[widget.activeTool]!.group;
  String? _commandFeedback;
  Timer? _commandFeedbackTimer;
  final Map<ToolGroup, GlobalKey> _groupKeys = {
    for (final group in ToolGroup.values) group: GlobalKey(),
  };
  final GlobalKey _activeToolKey = GlobalKey();
  final ScrollController _groupScrollController = ScrollController();
  final ScrollController _toolScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollGroupIntoView(_group);
  }

  @override
  void didUpdateWidget(Math3DToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTool != widget.activeTool) {
      _commandFeedbackTimer?.cancel();
      _commandFeedbackTimer = null;
      _commandFeedback = null;
      if (!_group.tools.contains(widget.activeTool)) {
        final newGroup = ToolInfo.all[widget.activeTool]!.group;
        _group = newGroup;
        _scrollGroupIntoView(newGroup);
      }
      _scrollActiveToolIntoView();
    }
  }

  void _scrollGroupIntoView(ToolGroup group) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_groupScrollController.hasClients) return;
      final chipContext = _groupKeys[group]?.currentContext;
      if (chipContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          chipContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _scrollActiveToolIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _activeToolKey.currentContext;
      if (!mounted || context == null) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _commandFeedbackTimer?.cancel();
    _groupScrollController.dispose();
    _toolScrollController.dispose();
    super.dispose();
  }

  void _onGroupSelected(ToolGroup group) {
    if (group == _group) return;
    setState(() => _group = group);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _toolScrollController.hasClients) {
        _toolScrollController.jumpTo(0);
        if (group.tools.contains(widget.activeTool)) {
          _scrollActiveToolIntoView();
        }
      }
    });
  }

  void _onToolSelected(ConstructionTool tool) {
    final info = ToolInfo.all[tool]!;
    if (info.behavior == ToolBehavior.command) {
      _commandFeedbackTimer?.cancel();
      setState(() => _commandFeedback = info.tooltip);
      _commandFeedbackTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _clearCommandFeedback();
      });
    } else {
      _clearCommandFeedback();
    }
    widget.onToolSelected(tool);
  }

  void _clearCommandFeedback() {
    _commandFeedbackTimer?.cancel();
    _commandFeedbackTimer = null;
    if (_commandFeedback == null || !mounted) return;
    setState(() => _commandFeedback = null);
  }

  void _scrollHorizontally(
    ScrollController controller,
    PointerSignalEvent event,
  ) {
    if (event is! PointerScrollEvent || !controller.hasClients) return;
    final position = controller.position;
    // The horizontal Scrollable handles trackpad dx natively. Convert a
    // conventional vertical mouse-wheel event to horizontal movement here.
    if (event.scrollDelta.dx != 0) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0 || position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }
    controller.jumpTo(
      (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  Widget _horizontalStrip({
    required ScrollController controller,
    required EdgeInsets padding,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) => _scrollHorizontally(controller, event),
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = ToolInfo.all[widget.activeTool]!;
    final instruction = widget.instruction?.isNotEmpty == true
        ? widget.instruction!
        : active.tooltip;
    final tools = _group.tools;

    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _horizontalStrip(
            controller: _groupScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final group in ToolGroup.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: _groupKeys[group],
                      label: Text(group.label),
                      selected: _group == group,
                      onSelected: (_) => _onGroupSelected(group),
                    ),
                  ),
              ],
            ),
          ),
          _horizontalStrip(
            controller: _toolScrollController,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                for (final tool in tools)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ToolButton(
                      key: tool == widget.activeTool ? _activeToolKey : null,
                      info: ToolInfo.all[tool]!,
                      selected: tool == widget.activeTool,
                      colorScheme: cs,
                      onPressed: () => _onToolSelected(tool),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.activeTool == ConstructionTool.regularPolygon)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('边数：'),
                DropdownButton<int>(
                  value: widget.polygonSides,
                  items: [
                    for (var n = 3; n <= 12; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: widget.onPolygonSidesChanged == null
                      ? null
                      : (value) {
                          if (value != null) {
                            widget.onPolygonSidesChanged!(value);
                          }
                        },
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${active.name} · $instruction',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (_commandFeedback case final feedback?)
                        Text(
                          '命令：$feedback',
                          style: TextStyle(fontSize: 11, color: cs.primary),
                        ),
                    ],
                  ),
                ),
                if (widget.activeTool != ConstructionTool.move)
                  IconButton(
                    tooltip: '结束工具，返回移动',
                    onPressed: () => _onToolSelected(ConstructionTool.move),
                    icon: const Icon(Icons.close, size: 20),
                  )
                else
                  const SizedBox(width: 12, height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final ToolInfo info;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  const _ToolButton({
    super.key,
    required this.info,
    required this.selected,
    required this.colorScheme,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: info.tooltip,
      child: Semantics(
        selected: selected,
        button: true,
        label: info.name,
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(112, 72),
            maximumSize: const Size(112, double.infinity),
            padding: EdgeInsets.zero,
            foregroundColor: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
            backgroundColor: selected
                ? colorScheme.primaryContainer
                : colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: onPressed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.iconData, size: 24),
              const SizedBox(height: 4),
              Text(info.name, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
