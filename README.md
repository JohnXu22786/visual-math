# visual_math

`visual_math` is a Flutter package for interactive 2D graphing and 3D geometry.
It includes expression models and parsing, formula editing, parameter controls,
a math keyboard, and reusable 2D and 3D canvases. The package's main screen is
`MathDrawingPage`.

Source: <https://github.com/JohnXu22786/visual-math>.

## Install

Add the package to your app's `pubspec.yaml`:

```yaml
dependencies:
  visual_math: ^0.1.0
```

Then resolve dependencies with `flutter pub get`. Import the public library:

```dart
import 'package:visual_math/visual_math.dart';
```

The package declares its MathLive editor and font assets in `pubspec.yaml`.
Flutter bundles them automatically; the consuming app does not need to copy or
redeclare them.

## Use the complete drawing screen

Place `MathDrawingPage` in your app to provide formula editing, plotting, and
the 3D geometry workspace. Its optional `initialExpression` seeds the formula
field.

```dart
import 'package:flutter/material.dart';
import 'package:visual_math/visual_math.dart';

void main() => runApp(const VisualMathApp());

class VisualMathApp extends StatelessWidget {
  const VisualMathApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: MathDrawingPage(initialExpression: 'x^2'),
      );
}
```

Keep a controller in host state to integrate commands and lifecycle events.
The page attaches the controller when mounted; commands are safe to call from
host callbacks after that point, and the snapshot remains null before attach:

```dart
class GraphHostState extends State<GraphHost> {
  late final drawingController = MathDrawingController()
    ..onPlotted = (snapshot) => debugPrint('Plotted ${snapshot.formulas.length}');

  @override
  Widget build(BuildContext context) =>
      MathDrawingPage(controller: drawingController);

  void zoomInFromHostButton() => drawingController.zoomIn();

  MathDrawingSnapshot? get currentSnapshot => drawingController.snapshot;
}
```

The controller can set formulas, view, tool, camera, and viewport after the
page is mounted. It detaches automatically when the page is disposed.

## Embed individual components

`MathCanvas` is a pure-Flutter 2D plot that can be embedded independently. It
accepts an optional initial expression and reports ready, viewport, coordinate,
and error events through callbacks.

```dart
MathCanvas(
  initialExpression: 'sin(x)',
  onError: (message) => debugPrint(message),
)
```

The library also exports `MathCanvas3D`, `MathFormulaField`, `MathKeyboard`,
`MathParameterControls`, `Math3DToolbar`, `MathNumericKeyboard`,
`MathCanvasWebView`, `FormulaEntry`, and the expression and geometry models. These exports form three integration
levels, with different ownership responsibilities.

## Integration levels and ownership

| Level | Public entry points | State and responsibility |
| --- | --- | --- |
| App-owned UI | Exported models: `MathExpression`, `FormulaEntry`, `MathParameter`, `CoordinatePoint`, `Viewport`, `MathInputTemplate`; 3D data types including `Point3D`, `Vector3D`, `Object3D`, `SurfaceMesh`, `Camera3D`, `Projection3D`, `Scene3D`; and `ConstructionState`, `ConstructionTool`, and related enums | The host builds its own UI and owns its application state. Models provide math, scene, and construction data; they do not create a workspace or coordinate widgets. |
| Embeddable components | `MathCanvas`, `MathCanvas3D`, `MathFormulaField`, `MathKeyboard`, `MathParameterControls`, `Math3DToolbar`, `MathNumericKeyboard`, and `MathCanvasWebView` | The host composes the widgets and wires their inputs and callbacks. Stateful widgets manage their interaction state. Stateless controls such as `MathParameterControls` and `MathNumericKeyboard` use host-provided values and callbacks, so the host owns the state passed to them. `MathKeyboard` also stores its category order in shared preferences. |
| Complete workspace | `MathDrawingPage` and optional `MathDrawingController` | The page owns its editor resources and default workspace UI. A controller exposes formulas, parameters, active view/tool, 2D viewport, 3D camera/scene, commands, snapshots, and lifecycle callbacks without replacing the default UI. |

