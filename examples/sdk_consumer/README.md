# Standalone SDK consumer

This Flutter host uses only the public `visual_math` import and embeds the 2D
and 3D canvases without the package's workspace. From this directory run
`flutter pub get`, `flutter test`, and `flutter run -d <device>`. Generate
platform runners with `flutter create .` if your checkout has none. The path
dependency points to the repository root; a separate application can replace
it with its chosen published or Git dependency. The host initializes 3D objects
on readiness and updates the 2D expression using its mounted canvas key.
