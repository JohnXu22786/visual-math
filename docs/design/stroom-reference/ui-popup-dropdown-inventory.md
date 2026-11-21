# Popup, dropdown, and selection overlay inventory

This is the current production-source inventory for Stroom-owned Flutter UI: `lib/` and the first-party [`packages/streaming_markdown/`](../packages/streaming_markdown/) package. Test fixtures are not counted as app call sites; `tool/` and `integration_test/` were also searched and contain no in-scope production call sites. The external math component is excluded.

## Coverage and counts

Counts below come from tracked Dart files at the documentation baseline (`84f78a72db776809319e890ddbca520004bbf980`). Recount with `git ls-files '*.dart'` and group by first path segment. The menu census searches all production roots for `PopupMenuButton`, `showMenu`, `DropdownButton`, `DropdownMenu`, `MenuAnchor`, `MenuItemButton`, `Autocomplete`, `RawAutocomplete`, and `OverlayEntry`, then manually checks each overlay owner. Test sources were reviewed separately; their widget fixtures are not counted as production screens.

| Tracked Dart source root | Files | Use in this inventory |
|---|---:|---|
| `lib/` | 558 | Application and built-in features |
| `packages/streaming_markdown/` | 87 | First-party Markdown renderer |
| `tests/` | 461 | Test sources, not app call sites |
| `integration_test/` | 1 | Test source |
| `tool/` | 1 | Utility source |
| **Total** | **1108** | **645 production files in guide scope** |

The production census found **27** `PopupMenuButton`, **1** `showMenu`, **33** legacy `DropdownButton` / `DropdownButtonFormField`, and **2** `OverlayEntry` owners. There are no production call sites for `DropdownMenu`, `MenuAnchor`, `MenuItemButton`, `Autocomplete`, or `RawAutocomplete`. The [UI guidelines](ui-guidelines.md) explain component selection, shared styling, and review expectations.

## Shared menu styling

[`StroomMenuStyle`](../lib/widgets/stroom_menu_style.dart) is the shared source for popup and dropdown menu surfaces. It uses `surfaceContainerHigh`, transparent surface tint, 16 dp corners, and a 0.5 dp `outlineVariant` stroke at 35% alpha. The Material 3 `DropdownMenu` theme also specifies 8 dp elevation. Both light and dark app themes apply the shared popup/dropdown styling in [`application.dart`](../lib/application.dart).

