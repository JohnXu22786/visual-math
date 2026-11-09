import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/visual_math.dart';

void main() => runApp(const VisualMathExampleApp());

class VisualMathExampleApp extends StatefulWidget {
  const VisualMathExampleApp({super.key});

  @override
  State<VisualMathExampleApp> createState() => _VisualMathExampleAppState();
}

class _VisualMathExampleAppState extends State<VisualMathExampleApp> {
  static const _themeKey = 'visual_math_app_theme';
  static const _languageKey = 'visual_math_app_language';
  static const _mathModeKey = 'math_drawing_mathematical_input';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isEnglish = false;
  bool _mathematicalMode = true;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeMode = switch (preferences.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _isEnglish = preferences.getString(_languageKey) == 'en';
      _mathematicalMode = preferences.getBool(_mathModeKey) ?? true;
      _preferencesLoaded = true;
    });
  }

  Future<void> _setThemeMode(ThemeMode value) async {
    setState(() => _themeMode = value);
    await (await SharedPreferences.getInstance()).setString(
      _themeKey,
      switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  Future<void> _setLanguage(bool english) async {
    setState(() => _isEnglish = english);
    await (await SharedPreferences.getInstance()).setString(
      _languageKey,
      english ? 'en' : 'zh',
    );
  }

  Future<void> _setMathematicalMode(bool value) async {
    setState(() => _mathematicalMode = value);
    await (await SharedPreferences.getInstance()).setBool(_mathModeKey, value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: _isEnglish ? 'Visual Math' : '数学绘图',
    themeMode: _themeMode,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: _preferencesLoaded
        ? _VisualMathShell(
            isEnglish: _isEnglish,
            themeMode: _themeMode,
            mathematicalMode: _mathematicalMode,
            onThemeModeChanged: _setThemeMode,
            onLanguageChanged: _setLanguage,
            onMathematicalModeChanged: _setMathematicalMode,
          )
        : const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}

class _VisualMathShell extends StatefulWidget {
  const _VisualMathShell({
    required this.isEnglish,
    required this.themeMode,
    required this.mathematicalMode,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
    required this.onMathematicalModeChanged,
  });

  final bool isEnglish;
  final ThemeMode themeMode;
  final bool mathematicalMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onLanguageChanged;
  final ValueChanged<bool> onMathematicalModeChanged;

  @override
  State<_VisualMathShell> createState() => _VisualMathShellState();
}

class _VisualMathShellState extends State<_VisualMathShell> {
  static const _breakpoint = 720.0;
  int _selectedIndex = 0;

  List<String> get _destinations => widget.isEnglish
      ? const ['Home', 'Files', 'Settings']
      : const ['主页', '文件', '设置'];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _breakpoint;
    final titles = _destinations;
    final pages = [
      _HomeDestination(
        isEnglish: widget.isEnglish,
        mathematicalMode: widget.mathematicalMode,
        onMathematicalModeChanged: widget.onMathematicalModeChanged,
      ),
      _FilesDestination(isEnglish: widget.isEnglish),
      _SettingsDestination(
        isEnglish: widget.isEnglish,
        isActive: _selectedIndex == 2,
        themeMode: widget.themeMode,
        mathematicalMode: widget.mathematicalMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onLanguageChanged: widget.onLanguageChanged,
        onMathematicalModeChanged: widget.onMathematicalModeChanged,
      ),
    ];
    final content = IndexedStack(index: _selectedIndex, children: pages);

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
      ),
      body: Row(
        children: [
          if (wide) ...[
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: Text(titles[0]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.folder_outlined),
                  selectedIcon: const Icon(Icons.folder),
                  label: Text(titles[1]),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: Text(titles[2]),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(key: const ValueKey('destination-pages'), child: content),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: titles[0],
                ),
                NavigationDestination(
                  icon: const Icon(Icons.folder_outlined),
                  selectedIcon: const Icon(Icons.folder),
                  label: titles[1],
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: titles[2],
                ),
              ],
            ),
    );
  }
}

class _HomeDestination extends StatelessWidget {
  const _HomeDestination({
    required this.isEnglish,
    required this.mathematicalMode,
    required this.onMathematicalModeChanged,
  });

  final bool isEnglish;
  final bool mathematicalMode;
  final ValueChanged<bool> onMathematicalModeChanged;

