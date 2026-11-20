# Standalone SDK consumer

This Flutter host imports only `package:visual_math/visual_math.dart` and embeds
both Flutter canvases without the full workspace or a v0.2 file format. It
uses a local path dependency, so the package checkout must remain two levels
above this directory. For another app, replace `path: ../..` in `pubspec.yaml`
with the appropriate published or Git dependency and resolve dependencies.

From this directory, with the Flutter and Dart versions required by its
`pubspec.yaml`, run:

```sh
flutter pub get
flutter test
flutter create .  # only if platform runners are needed and absent
flutter run -d <device>
```

In the 2D tab, enter an expression and select **Plot**. The host waits for
`onReady`, uses its `GlobalKey<MathCanvasState>` to call `setExpression`, and
displays the sample count from `onCoordinateUpdate`. `onError` displays parse
errors; an invalid expression leaves the previous plot intact. The next attempt
clears the displayed error. The `setExpression` second argument supplies optional
parameter values; this example passes `null`.

The 3D tab creates two `Object3D` points in `onReady`; **Replace scene** uses
`setObjects` to replace them with one point. `onSceneChanged` reports changes,
including the initial setup. Other callbacks can observe viewport and selection
changes; see the public widget declarations for their signatures. The host owns
its keys, input controller and surrounding UI. State methods require a mounted
canvas: wait for readiness, handle a missing `currentState`, and stop using it
after disposal. The example disposes its text controller when removed.

Both main canvases render with Flutter; the separate WebView canvas and the
full editor have different platform and network requirements. Sampled plots
have finite numerical resolution. See the [SDK contract](../../docs/roadmap/v0.3-sdk-contract.md)
and the [package README](../../README.md) for supported capabilities and platform
requirements. A successful local test is not a claim of runtime validation on
all platforms.
