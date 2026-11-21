import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visual_math/visual_math.dart';

import 'orbiting_math_splash.dart';

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
    home: const _ExampleStartupHost(),
  );
}

class _ExampleStartupHost extends StatefulWidget {
  const _ExampleStartupHost();

  @override
  State<_ExampleStartupHost> createState() => _ExampleStartupHostState();
}

class _ExampleStartupHostState extends State<_ExampleStartupHost> {
  double _progress = 0;
  bool _splashVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _progress = 1);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ExampleMenu(),
      if (_splashVisible)
        OrbitingMathSplash(
          progress: _progress,
          onTransitionComplete: () {
            if (mounted) setState(() => _splashVisible = false);
          },
        ),
    ],
  );
}

class ExampleMenu extends StatefulWidget {
  const ExampleMenu({
    super.key,
    this.documentStorage = const MathDrawingStorage(),
  });
  final MathDrawingStorage documentStorage;

  @override
  State<ExampleMenu> createState() => _ExampleMenuState();
}

class _ExampleMenuState extends State<ExampleMenu> {
  int _selected = 0;
  late Future<List<String>> _names;
  ThemeMode _themeMode = ThemeMode.system;
  bool _busy = false;
  bool _grid = false;
  bool _descending = false;
  bool _selecting = false;
  String _query = '';
  final Set<String> _selectedNames = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _names = widget.documentStorage.listNames();
  }

  Future<void> _open({String? name, ViewMode view = ViewMode.mode2D}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final document = name == null
          ? null
          : await widget.documentStorage.load(name);
      if (name != null && document == null) throw StateError('绘图不存在');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Theme(
            data: _theme(context),
            child: MathDrawingPage(
              initialDocument: document,
              controller: MathDrawingController(),
              documentStorage: widget.documentStorage,
              options: MathWorkspaceOptions(initialView: view),
            ),
          ),
        ),
      );
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开绘图：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除绘图？'),
        content: Text('确定删除“$name”吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.documentStorage.delete(name);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法删除绘图：$error')));
    }
  }

  ThemeData _theme(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: _themeMode == ThemeMode.system
          ? MediaQuery.platformBrightnessOf(context)
          : (_themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(elevation: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme(context);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final wide =
              MediaQuery.sizeOf(context).width >=
              MediaQuery.sizeOf(context).height;
          final pages = [_home(context), _files(context), _settings(context)];
          const destinations = [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '文件',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ];
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  if (wide)
                    NavigationRail(
                      selectedIndex: _selected,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() {
                        _selected = i;
                        if (i == 1) _refresh();
                      }),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('首页'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.folder_outlined),
                          selectedIcon: Icon(Icons.folder),
                          label: Text('文件'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('设置'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: IndexedStack(index: _selected, children: pages),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _selected,
                    destinations: destinations,
                    onDestinationSelected: (i) => setState(() {
                      _selected = i;
                      if (i == 1) _refresh();
                    }),
                  ),
          );
        },
      ),
    );
  }

  Widget _home(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.functions_rounded,
                        color: cs.onPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Visual Math',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            '用图形探索数学',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Text(
                  '从一个想法开始',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '选择画布，开始探索函数与几何。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final vertical = constraints.maxWidth < 360;
                    return Flex(
                      direction: vertical ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: vertical
                          ? CrossAxisAlignment.stretch
                          : CrossAxisAlignment.start,
                      children: [
                        if (vertical)
                          _canvasCard(
                            context,
                            '2D 绘图',
                            '绘制函数，观察曲线变化',
                            Icons.show_chart_rounded,
                            false,
                            () => _open(),
                          )
                        else
                          Expanded(
                            child: _canvasCard(
                              context,
                              '2D 绘图',
                              '绘制函数，观察曲线变化',
                              Icons.show_chart_rounded,
                              false,
                              () => _open(),
                            ),
                          ),
                        SizedBox(
                          width: vertical ? 0 : 12,
                          height: vertical ? 12 : 0,
                        ),
                        if (vertical)
                          _canvasCard(
                            context,
                            '3D 几何',
                            '构造图形，探索空间关系',
                            Icons.view_in_ar_rounded,
                            true,
                            () => _open(view: ViewMode.mode3D),
                          )
                        else
                          Expanded(
                            child: _canvasCard(
                              context,
                              '3D 几何',
                              '构造图形，探索空间关系',
                              Icons.view_in_ar_rounded,
                              true,
                              () => _open(view: ViewMode.mode3D),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已保存的绘图',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _selected = 1;
                        _refresh();
                      }),
                      child: const Text('查看全部'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _drawingList(context, compact: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _canvasCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool is3d,
    VoidCallback action,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : action,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 76,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MathSketchPainter(
                          color: cs.primary,
                          is3d: is3d,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          icon,
                          size: 21,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _files(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<String>>(
      future: _names,
      builder: (context, snapshot) {
        final names = snapshot.data ?? <String>[];
        final visible =
            names
                .where(
                  (name) => name.toLowerCase().contains(_query.toLowerCase()),
                )
                .toList()
              ..sort((a, b) => _descending ? b.compareTo(a) : a.compareTo(b));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  if (_selecting)
                    IconButton(
                      tooltip: '取消选择',
                      onPressed: () => setState(() {
                        _selecting = false;
                        _selectedNames.clear();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  Expanded(
                    child: Text(
                      _selecting ? '已选择 ${_selectedNames.length} 项' : '文件',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_selecting)
                    IconButton(
                      tooltip: '全选',
                      onPressed: () => setState(() {
                        if (visible.every(_selectedNames.contains)) {
                          _selectedNames.removeAll(visible);
                        } else {
                          _selectedNames.addAll(visible);
                        }
                      }),
                      icon: const Icon(Icons.select_all),
                    )
                  else ...[
                    PopupMenuButton<bool>(
                      tooltip: '名称排序',
                      icon: const Icon(Icons.sort),
                      onSelected: (value) =>
                          setState(() => _descending = value),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: false,
                          checked: !_descending,
                          child: const Text('名称升序'),
                        ),
                        CheckedPopupMenuItem(
                          value: true,
                          checked: _descending,
                          child: const Text('名称降序'),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: _grid ? '列表视图' : '网格视图',
                      onPressed: () => setState(() => _grid = !_grid),
                      icon: Icon(
                        _grid
                            ? Icons.view_list_outlined
                            : Icons.grid_view_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _busy ? null : () => setState(_refresh),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '新建绘图',
                      onPressed: _busy ? null : () => _open(),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SearchBar(
                leading: const Icon(Icons.search),
                hintText: '搜索绘图',
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: snapshot.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.hasError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('无法读取绘图列表'),
                          TextButton(
                            onPressed: () => setState(_refresh),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : visible.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _query.isEmpty
                                ? Icons.folder_open_outlined
                                : Icons.search_off,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(_query.isEmpty ? '还没有保存的绘图' : '没有匹配的绘图'),
                          if (_query.isEmpty)
                            TextButton(
                              onPressed: _busy ? null : () => _open(),
                              child: const Text('新建绘图'),
                            ),
                        ],
                      ),
                    )
                  : _grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 210,
                            mainAxisExtent: 160,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _fileItem(context, visible[index], grid: true),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _fileItem(context, visible[index]),
                    ),
            ),
            if (_selecting)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.tonalIcon(
                    onPressed: _selectedNames.isEmpty || _busy
                        ? null
                        : _deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      '删除所选',
                      style: TextStyle(
                        color: _selectedNames.isEmpty || _busy
                            ? theme.colorScheme.onSurface.withValues(alpha: .38)
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _toggleFile(String name) => setState(() {
    if (!_selectedNames.add(name)) _selectedNames.remove(name);
  });

  Widget _fileItem(BuildContext context, String name, {bool grid = false}) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedNames.contains(name);
    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.functions, color: cs.onPrimaryContainer),
    );
    final menu = PopupMenuButton<String>(
      tooltip: '文件操作',
      onSelected: (value) {
        if (value == 'open') _open(name: name);
        if (value == 'select')
          setState(() {
            _selecting = true;
            _selectedNames.add(name);
          });
        if (value == 'copy') _copyOrRename(name, false);
        if (value == 'rename') _copyOrRename(name, true);
        if (value == 'delete') _delete(name);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        PopupMenuItem(value: 'select', child: Text('选择')),
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: cs.error)),
        ),
      ],
    );
    return Card(
      margin: grid ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _busy
            ? null
            : () => _selecting ? _toggleFile(name) : _open(name: name),
        onLongPress: _busy
            ? null
            : () => setState(() {
                _selecting = true;
                _selectedNames.add(name);
              }),
        child: grid
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        icon,
                        const Spacer(),
                        if (_selecting)
                          Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleFile(name),
                          )
                        else
                          menu,
                      ],
                    ),
                    const Spacer(),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '数学绘图',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            : ListTile(
                leading: _selecting
                    ? Checkbox(
                        value: selected,
                        onChanged: (_) => _toggleFile(name),
                      )
                    : icon,
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: const Text('数学绘图'),
                trailing: _selecting ? null : menu,
              ),
      ),
    );
  }

  Future<void> _copyOrRename(String name, bool rename) async {
    var value = rename ? name : '$name 副本';
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(rename ? '重命名绘图' : '复制绘图'),
        content: TextFormField(
          initialValue: value,
          onChanged: (text) => value = text,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, value.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (!mounted || next == null || next.isEmpty || next == name) return;
    setState(() => _busy = true);
    try {
      final original = await widget.documentStorage.load(name);
      if (original == null) throw StateError('绘图不存在');
      await widget.documentStorage.save(
        MathDrawingDocument(
          name: next,
          drawing: original.drawing,
          extensions: original.extensions,
        ),
      );
      if (rename) await widget.documentStorage.delete(name);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作未完成：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final targets = _selectedNames.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除 ${targets.length} 个绘图？'),
        content: const Text('删除后无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '删除',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final name in targets) {
        await widget.documentStorage.delete(name);
        _selectedNames.remove(name);
      }
      if (mounted)
        setState(() {
          _selecting = false;
          _refresh();
        });
    } catch (error) {
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('部分绘图可能未删除：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _drawingList(
    BuildContext context, {
    bool compact = false,
  }) => FutureBuilder<List<String>>(
    future: _names,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        );
      if (snapshot.hasError)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('无法读取绘图列表：${snapshot.error}'),
            TextButton(
              onPressed: () => setState(_refresh),
              child: const Text('重试'),
            ),
          ],
        );
      final names = snapshot.data ?? [];
      if (names.isEmpty) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.draw_outlined, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '还没有保存的绘图',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '创建画布后，保存的作品会出现在这里。',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final name in compact ? names.take(5) : names)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    Icons.functions,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: const Text('数学绘图'),
                onTap: _busy ? null : () => _open(name: name),
                trailing: compact
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: '删除绘图',
                        onPressed: _busy ? null : () => _delete(name),
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            ),
        ],
      );
    },
  );

  Widget _settings(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        '设置',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 24),
      Text('外观', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        child: RadioGroup<ThemeMode>(
          groupValue: _themeMode,
          onChanged: (value) {
            if (value != null) setState(() => _themeMode = value);
          },
          child: Column(
            children: [
              for (final entry in [
                (ThemeMode.system, '跟随系统'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色'),
              ])
                RadioListTile<ThemeMode>(
                  title: Text(entry.$2),
                  value: entry.$1,
                ),
            ],
          ),
        ),
      ),
    ],
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
  const CustomizedWorkspaceExample({
    super.key,
    this.documentStorage = const MathDrawingStorage(),
  });

  final MathDrawingStorage documentStorage;

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
    documentStorage: widget.documentStorage,
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

