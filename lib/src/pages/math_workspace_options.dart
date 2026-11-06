import 'package:flutter/material.dart';

import '../models/math_drawing_state.dart';
import '../models/math_3d_tool.dart';
import '../models/math_parameter.dart';

/// Builds a workspace region from its default package-provided content.
///
/// Return [defaultContent] unchanged to keep the default region, wrap it to
/// customize its presentation, or return another widget to replace it.
typedef MathWorkspaceRegionBuilder = Widget Function(
  BuildContext context,
  Widget defaultContent,
  MathWorkspaceRegionActions actions,
);

/// Builds an app bar from the package-provided default app bar.
typedef MathWorkspaceAppBarBuilder = PreferredSizeWidget Function(
  BuildContext context,
  PreferredSizeWidget defaultAppBar,
);

/// Labels for the workspace chrome that commonly needs host localization.
/// Unspecified values retain the package's Chinese defaults.
class MathWorkspaceLabels {
  final String pageTitle;
  final String addFormula;
  final String view2D;
  final String view3D;
  final String removeFormulaTitle;
  final String confirmRemoveFormula;
  final String selectColorTitle;
  final String cancel;
  final String removeFormula;
  final String hideFormula;
  final String showFormula;
  final String plotFormula;
  final String fit2DCanvas;
  final String zoomIn;
  final String zoomOut;
  final String formulaLabel;
  final String formulaColorLabel;
  final String Function(String sourceText)? translate;

  const MathWorkspaceLabels({
    this.pageTitle = '数学绘图',
    this.addFormula = '添加公式',
    this.view2D = '2D',
    this.view3D = '3D',
    this.removeFormulaTitle = '删除公式',
    this.confirmRemoveFormula = '确定要删除"公式 {index}"吗？',
    this.selectColorTitle = '选择颜色',
    this.cancel = '取消',
    this.removeFormula = '删除公式',
    this.hideFormula = '隐藏公式',
    this.showFormula = '显示公式',
    this.plotFormula = '绘制',
    this.fit2DCanvas = '缩放至适合',
    this.zoomIn = '放大',
    this.zoomOut = '缩小',
    this.formulaLabel = '公式 {index}',
    this.formulaColorLabel = '公式颜色 {index}',
    this.translate,
  });

  /// Replaces a numbered `{index}` placeholder in a workspace label.
  String withIndex(String pattern, int index) =>
      resolve(pattern.replaceAll('{index}', '$index'));

  /// Translates a package default label when a host translation callback exists.
  String resolve(String sourceText) =>
      translate?.call(sourceText) ?? sourceText;
}

/// Density choices for the package-owned workspace layout.
enum MathWorkspaceDensity { comfortable, compact }

/// Anchor for the built-in 2D canvas actions.
enum MathWorkspaceControlPlacement { bottomEnd, bottomStart }

/// Selects which pointer families can manipulate package-owned canvases.
class MathWorkspaceInteractionPolicy {
  final bool allowTouchGestures;
  final bool allowMouseGestures;

  const MathWorkspaceInteractionPolicy({
    this.allowTouchGestures = true,
    this.allowMouseGestures = true,
  });
}

/// Presentation-level controls for hosts embedding [MathDrawingPage].
///
/// Flutter [Theme] remains the source of colors and typography. These options
/// adjust package layout and provide localized labels and error surfaces.
class MathWorkspacePresentation {
  final MathWorkspaceLabels labels;
  final MathWorkspaceDensity density;

  /// Optional inset applied to both canvases. Omission preserves each view's
  /// historical spacing.
  final EdgeInsets? canvasInset;
  final EdgeInsets controlInset;
  final double responsiveBreakpoint;
  final MathWorkspaceControlPlacement controlPlacement;
  final MathWorkspaceInteractionPolicy interactionPolicy;
  final Widget Function(BuildContext context, Widget dialog)? dialogBuilder;
  final Widget Function(BuildContext context, String message)? errorBuilder;

  const MathWorkspacePresentation({
    this.labels = const MathWorkspaceLabels(),
    this.density = MathWorkspaceDensity.comfortable,
    this.canvasInset,
    this.controlInset = const EdgeInsets.fromLTRB(8, 0, 8, 8),
    this.responsiveBreakpoint = 0,
    this.controlPlacement = MathWorkspaceControlPlacement.bottomEnd,
    this.interactionPolicy = const MathWorkspaceInteractionPolicy(),
    this.dialogBuilder,
    this.errorBuilder,
  }) : assert(responsiveBreakpoint >= 0);