The optional `MathDrawingController` lets a host observe and control the
complete workspace while keeping its built-in UI. Snapshots are immutable,
versioned package objects intended for host save/restore; version 1 keeps typed
formula and scene models and does not define a cross-package interchange
format. The canvases also expose imperative controls on their public
`State` classes, which a host can access with its own `GlobalKey` while the
widget is mounted. For 2D, `MathCanvasState` includes `setFormulas`, `setExpression`,
`setViewport`, `resetView`, `fitToView`, `zoomIn`, and `zoomOut`. For 3D, `MathCanvas3DState` includes scene methods `setObjects`, `setSurface`,
and `clearObjects`; tool methods `setTool` and `performToolCommand`; projection
and visibility methods `setProjectionType`, `toggleAxes`, `toggleGrid`, and
`togglePlane`; and camera methods `resetView`, `fitToView`, `zoomIn`, and
`zoomOut`. A host can use these methods
to connect its own controls to a canvas; the full page's controls remain part
of `MathDrawingPage`.

Choose the model and component level when the host decides which tools or
views to show. For example, an app can include only `MathCanvas` for a 2D-only
experience or only `MathCanvas3D` for a 3D-only experience. These canvases do
not include the formula editor or formula list. `MathFormulaField` requires a
`TextEditingController` and callbacks, so the host owns and disposes a
controller it creates. `MathDrawingPage` creates and disposes its own editing
controllers and other private resources. Do not dispose controllers managed
by a package widget.

### Standalone 2D or 3D

The focused canvases are independent Flutter widgets. They include canvas
interaction, but no formula field, formula list, workspace tabs, or formula
keyboard. Supply your own surrounding UI when you need those pieces:

```dart
Scaffold(
  appBar: AppBar(title: const Text('Graph only')),
  body: const MathCanvas(initialExpression: 'sin(x)'),
)
```

For a 3D-only screen, use `MathCanvas3D()` in the same way. Its canvas
supports the package's built-in pointer interactions; add `Math3DToolbar` or
your own controls when the user needs construction tools. The two examples are
also runnable from the repository's `example/` app.

### Customize the complete workspace

`MathWorkspaceOptions` keeps every existing region enabled by default. It can
also restrict a page to one view, hide package-owned controls, or wrap/replace
individual regions. `MathWorkspacePresentation.labels` changes the built-in
workspace labels. Its optional `translate` callback also receives strings from
canvas and keyboard controls; return the host-language version for labels your
app uses and return the source string for any untranslated label. Flutter
`Theme` controls colors and typography. The app bar can be replaced while
remaining connected to host-owned commands:

```dart
final controller = MathDrawingController();

MathDrawingPage(
  controller: controller,
  options: MathWorkspaceOptions(
    persistence: const MathWorkspacePersistence(
      namespace: 'my_graph_screen',
    ),
    presentation: MathWorkspacePresentation(
      labels: MathWorkspaceLabels(
        pageTitle: 'Studio Math',
        addFormula: 'Add equation',
        view2D: 'Graphs',
        view3D: 'Geometry',
        plotFormula: 'Plot',
        translate: (source) => switch (source) {
          '标准视图' => 'Standard view',
          '平行投影' => 'Parallel projection',
          '透视投影' => 'Perspective projection',
          _ => source,
        },
      ),
      density: MathWorkspaceDensity.compact,
    ),
    appBarBuilder: (context, defaultAppBar) => AppBar(
      title: const Text('Acme • Studio Math'),
      actions: [
        IconButton(
          tooltip: 'Zoom in',
          onPressed: controller.zoomIn,
          icon: const Icon(Icons.zoom_in),
        ),
      ],
    ),
  ),
)
```

For a focused built-in workspace, use `MathWorkspaceOptions(show3D: false)`
or `MathWorkspaceOptions(show2D: false, initialView: ViewMode.mode3D)`. At
least one view must remain enabled, and `initialView` must name an enabled
view. Region builders receive both the default region and
`MathWorkspaceRegionActions`; return the default to retain it, wrap it, or
replace it and call its actions from host controls.

### Host state, preferences, and lifecycle

Keep `MathDrawingController` in the host's `State` when its callbacks, commands,
or snapshots must live across rebuilds. It attaches to one mounted page at a
time, is detached when that page is disposed, and has no separate `dispose`
method. Use `snapshot` after attachment or handle `onPlotted`, `onViewportChanged`,
`onFormulaEdited`, and other callbacks to save host data. A version 1 snapshot
is an immutable in-memory package model, not a promised JSON or cross-version
storage format. Persist data in a host-defined format and map it to supported
models when restoring. Call `restore` before attachment to queue a snapshot, or
after attachment to apply it.

By default, the complete workspace keeps its historical shared-preference
keys. That preserves current input-mode and math-keyboard category-order
behavior. For multiple embedded instances, set a stable distinct
`MathWorkspacePersistence.namespace`; use `enabled: false` when the host owns
preference persistence or wants a non-persistent session. This setting covers
workspace input preferences, not formula/scene snapshots. Optional
`clipboardReader` and `clipboardWriter` let the host provide clipboard access
for keyboard paste/copy/cut commands; leaving them unset retains Flutter's
clipboard behavior. They do not replace the editor's selection handling.