class _MathSketchPainter extends CustomPainter {
  const _MathSketchPainter({required this.color, required this.is3d});
  final Color color;
  final bool is3d;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final x = size.width * .72, y = size.height * .52;
    if (is3d) {
      final path = Path()
        ..moveTo(x, y - 27)
        ..lineTo(x + 30, y - 12)
        ..lineTo(x + 30, y + 20)
        ..lineTo(x, y + 35)
        ..lineTo(x - 30, y + 20)
        ..lineTo(x - 30, y - 12)
        ..close()
        ..moveTo(x - 30, y - 12)
        ..lineTo(x, y + 4)
        ..lineTo(x + 30, y - 12)
        ..moveTo(x, y + 4)
        ..lineTo(x, y + 35);
      canvas.drawPath(path, p);
    } else {
      canvas.drawLine(Offset(x - 43, y + 18), Offset(x + 43, y + 18), p);
      canvas.drawLine(Offset(x, y - 31), Offset(x, y + 29), p);
      final path = Path()
        ..moveTo(x - 35, y - 27)
        ..quadraticBezierTo(x, y + 62, x + 35, y - 27);
      canvas.drawPath(
        path,
        p
          ..color = color.withValues(alpha: .6)
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MathSketchPainter old) =>
      old.color != color || old.is3d != is3d;
}
