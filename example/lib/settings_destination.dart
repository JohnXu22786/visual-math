part of 'main.dart';

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
  bool _checkingForUpdates = false;
  GithubReleaseInfo? _latestRelease;

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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _sectionHeader(theme, isEnglish ? 'General' : '通用'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _settingHeader(
                Icons.palette_outlined,
                isEnglish ? 'Appearance' : '外观',
                isEnglish ? 'Choose a theme' : '选择主题',
                theme,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<ThemeMode>(
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
              ),
              const Divider(height: 1),
              _settingHeader(
                Icons.translate,
                isEnglish ? 'Language' : '语言',
                isEnglish ? 'Select display language' : '选择显示语言',
                theme,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('中文')),
                    ButtonSegment(value: true, label: Text('English')),
                  ],
                  selected: {isEnglish},
                  onSelectionChanged: (selection) =>
                      widget.onLanguageChanged(selection.first),
                ),
              ),
              const Divider(height: 1),
              _settingHeader(
                Icons.functions,
                isEnglish ? 'Math input' : '数学输入',
                isEnglish ? 'Choose the formula editing mode' : '选择公式编辑方式',
                theme,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(isEnglish ? 'Math editor' : '数学编辑器'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(isEnglish ? 'Text input' : '文本输入'),
                    ),
                  ],
                  selected: {widget.mathematicalMode},
                  onSelectionChanged: (selection) =>
                      widget.onMathematicalModeChanged(selection.first),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.code, color: theme.colorScheme.primary),
                title: Text(isEnglish ? 'Developer examples' : '开发者示例'),
                subtitle: Text(
                  isEnglish
                      ? 'Explore the Visual Math components'
                      : '探索 Visual Math 组件',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ExampleMenu()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(theme, isEnglish ? 'About' : '关于'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text('Visual Math', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'v$visualMathVersion',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: _checkingForUpdates
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.system_update_alt,
                        color: theme.colorScheme.primary,
                      ),
                title: Text(isEnglish ? 'Check for updates' : '检查更新'),
                subtitle: Text(
                  _latestRelease != null &&
                          compareVersions(
                                _latestRelease!.version,
                                visualMathVersion,
                              ) >
                              0
                      ? (isEnglish
                            ? 'Version ${_latestRelease!.version} is available'
                            : '发现新版本 ${_latestRelease!.version}')
                      : (isEnglish
                            ? 'Current version v$visualMathVersion'
                            : '当前版本 v$visualMathVersion'),
                ),
                trailing:
                    _latestRelease != null &&
                        compareVersions(
                              _latestRelease!.version,
                              visualMathVersion,
                            ) >
                            0
                    ? _newVersionBadge(isEnglish)
                    : const Icon(Icons.chevron_right),
                onTap: _checkingForUpdates ? null : _checkForUpdates,
              ),
              const Divider(height: 1),
              _aboutLink(
                icon: Icons.link,
                title: isEnglish ? 'Project homepage' : '项目主页',
                subtitle: 'github.com/JohnXu22786/visual-math',
                theme: theme,
                onTap: () => _openUrl(
                  Uri.parse('https://github.com/JohnXu22786/visual-math'),
                ),
              ),
              const Divider(height: 1),
              _aboutLink(
                icon: Icons.bug_report_outlined,
                title: isEnglish ? 'Feedback' : '问题反馈',
                subtitle: isEnglish ? 'GitHub Issues' : '提交问题或建议',
                theme: theme,
                onTap: () => _openUrl(
                  Uri.parse(
                    'https://github.com/JohnXu22786/visual-math/issues',
                  ),
                ),
              ),
              const Divider(height: 1),
              _aboutLink(
                icon: Icons.description_outlined,
                title: isEnglish ? 'Open-source license' : '开源协议',
                subtitle: 'GNU Affero General Public License v3.0',
                theme: theme,
                onTap: () => _openUrl(
                  Uri.parse(
                    'https://github.com/JohnXu22786/visual-math/blob/main/LICENSE',
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.article_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(isEnglish ? 'Third-party licenses' : '第三方许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Visual Math',
                  applicationVersion: visualMathVersion,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _settingHeader(
    IconData icon,
    String title,
    String subtitle,
    ThemeData theme,
  ) => ListTile(
    leading: Icon(icon, color: theme.colorScheme.primary),
    title: Text(title),
    subtitle: Text(subtitle),
  );

  Widget _aboutLink({
    required IconData icon,
    required String title,
    required String subtitle,
    required ThemeData theme,
    required VoidCallback onTap,
  }) => ListTile(
    leading: Icon(icon, color: theme.colorScheme.primary),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.open_in_new, size: 18),
    onTap: onTap,
  );

  Widget _newVersionBadge(bool isEnglish) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      isEnglish ? 'NEW' : '新版本',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onError,
        fontSize: 11,
      ),
    ),
  );

  Future<void> _checkForUpdates() async {
    setState(() => _checkingForUpdates = true);
    try {
      final release = await fetchLatestRelease();
      if (!mounted) return;
      setState(() => _latestRelease = release);
      if (compareVersions(release.version, visualMathVersion) > 0) {
        await _showUpdateDialog(release);
      } else {
        _showMessage(
          widget.isEnglish ? 'You are using the latest version.' : '当前已是最新版本。',
        );
      }
    } catch (error) {
      debugPrint('Visual Math update check failed: $error');
      if (mounted) {
        _showMessage(
          widget.isEnglish
              ? 'Could not check for updates. Please try again later.'
              : '检查更新失败，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  Future<void> _showUpdateDialog(GithubReleaseInfo release) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.isEnglish ? 'Update available' : '发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isEnglish
                    ? 'Visual Math v${release.version} is available.'
                    : 'Visual Math v${release.version} 已发布。',
              ),
              if (release.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(release.notes.trim()),
              ],
              const SizedBox(height: 12),
              Text(
                widget.isEnglish
                    ? 'Open the release page to review the package update.'
                    : '请前往发布页面查看并更新 Visual Math 软件包。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(widget.isEnglish ? 'Later' : '稍后'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openUrl(release.url);
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(widget.isEnglish ? 'View release' : '查看发布'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage(widget.isEnglish ? 'Could not open the link.' : '无法打开链接。');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