Legacy `DropdownButton` and `DropdownButtonFormField` do not inherit a global menu radius, so their call sites set `StroomMenuStyle.surface(context)` and `StroomMenuStyle.borderRadius`. Keep those values aligned when adding a legacy control. Flutter supplies ordinary hover, focus, disabled, and selected states. Preserve destructive-action `error` color and separate destructive actions from routine menu actions when both are present.
Dropdown option labels and their selected display use `ConstrainedText` when they occupy a bounded single-line slot, so a clipped value can reveal its full text without changing selection or focus behavior. See the [constrained display-label rule](ui-guidelines.md#constrained-display-labels).

## Production call sites

Line links below are source locations at this inventory baseline. Refresh them after code changes. A row with several line references represents distinct constructors in the same source file.

### PopupMenuButton

| Screen / component | Source call sites |
|---|---|
| anki page | [`396`](../lib/pages/anki_page.dart#L396) |
| conversations page | [`496`](../lib/pages/conversations_page.dart#L496) |
| ocr page | [`609`](../lib/pages/ocr_page.dart#L609), [`1269`](../lib/pages/ocr_page.dart#L1269) |
| provider config page | [`1372`](../lib/pages/provider_config_page.dart#L1372) |
| task list shared | [`165`](../lib/pages/task_list_shared.dart#L165), [`223`](../lib/pages/task_list_shared.dart#L223), [`271`](../lib/pages/task_list_shared.dart#L271), [`320`](../lib/pages/task_list_shared.dart#L320) |
| synthesis task card | [`213`](../lib/pages/unified_task_list/synthesis_task_card.dart#L213), [`275`](../lib/pages/unified_task_list/synthesis_task_card.dart#L275), [`332`](../lib/pages/unified_task_list/synthesis_task_card.dart#L332), [`385`](../lib/pages/unified_task_list/synthesis_task_card.dart#L385) |
| unified task list page | [`331`](../lib/pages/unified_task_list_page.dart#L331) |
| catcatch policy menu | [`32`](../lib/task_flow/widgets/catcatch_policy_menu.dart#L32) |
| flow block card | [`393`](../lib/task_flow/widgets/flow_block_card.dart#L393) |
| batch rename dialog | [`457`](../lib/widgets/batch_rename_dialog.dart#L457), [`573`](../lib/widgets/batch_rename_dialog.dart#L573), [`710`](../lib/widgets/batch_rename_dialog.dart#L710) |
| batch rename rule editor | [`518`](../lib/widgets/batch_rename_rule_editor.dart#L518) |
| file manager view | [`578`](../lib/widgets/file_manager_view.dart#L578), [`725`](../lib/widgets/file_manager_view.dart#L725), [`1054`](../lib/widgets/file_manager_view.dart#L1054), [`1160`](../lib/widgets/file_manager_view.dart#L1160), [`1259`](../lib/widgets/file_manager_view.dart#L1259), [`1529`](../lib/widgets/file_manager_view.dart#L1529) |
| topic item | [`205`](../lib/widgets/topic_item.dart#L205) |

### showMenu

| Screen / component | Source call sites |
|---|---|
| mermaid chart page | [`312`](../lib/pages/mermaid_chart_page.dart#L312) |

### DropdownButton / DropdownButtonFormField

| Screen / component | Source call sites |
|---|---|
| anki page | [`250`](../lib/pages/anki_page.dart#L250) |
| asr model config page | [`535`](../lib/pages/asr_model_config_page.dart#L535), [`705`](../lib/pages/asr_model_config_page.dart#L705), [`819`](../lib/pages/asr_model_config_page.dart#L819) |
| asr page | [`693`](../lib/pages/asr_page.dart#L693) |
| assistant selection page add custom param | [`59`](../lib/pages/assistant_selection_page_add_custom_param.dart#L59) |
| assistant selection page edit custom param | [`70`](../lib/pages/assistant_selection_page_edit_custom_param.dart#L70) |
| llm model config page reasoning builders | [`431`](../lib/pages/llm_model_config_page_reasoning_builders.dart#L431) |
| llm model config page sections | [`196`](../lib/pages/llm_model_config_page_sections.dart#L196), [`409`](../lib/pages/llm_model_config_page_sections.dart#L409) |
| model config page | [`1183`](../lib/pages/model_config_page.dart#L1183) |
| ocr model config page | [`731`](../lib/pages/ocr_model_config_page.dart#L731) |
| ocr page | [`921`](../lib/pages/ocr_page.dart#L921), [`1070`](../lib/pages/ocr_page.dart#L1070) |
| provider settings panel custom params | [`241`](../lib/pages/provider_settings_panel_custom_params.dart#L241) |
| provider settings panel reasoning | [`632`](../lib/pages/provider_settings_panel_reasoning.dart#L632) |
| provider settings panel tab asr | [`48`](../lib/pages/provider_settings_panel_tab_asr.dart#L48), [`143`](../lib/pages/provider_settings_panel_tab_asr.dart#L143) |
| provider settings panel tab basic | [`56`](../lib/pages/provider_settings_panel_tab_basic.dart#L56), [`212`](../lib/pages/provider_settings_panel_tab_basic.dart#L212), [`357`](../lib/pages/provider_settings_panel_tab_basic.dart#L357), [`458`](../lib/pages/provider_settings_panel_tab_basic.dart#L458) |
| simple model config page | [`276`](../lib/pages/simple_model_config_page.dart#L276) |
| text storage shared | [`123`](../lib/pages/text_storage_shared.dart#L123) |
| tts create page | [`574`](../lib/pages/tts_create_page.dart#L574), [`1045`](../lib/pages/tts_create_page.dart#L1045) |
| voice batch add page | [`354`](../lib/pages/voice_batch_add_page.dart#L354) |
| block chain editor | [`231`](../lib/task_flow/widgets/block_chain_editor.dart#L231) |
| block editor dialog | [`509`](../lib/task_flow/widgets/block_editor_dialog.dart#L509), [`677`](../lib/task_flow/widgets/block_editor_dialog.dart#L677) |
| batch rename dialog | [`691`](../lib/widgets/batch_rename_dialog.dart#L691), [`756`](../lib/widgets/batch_rename_dialog.dart#L756) |
| file manager view | [`2997`](../lib/widgets/file_manager_view.dart#L2997) |

### LabeledTextField suggestions

| Screen / component | Source call sites |
|---|---|
| llm model config shared | [`135`](../lib/pages/llm_model_config_shared.dart#L135) |

### DragSortArea feedback

| Screen / component | Source call sites |
|---|---|
| drag sort area | [`329`](../lib/widgets/drag_sort_area.dart#L329) |

## Reviewed exclusions and boundaries

- [`lib/pages/llm_model_config_shared.dart`](../lib/pages/llm_model_config_shared.dart) owns a suggestion-list `OverlayEntry`; it is selection UI and shares the menu surface/shape treatment.
- [`lib/widgets/drag_sort_area.dart`](../lib/widgets/drag_sort_area.dart) owns an `OverlayEntry` for drag-release feedback, not a menu or selectable list.
- `showDialog` and `showModalBottomSheet` are separate confirmation-dialog, structured-picker, and contextual-sheet families. The [UI guidelines](ui-guidelines.md) describe their usage; these APIs are not included in popup/dropdown counts.
- No `DropdownMenu`, `MenuAnchor`, `MenuItemButton`, `Autocomplete`, or `RawAutocomplete` call sites were found in production roots.
- The first-party Markdown package is included in the tracked source count, but it currently owns none of the listed menu APIs. The external math component/package is excluded from this inventory and all related code changes.