  @override
  Widget build(BuildContext context) => MathDrawingPage(
    initialMathematicalMode: mathematicalMode,
    onMathematicalModeChanged: onMathematicalModeChanged,
    options: MathWorkspaceOptions(
      persistence: const MathWorkspacePersistence(enabled: false),
      showScaffold: false,
      showAppBar: false,
      presentation: MathWorkspacePresentation(
        labels: MathWorkspaceLabels(
          pageTitle: isEnglish ? 'Graphs' : '数学绘图',
          addFormula: isEnglish ? 'Add formula' : '添加公式',
          view2D: isEnglish ? 'Graphs' : '图像',
          view3D: isEnglish ? 'Geometry' : '几何',
          removeFormulaTitle: isEnglish ? 'Remove formula' : '删除公式',
          confirmRemoveFormula: isEnglish
              ? 'Remove formula {index}?'
              : '确定要删除"公式 {index}"吗？',
          selectColorTitle: isEnglish ? 'Select color' : '选择颜色',
          cancel: isEnglish ? 'Cancel' : '取消',
          removeFormula: isEnglish ? 'Remove' : '删除',
          removeFormulaTooltip: isEnglish ? 'Remove formula' : '删除公式',
          hideFormula: isEnglish ? 'Hide formula' : '隐藏公式',
          showFormula: isEnglish ? 'Show formula' : '显示公式',
          plotFormula: isEnglish ? 'Plot' : '绘制',
          fit2DCanvas: isEnglish ? 'Fit graph' : '缩放至适合',
          zoomIn: isEnglish ? 'Zoom in' : '放大',
          zoomOut: isEnglish ? 'Zoom out' : '缩小',
          formulaLabel: isEnglish ? 'Formula {index}' : '公式 {index}',
          formulaColorLabel: isEnglish
              ? 'Formula color {index}'
              : '公式颜色 {index}',
          translate: isEnglish ? _englishWorkspaceLabel : null,
        ),
        responsiveBreakpoint: 720,
      ),
    ),
  );
}

class _FilesDestination extends StatelessWidget {
  const _FilesDestination({required this.isEnglish});

  final bool isEnglish;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      isEnglish ? 'Files will be available here.' : '文件功能后续开放',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}

class _SettingsDestination extends StatefulWidget {
  const _SettingsDestination({
    required this.isEnglish,
    required this.isActive,
    required this.themeMode,
    required this.mathematicalMode,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
    required this.onMathematicalModeChanged,
  });

  final bool isEnglish;
  final bool isActive;
  final ThemeMode themeMode;
  final bool mathematicalMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onLanguageChanged;
  final ValueChanged<bool> onMathematicalModeChanged;

  @override
  State<_SettingsDestination> createState() => _SettingsDestinationState();
}

class _SettingsDestinationState extends State<_SettingsDestination> {
  static const _mathModeKey = 'math_drawing_mathematical_input';

  @override
  void initState() {
    super.initState();
    _refreshMathematicalMode();
  }

  @override
  void didUpdateWidget(_SettingsDestination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _refreshMathematicalMode();
  }

  Future<void> _refreshMathematicalMode() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getBool(_mathModeKey) ?? widget.mathematicalMode;
    if (mounted && value != widget.mathematicalMode) {
      widget.onMathematicalModeChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = widget.isEnglish;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isEnglish ? 'Appearance' : '外观',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(isEnglish ? 'System' : '跟随系统'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(isEnglish ? 'Light' : '浅色'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(isEnglish ? 'Dark' : '深色'),
            ),
          ],
          selected: {widget.themeMode},
          onSelectionChanged: (selection) =>
              widget.onThemeModeChanged(selection.first),
        ),
        const SizedBox(height: 24),
        Text(isEnglish ? 'Language' : '语言', style: theme.textTheme.titleLarge),
        RadioGroup<bool>(
          groupValue: isEnglish,
          onChanged: (value) {
            if (value != null) widget.onLanguageChanged(value);
          },
          child: Column(
            children: [
              RadioListTile<bool>(value: false, title: const Text('中文')),
              RadioListTile<bool>(value: true, title: const Text('English')),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isEnglish ? 'Math input' : '数学输入',
          style: theme.textTheme.titleLarge,
        ),
        RadioGroup<bool>(
          groupValue: widget.mathematicalMode,
          onChanged: (value) {
            if (value != null) widget.onMathematicalModeChanged(value);
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: true,
                title: Text(isEnglish ? 'Math editor' : '数学编辑器'),
              ),
              RadioListTile<bool>(
                value: false,
                title: Text(isEnglish ? 'Text input' : '文本输入'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        ListTile(
          dense: true,
          leading: Icon(
            Icons.code,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            isEnglish ? 'Developer examples' : '开发者示例',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ExampleMenu()),
          ),
        ),
      ],
    );
  }
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
    _controller.onPlotted = (snapshot) => debugPrint(
      'Saved ${snapshot.formulas.length} formulas; '
      'view=${snapshot.activeView.name}',
    );
    _controller.onError = (message) => debugPrint('Plot error: $message');
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