  /// Whether the compact layout should be used for the supplied width.
  /// A zero breakpoint keeps the default layout at every width.
  bool isCompactForWidth(double width) =>
      density == MathWorkspaceDensity.compact || width < responsiveBreakpoint;

  /// Inset applied to the 2D canvas, retaining its original default spacing.
  EdgeInsets get canvasInset2D =>
      canvasInset ?? const EdgeInsets.symmetric(horizontal: 8);

  /// Inset applied to the 3D canvas, retaining its original default spacing.
  EdgeInsets get canvasInset3D =>
      canvasInset ?? const EdgeInsets.fromLTRB(8, 4, 8, 8);

  /// Builds the configured error content, or the default plain message.
  Widget buildError(BuildContext context, String message) =>
      errorBuilder?.call(context, message) ?? Text(message);

  /// Wraps a package dialog with the host's dialog surface when configured.
  Widget buildDialog(BuildContext context, Widget dialog) =>
      dialogBuilder?.call(context, dialog) ?? dialog;
}

/// Page-owned values and actions available to custom workspace regions.
///
/// A replacement builder can use these callbacks to keep its controls
/// connected to the package-owned canvases and formula state.
class MathWorkspaceRegionActions {
  /// The currently selected available view.
  final ViewMode activeView;

  /// Selects an available view.
  final Future<void> Function(ViewMode view) setActiveView;

  /// The currently selected 3D construction tool.
  final ConstructionTool active3DTool;

  /// The number of formula rows currently in the workspace.
  final int formulaCount;

  /// The current 3D polygon side count.
  final int polygonSides;

  /// The current 3D construction instruction, when present.
  final String? toolInstruction;

  /// The active parameter values shown in the 2D view.
  final Map<String, MathParameter> parameters;

  /// Whether the active editor is ready to receive commands.
  final bool editorReady;

  /// Whether the active editor supports directional structural navigation.
  final bool supportsStructuralNavigation;

  /// Whether the active editor supports structured editing commands.
  final bool supportsStructuredEditing;

  /// The label of the active formula row, if any.
  final String? activeFormulaLabel;

  /// The active editor's current caret location.
  final String? editorLocation;

  /// Selects a 3D construction tool.
  final ValueChanged<ConstructionTool> select3DTool;

  /// Updates the polygon side count used by polygon tools.
  final ValueChanged<int> setPolygonSides;

  /// Updates a formula draft at [index]. Call [plot] to commit it to a canvas.
  final void Function(int index, String expression) setFormulaExpression;

  /// Reads the current formula draft at [index], or returns null if missing.
  final String? Function(int index) formulaExpression;

  /// Adds a formula row.
  final VoidCallback addFormula;

  /// Activates the formula at [index] and shows the configured keyboard.
  ///
  /// This lets a replacement input panel pair its own editor with a custom
  /// keyboard while retaining the workspace's formula and plot actions.
  final ValueChanged<int> activateFormula;

  /// Toggles visibility of the formula at [index] and replots the workspace.
  final Future<void> Function(int index) toggleFormulaVisibility;

  /// Opens the package confirmation flow to remove the formula at [index].
  final void Function(int index) removeFormula;

  /// Plots current formula drafts in the active view.
  final Future<void> Function() plot;

  /// Updates a parameter in the active 2D view.
  final void Function(String name, MathParameter parameter) setParameter;

  /// Dismisses the package math keyboard.
  final VoidCallback dismissKeyboard;

  /// Sends an insertion, navigation, command, or clipboard request to the
  /// active formula editor so it preserves its current caret and selection.
  final Future<void> Function(String kind, String value) sendEditorCommand;

  /// Fits the 2D canvas to its plotted content.
  final VoidCallback fit2DCanvas;

  /// Zooms in on the 2D canvas.
  final VoidCallback zoomIn2DCanvas;

  /// Zooms out on the 2D canvas.
  final VoidCallback zoomOut2DCanvas;

  /// Fits the 3D canvas to its scene.
  final VoidCallback fit3DCanvas;

  /// Zooms in on the 3D canvas.
  final VoidCallback zoomIn3DCanvas;

  /// Zooms out on the 3D canvas.
  final VoidCallback zoomOut3DCanvas;

