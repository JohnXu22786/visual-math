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
  String? _error;

  void _loadScene() {
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
          Column(
            children: [
              if (_error != null) Text(_error!),
              Expanded(
                child: MathCanvas(
                  key: _graph,
                  initialExpression: 'sin(x)',
                  onError: (message) => setState(() => _error = message),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  _graph.currentState?.setExpression('x^2', null);
                },
                child: const Text('Plot x²'),
              ),
            ],
          ),
          MathCanvas3D(key: _scene, onReady: _loadScene),
        ],
      ),
    ),
  );
}