### Migrate imperative `GlobalKey` integrations

Existing code that controls a canvas through a key remains supported while the
canvas is mounted. For example, `MathCanvasState.setViewport` and
`MathCanvas3DState.setCamera` still work with the corresponding `GlobalKey`.
For a complete `MathDrawingPage`, prefer the controller so host code can issue
commands and observe a typed snapshot without reaching into a canvas state:

```dart
// Before: call the key only from a host callback while the canvas is mounted.
final canvasKey = GlobalKey<MathCanvasState>();
MathCanvas(key: canvasKey);
void onLegacyZoomButtonPressed() => canvasKey.currentState?.zoomIn();

// After: retain the controller in host state and pass it to the page.
final controller = MathDrawingController();
MathDrawingPage(controller: controller);
void onZoomButtonPressed() => controller.zoomIn(); // after page attachment
final MathDrawingSnapshot? snapshot = controller.snapshot; // null until attach
```

The controller only covers the complete workspace APIs it documents. Keep a
canvas `GlobalKey` for focused canvas APIs not exposed by that controller, and
check `currentState` because key operations are available only while mounted.
Do not read or dispose private controllers owned by package widgets. Attach one
`MathDrawingController` to only one live `MathDrawingPage` at a time.

The focused widgets are composable pieces. For example, `MathKeyboard` and
`Math3DToolbar` need the host to connect their callbacks to the active editor or
canvas. `MathNumericKeyboard` is the smaller numeric-entry panel; its host
supplies insertion, backspace, caret-movement, and dismiss callbacks. The
complete page provides integrated defaults and also accepts
`MathWorkspaceOptions` to choose views, hide regions, and wrap or replace them.

```dart
MathDrawingPage(
  options: MathWorkspaceOptions(
    show2D: true,
    show3D: false,
    initialView: ViewMode.mode2D,
    showScaffold: false,
    showAppBar: false,
    showFormulaEditor: false,
    canvas2DOverlayBuilder: (context, defaultOverlay, actions) => Stack(
      children: [
        defaultOverlay,
        Positioned(
          left: 12,
          top: 12,
          child: TextButton(
            onPressed: actions.zoomIn2DCanvas,
            child: const Text('Zoom in'),
          ),
        ),
      ],
    ),
  ),
)
```

Both views, the 2D initial view, the formula editor, parameter controls,
keyboard, 3D tools, 2D canvas actions, Scaffold, and AppBar are enabled by
default. A region builder receives the default widget so an app can keep it,
wrap it, or return a replacement. Builders also receive `MathWorkspaceRegionActions`
with page-connected view, formula, parameter, keyboard, tool, and canvas
operations. With `showScaffold: false`, the workspace returns its body for
placement inside a host-owned page.

The public `MathDrawingPage` inputs are `initialExpression` (empty by default),
`initialShowWebView` (true by default), optional `initialMathematicalMode`, and
an optional `MathDrawingController` and `options` (a default
`MathWorkspaceOptions` instance).
Setting `initialShowWebView` to false uses the source editor and preview even on
a platform that supports MathLive; the platform matrix below describes which
platforms can use the embedded editor when it is enabled.

Existing defaults remain the baseline: `MathDrawingPage` starts with one
formula row, opens on the 2D tab, and includes both the 2D and 3D workspaces;
the initial formula is empty unless `initialExpression` is supplied. The 2D
canvas starts with bounds from -10 to 10 on each axis. The 3D canvas starts
with an empty scene and its move tool, parallel projection, visible axes,
plane and labels, and hidden grid. Optional initial values and documented
callbacks or canvas `State` methods are the current host control surface.

`visual_math.dart` is the canonical package import. It exports the model files
for formulas, expressions, parameters, input templates, drawing state, and 3D
geometry, scene, and construction, along with the widgets listed above. Parse
text with `MathExpression.fromInput`; the lower-level parser implementation is
not a separate public export. `dart_math.dart` remains a compatibility export
of the same library. The package does not currently mark
public APIs deprecated; when a public symbol must change, treat that as a
compatibility change and document the replacement and migration in the
changelog. The package is currently pre-1.0, so check release notes when
upgrading for API changes.

`MathCanvasWebView` is a separate JSXGraph-backed canvas with network
requirements described below; it is not the canvas used by
`MathDrawingPage`.

## Platform behavior

