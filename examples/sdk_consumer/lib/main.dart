import 'package:flutter/material.dart';
import 'package:visual_math/visual_math.dart';

void main() => runApp(const ConsumerApp());

class ConsumerApp extends StatelessWidget {
  const ConsumerApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: DisplayDemo());
}

class DisplayDemo extends StatefulWidget {
  const DisplayDemo({super.key});

  @override
  State<DisplayDemo> createState() => _DisplayDemoState();
}

class _DisplayDemoState extends State<DisplayDemo> {
  final _graph = GlobalKey<MathCanvasState>();
  final _scene = GlobalKey<MathCanvas3DState>();
  final _expression = TextEditingController(text: 'sin(x)');
  bool _graphReady = false;
  bool _sceneReady = false;
  int _samples = 0;
  int _sceneChanges = 0;
  String? _error;

  @override
  void dispose() {
    _expression.dispose();
    super.dispose();
  }

  void _loadScene() {
    setState(() => _sceneReady = true);
    _scene.currentState?.setObjects(const [
      Object3D.point(Point3D(1, 2, 3)),
      Object3D.point(Point3D(-1, -2, 1)),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Visual Math consumer'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '2D'),
            Tab(text: '3D'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _KeepAliveTab(
            child: Column(
              children: [
                Text(_graphReady ? '2D ready' : 'Loading 2D'),
                Text('Plot samples: $_samples'),
                if (_error != null) Text(_error!, key: const Key('plot-error')),
                Expanded(
                  child: MathCanvas(
                    key: _graph,
                    initialExpression: 'sin(x)',
                    onReady: () => setState(() => _graphReady = true),
                    onCoordinateUpdate: (points) =>
                        setState(() => _samples = points.length),
                    onError: (message) => setState(() => _error = message),
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _expression)),
                    TextButton(
                      onPressed: _graphReady
                          ? () {
                              setState(() => _error = null);
                              _graph.currentState?.setExpression(
                                _expression.text,
                                null,
                              );
                            }
                          : null,
                      child: const Text('Plot'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _KeepAliveTab(
            child: Column(
              children: [
                Text(_sceneReady ? '3D ready' : 'Loading 3D'),
                Text('Scene changes: $_sceneChanges'),
                Expanded(
                  child: MathCanvas3D(
                    key: _scene,
                    onReady: _loadScene,
                    onSceneChanged: () => setState(() => _sceneChanges++),
                  ),
                ),
                TextButton(
                  onPressed: _sceneReady
                      ? () => _scene.currentState?.setObjects(const [
                          Object3D.point(Point3D(0, 0, 0)),
                        ])
                      : null,
                  child: const Text('Replace scene'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Keep each canvas mounted while the user visits the other tab.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});
  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