  /// Creates values and callbacks for a workspace region builder.
  const MathWorkspaceRegionActions({
    required this.activeView,
    required this.setActiveView,
    required this.active3DTool,
    required this.formulaCount,
    required this.polygonSides,
    required this.toolInstruction,
    required this.parameters,
    required this.editorReady,
    required this.supportsStructuralNavigation,
    required this.supportsStructuredEditing,
    required this.activeFormulaLabel,
    required this.editorLocation,
    required this.select3DTool,
    required this.setPolygonSides,
    required this.setFormulaExpression,
    required this.formulaExpression,
    required this.addFormula,
    required this.activateFormula,
    required this.toggleFormulaVisibility,
    required this.removeFormula,
    required this.plot,
    required this.setParameter,
    required this.dismissKeyboard,
    required this.sendEditorCommand,
    required this.fit2DCanvas,
    required this.zoomIn2DCanvas,
    required this.zoomOut2DCanvas,
    required this.fit3DCanvas,
    required this.zoomIn3DCanvas,
    required this.zoomOut3DCanvas,
  });
}

/// Selects which built-in views and workspace regions [MathDrawingPage] shows.
///
/// Defaults preserve the complete, turnkey workspace. Set [show2D] or
/// [show3D] to false for a focused workspace, and use the region builders to
/// wrap or replace package-provided controls. A host can set [showScaffold] to
/// false when embedding the workspace inside its own page body.
class MathWorkspaceOptions {
  /// Whether the 2D plotting view is available.
  final bool show2D;

  /// Whether the 3D geometry view is available.
  final bool show3D;

  /// Which available view is selected when the workspace is first created.
  final ViewMode initialView;

  /// Whether to show the built-in selector when both views are available.
  final bool showViewSelector;

  /// Whether to show the package-owned [Scaffold] around the workspace.
  final bool showScaffold;

  /// Whether to show the default app bar when [showScaffold] is true.
  final bool showAppBar;

  /// Whether to include formula editor rows in the formula panel.
  final bool showFormulaEditor;

  /// Whether to show discovered parameter controls in the formula panel.
  final bool showParameterControls;

  /// Whether the built-in math keyboard can be shown while editing.
  final bool showKeyboard;

  /// Whether to show the built-in construction tools above the 3D canvas.
  final bool show3DTools;

  /// Whether to show the built-in zoom and fit actions over the 2D canvas.
  final bool show2DCanvasActions;

  /// Wraps or replaces the default app bar.
  final MathWorkspaceAppBarBuilder? appBarBuilder;

  /// Wraps or replaces the built-in 2D/3D selector.
  final MathWorkspaceRegionBuilder? viewSelectorBuilder;

  /// Wraps or replaces the formula editor panel.
  final MathWorkspaceRegionBuilder? formulaEditorBuilder;

  /// Wraps or replaces the built-in parameter controls.
  final MathWorkspaceRegionBuilder? parameterControlsBuilder;

  /// Wraps or replaces the built-in math keyboard.
  final MathWorkspaceRegionBuilder? keyboardBuilder;

  /// Wraps or replaces the 3D construction toolbar.
  final MathWorkspaceRegionBuilder? threeDToolsBuilder;

  /// Wraps or replaces the 2D canvas zoom and fit actions.
  final MathWorkspaceRegionBuilder? canvas2DActionsBuilder;

  /// Wraps or replaces overlays on top of the 2D canvas.
  final MathWorkspaceRegionBuilder? canvas2DOverlayBuilder;

  /// Wraps or replaces overlays on top of the 3D canvas.
  final MathWorkspaceRegionBuilder? canvas3DOverlayBuilder;

  /// Localized labels, responsive density, spacing, and error presentation.
  final MathWorkspacePresentation presentation;

  /// Creates workspace options with the turnkey UI enabled by default.
  const MathWorkspaceOptions({
    this.show2D = true,
    this.show3D = true,
    this.initialView = ViewMode.mode2D,
    this.showViewSelector = true,
    this.showScaffold = true,
    this.showAppBar = true,
    this.showFormulaEditor = true,
    this.showParameterControls = true,
    this.showKeyboard = true,
    this.show3DTools = true,
    this.show2DCanvasActions = true,
    this.appBarBuilder,
    this.viewSelectorBuilder,
    this.formulaEditorBuilder,
    this.parameterControlsBuilder,
    this.keyboardBuilder,
    this.threeDToolsBuilder,
    this.canvas2DActionsBuilder,
    this.canvas2DOverlayBuilder,
    this.canvas3DOverlayBuilder,
    this.presentation = const MathWorkspacePresentation(),
  }) : assert(show2D || show3D, 'At least one workspace view is required.'),
       assert(
         (show2D && initialView == ViewMode.mode2D) ||
             (show3D && initialView == ViewMode.mode3D),
         'The initial view must be enabled.',
       );
}