The example's release builds passed CI on Linux x64, Web, Android APK, Windows
x64, macOS x64 and ARM64, and unsigned iOS ARM64. These are build results; they
do not claim identical runtime behavior on each target.

| Target | Formula editor in `MathDrawingPage` | Main 2D and 3D canvases |
| --- | --- | --- |
| Android, iOS, macOS, Windows | MathLive editor in the platform WebView | Pure-Flutter canvases |
| Linux, Web, Fuchsia | Built-in formula preview and source editing fallback; no embedded MathLive editor | Pure-Flutter canvases |

`MathFormulaField.supported` reports whether the runtime platform supports the
embedded MathLive editor; it does not guarantee that a specific page is using
it. `initialShowWebView: false` selects the fallback even on a supported
platform. Linux, Web, and Fuchsia use `flutter_math_fork` for formula preview
and source input. That fallback does not provide MathLive's structured editing
interaction. The 2D `MathCanvas` and the 3D canvas are Flutter widgets and do
not depend on WebView.

Hosts can query `MathWorkspaceCapabilities.current` for the current runtime's
MathLive support, source editor fallback, and the network requirement of the
separate JSXGraph WebView canvas. The primary Flutter canvases remain offline.
This capability object describes the current Flutter runtime; it is not a
statement that a host build succeeded or that editor interactions are identical
across targets. Android, iOS, macOS, and Windows use the embedded MathLive
editor when enabled. Web, Linux, and Fuchsia use source editing and preview instead.
`MathWorkspaceOptions.persistence` controls whether input preferences are
stored and accepts a stable namespace for independently embedded workspaces;
the empty namespace preserves the historical keys. Set `enabled: false` for
host-owned, non-persistent sessions. `clipboardReader` and `clipboardWriter`
can take ownership of clipboard access for the built-in keyboard while
preserving editor selection behavior; when omitted, the workspace uses
Flutter's platform clipboard as before. Error presentation is
host-controlled through `MathWorkspacePresentation.errorBuilder`.

Native MathLive support is provided by `flutter_inappwebview`. Use Flutter's
normal platform plugin setup when building the host app. The
`flutter_inappwebview` 6.1.5 documentation lists these platform prerequisites
for that release; the package's `^6.1.5` constraint can resolve later
compatible versions, so check the plugin's current setup guide as needed:

- Android: AndroidX, `minSdkVersion` 19 or later, `compileSdk` 34 or later, and
  Android Gradle Plugin 7.3.0 or later.
- iOS: iOS 12 or later and Xcode 15 or later.
- macOS: macOS 10.14 or later and Xcode 15 or later.
- Windows: NuGet CLI on `PATH` and the Microsoft Edge WebView2 Runtime
  installed on the target machine.

The exact build toolchain may require newer versions. See the
[`flutter_inappwebview` setup guide](https://inappwebview.dev/docs/intro/) for
current host-project setup details.

## MathLive assets and network access

The formula editor loads `editor.html`, JavaScript, styles, and fonts from the
package's bundled `assets/vendor/mathlive/` directory. The font directory is
resolved relative to that local editor page. Normal formula entry and preview
do not fetch MathLive or its fonts from a CDN, so this editor can work offline
after the Flutter app has installed its assets.

The main `MathCanvas` does not make network requests. The separately exported
`MathCanvasWebView` builds a JSXGraph page that fetches its JavaScript and CSS
from `https://cdn.jsdelivr.net`. That widget has no bundled JSXGraph copy or
offline fallback: the CDN must be reachable for its board to render. The
generated page includes inline JavaScript and styles, and the package does not
set a Content Security Policy. If the WebView configuration applies a CSP to
that page, allow `https://cdn.jsdelivr.net` for scripts and styles and permit
the page's inline script and style blocks. If network access is blocked, use
`MathCanvas`, which renders with Flutter instead.

## Standalone example

The repository includes a minimal Flutter host under `example/`. Run it from
the repository root with:

```sh
cd example
flutter pub get
flutter run -d chrome
```

The example uses the package through the local `path: ..` dependency and opens
`MathDrawingPage`. On Web, its formula editor uses the built-in fallback.

## License and attribution

This package is licensed under the GNU Affero General Public License v3.0 only
(`AGPL-3.0-only`). See [LICENSE](LICENSE). The feature is adapted from
[JohnXu22786/Stroom](https://github.com/JohnXu22786/Stroom), available under
the same license. See [NOTICE.md](NOTICE.md) for source revisions and the
history-transfer boundary. Vendored MathLive assets retain their upstream
license files.
