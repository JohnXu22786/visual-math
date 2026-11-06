import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visual_math/visual_math.dart';

void main() => runApp(const VisualMathExampleApp());

class VisualMathExampleApp extends StatelessWidget {
  const VisualMathExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Visual Math integration examples',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
    ),
    home: const ExampleMenu(),
  );
}

class ExampleMenu extends StatelessWidget {
  const ExampleMenu({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Visual Math examples')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ExampleLink(
          title: 'Standalone 2D canvas',
          subtitle: 'A graph without the formula editor or 3D workspace.',
          page: const Standalone2DExample(),
        ),
        _ExampleLink(
          title: 'Standalone 3D canvas',
          subtitle: 'A pure-Flutter 3D canvas embedded by the host.',
          page: const Standalone3DExample(),
        ),
        _ExampleLink(
          title: 'Customized workspace',
          subtitle: 'Host branding, labels, controller, and preferences.',
          page: const CustomizedWorkspaceExample(),
        ),
        const _CapabilitiesCard(),
      ],
    ),
  );
}

class _ExampleLink extends StatelessWidget {
  const _ExampleLink({
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final String title;
  final String subtitle;
  final Widget page;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page)),
    ),
  );
}

class Standalone2DExample extends StatelessWidget {
  const Standalone2DExample({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('2D only')),
    body: const SafeArea(child: MathCanvas(initialExpression: 'sin(x)')),
  );
}

class Standalone3DExample extends StatelessWidget {
  const Standalone3DExample({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('3D only')),
    body: const SafeArea(child: MathCanvas3D()),
  );
}

class CustomizedWorkspaceExample extends StatefulWidget {
  const CustomizedWorkspaceExample({super.key});

  @override
  State<CustomizedWorkspaceExample> createState() =>
      _CustomizedWorkspaceExampleState();
}

class _CustomizedWorkspaceExampleState
    extends State<CustomizedWorkspaceExample> {
  late final MathDrawingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MathDrawingController();
    _controller
      ..onPlotted = (snapshot) => debugPrint(
        'Saved ${snapshot.formulas.length} formulas; '
        'view=${snapshot.activeView.name}',
      )..onError = (message) => debugPrint('Plot error: $message');
  }

  @override
  Widget build(BuildContext context) => MathDrawingPage(
    initialExpression: 'x^2',
    controller: _controller,
    options: MathWorkspaceOptions(
      persistence: const MathWorkspacePersistence(
        namespace: 'integration_demo',
      ),
      clipboardReader: () async =>
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      clipboardWriter: (text) => Clipboard.setData(ClipboardData(text: text)),
      presentation: const MathWorkspacePresentation(
        labels: MathWorkspaceLabels(
          pageTitle: 'Studio Math',
          addFormula: 'Add equation',
          view2D: 'Graphs',
          view3D: 'Geometry',
          removeFormulaTitle: 'Remove equation',
          confirmRemoveFormula: 'Remove equation {index}?',
          selectColorTitle: 'Choose color',
          cancel: 'Cancel',
          removeFormula: 'Remove',
          removeFormulaTooltip: 'Remove equation',
          hideFormula: 'Hide equation',
          showFormula: 'Show equation',
          plotFormula: 'Plot',
          fit2DCanvas: 'Fit graph',
          zoomIn: 'Zoom in',
          zoomOut: 'Zoom out',
          formulaLabel: 'Equation {index}',
          formulaColorLabel: 'Equation color {index}',
          translate: _englishWorkspaceLabel,
        ),
        density: MathWorkspaceDensity.compact,
        responsiveBreakpoint: 720,
      ),
      appBarBuilder: (context, defaultAppBar) => AppBar(
        title: const Text('Acme • Studio Math'),
        actions: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: _controller.zoomIn,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: 'Reset view',
            onPressed: _controller.resetView,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      canvas2DOverlayBuilder: (context, defaultOverlay, actions) => Stack(
        children: [
          defaultOverlay,
          Positioned(
            left: 12,
            top: 12,
            child: FilledButton.tonal(
              onPressed: actions.fit2DCanvas,
              child: const Text('Fit'),
            ),
          ),
        ],
      ),
    ),
  );
}

// Translate additional package-owned canvas and toolbar strings as needed.
// Unmapped text intentionally remains the package's source-language label.
String _englishWorkspaceLabel(String source) =>
    const {
      '3D 视图设置': '3D view settings',
      'xOy 平面': 'xOy plane',
      '侧视 yOz': 'Side view yOz',
      '俯视 xOy': 'Top view xOy',
      '删除对象': 'Delete object',
      '取消': 'Cancel',
      '坐标轴': 'Axes',
      '填充色': 'Fill color',
      '展开图': 'Unfold net',
      '平行投影': 'Parallel projection',
      '放大': 'Zoom in',
      '显示棱': 'Show edges',
      '标准视图': 'Standard view',
      '棱宽 (0–6)': 'Edge width (0–6)',
      '正视 xOz': 'Front view xOz',
      '添加': 'Add',
      '添加文本': 'Add text',
      '点': 'Points',
      '点击切换': 'Tap to switch',
      '立体图形': '3D object',
      '缩小': 'Zoom out',
      '缩放至适合': 'Fit to view',
      '网格': 'Grid',
      '视图方向': 'View direction',
      '输入要显示的内容': 'Enter text to display',
      '选择填充颜色': 'Choose fill color',
      '选择颜色': 'Choose color',
      '透视投影': 'Perspective projection',
      '基本工具': 'Basic',
      '编辑': 'Edit',
      '直线与多边形': 'Lines and polygons',
      '平面': 'Planes',
      '圆': 'Circles',
      '曲线': 'Curves',
      '变换': 'Transforms',
      '度量': 'Measurements',
      '其它': 'Other',
      '特殊直线': 'Special lines',
      '移动': 'Move',
      '拖动点移动对象；点击已选点切换平面/高度移动；空白处拖动旋转视图':
          'Drag points to move objects; drag empty space to orbit',
    }[source] ??
    source;

class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard();

  @override
  Widget build(BuildContext context) {
    final capabilities = MathWorkspaceCapabilities.current;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Runtime capabilities',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('MathLive editor: ${capabilities.mathLiveEditor}'),
            Text(
              'Source editor fallback: ${capabilities.sourceEditorFallback}',
            ),
            Text(
              'Separate JSXGraph WebView needs network: '
              '${capabilities.mathCanvasWebViewRequiresNetwork}',
            ),
            Text(
              'Primary Flutter canvases need network: '
              '${capabilities.flutterCanvasesRequireNetwork}',
            ),
          ],
        ),
      ),
    );
  }
}
