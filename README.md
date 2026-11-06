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

Keep a controller in host state to integrate commands and lifecycle events:

```dart
final drawingController = MathDrawingController();
drawingController.onPlotted = (snapshot) => saveDraft(snapshot);

MathDrawingPage(controller: drawingController);

// The controller can also set formulas, view, tool, camera, and viewport.
drawingController.setViewport2D(
  const Viewport(xMin: -5, yMin: -4, xMax: 5, yMax: 4),
);
final snapshot = drawingController.snapshot;
```

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
| Linux, Web | Built-in formula preview and source editing fallback; no embedded MathLive editor | Pure-Flutter canvases |

`MathFormulaField.supported` reports whether the embedded MathLive editor is
used. Linux and Web use `flutter_math_fork` for formula preview and source input
instead. That fallback does not provide MathLive's structured editing
interaction. The 2D `MathCanvas` and the 3D canvas are Flutter widgets and do
not depend on WebView.

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
