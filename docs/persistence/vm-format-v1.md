# Visual Math `.vm` drawing format, version 1

A `.vm` document is UTF-8 JSON with `format: "visual-math-drawing"`, integer `version: 1`, a non-empty `name`, and a required `drawing` object. The current writer does not include an application version. Unknown keys under the optional top-level `extensions` object are retained on decode and encode. Unknown required versions, enum values, malformed required fields, and unknown object types are rejected before the page restores state.

The drawing object stores ordered formula rows with stable row IDs, exact editor source text, automatic/custom color selection and ARGB color, visibility, per-row parameter values, shared parameter values and slider ranges, active view and construction tool, 2D viewport bounds, and 3D camera, projection, axes, plane, grid, labels, and scene geometry/style. Scene objects are tagged by their object type. Curves preserve sampled geometry and conic parameters; meshes preserve vertices, indices and normals. Derived plot data is recalculated from formula source when reopened.

Compatibility policy: version 1 readers accept only version 1 required structure. Optional vendor data belongs in `extensions`; writers must not discard it. A future incompatible required schema change increments `version` and requires an explicit migration before restore. A failed decode does not mutate the currently open drawing.

The built-in document store is app-private, uses the platform implementation behind `shared_preferences` (including browser local storage on web), and requires an explicit overwrite choice for duplicate names. The Files action lists documents and opens a selected drawing.

## Current v0.2 model limits

The v0.2 editor does not currently expose formula domain expressions/end-point inclusivity, formula-specific slider ranges, 2D axes/grid/characteristic-point toggles, or source/parent relationships for constructed 3D objects. Its 3D settings that do exist and its formula/shared parameter settings are persisted. 3D dependencies kept only in the canvas's private transient editing maps cannot be reconstructed from the public scene model; those are not claimed as preserved by v1. These limitations are explicit so such state is not silently represented as saved data.
