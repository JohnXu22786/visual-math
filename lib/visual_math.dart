/// Public models and widgets for the Visual Math Flutter package.
///
/// Use exported models to build app-owned math UI, compose focused widgets such
/// as [MathCanvas] and [MathCanvas3D], or place [MathDrawingPage] for the
/// complete editor, graphing, and geometry workspace. The focused widgets
/// expose their documented inputs, callbacks, and state APIs; the complete
/// workspace keeps its internal state package-owned.
library visual_math;

export 'src/models/formula_entry.dart';
export 'src/models/math_3d_construction.dart';
export 'src/models/math_3d_object.dart';
export 'src/models/math_3d_scene.dart';
export 'src/models/math_3d_tool.dart';
export 'src/models/math_3d_relationship.dart';
export 'src/models/math_drawing_state.dart';
export 'src/models/math_drawing_controller.dart';
export 'src/models/math_drawing_document.dart';
export 'src/models/math_drawing_storage_error.dart';
export 'src/models/math_drawing_storage.dart';
export 'src/models/math_expression.dart';
export 'src/models/math_expression_3d.dart';
export 'src/models/math_input_catalog.dart';
export 'src/models/math_parameter.dart';
export 'src/pages/math_drawing_page.dart';
export 'src/pages/math_workspace_options.dart';
export 'src/pages/math_workspace_capabilities.dart';
export 'src/widgets/math_3d_toolbar.dart';
export 'src/widgets/math_canvas.dart';
export 'src/widgets/math_canvas_3d.dart';
export 'src/widgets/math_canvas_webview.dart'
    hide OnCoordinateUpdate, OnViewportChange, OnReady, OnError;
export 'src/widgets/math_formula_field.dart';
export 'src/widgets/math_keyboard.dart';
export 'src/widgets/math_parameter_controls.dart';
