import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('runtime capabilities describe the actual editor and canvas split', () {
    final capabilities = MathWorkspaceCapabilities.current;
    expect(capabilities.mathLiveEditor, MathFormulaField.supported);
    expect(capabilities.sourceEditorFallback, isTrue);
    expect(capabilities.mathCanvasWebViewRequiresNetwork, isTrue);
    expect(capabilities.flutterCanvasesRequireNetwork, isFalse);
  });

  test(
    'persistence keeps legacy keys by default and namespaces embedded use',
    () {
      const defaults = MathWorkspacePersistence();
      const isolated = MathWorkspacePersistence(namespace: 'editor-2');
      expect(
        defaults.key('math_drawing_mathematical_input'),
        'math_drawing_mathematical_input',
      );
      expect(
        isolated.key('math_drawing_mathematical_input'),
        'visual_math.editor-2.math_drawing_mathematical_input',
      );
    },
  );
}
