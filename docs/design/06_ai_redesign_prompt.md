# AI Redesign Prompt

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

Use this prompt when asking an AI coding agent to redesign VisionCraft iPadOS UI.

```md
You are redesigning VisionCraft for iPadOS, an accessibility assistant app. It is the same product as the Android app at /Users/me/Develop/AndroidProject/VisionCraft; Android is the reference.

Before editing, read:

- CLAUDE.md
- docs/design/README.md
- docs/design/00_product_design_brief.md
- docs/design/01_reference_matrix.md
- docs/design/02_accessibility_contract.md
- docs/design/03_design_tokens.md
- docs/design/04_component_specs.md
- docs/design/05_screen_specs.md
- shortcuts_example/DesignSystem/VisionCraftUI.swift
- shortcuts_example/DesignSystem/VisionCraftHomeUI.swift
- the matching Android screen (docs/design/05_screen_specs.md names the Android file for each screen)

Product goal:

VisionCraft should feel like a calm, reliable accessibility tool. It helps users read screens, scan documents, ask AI questions, use DAISY/EPUB books, edit office documents, and launch voice commands. The UI must be easier to scan, less visually clumsy, and more accessible.

Design constraints:

- Use the shared components in `docs/design/04_component_specs.md` (VisionCraftDialogCard, VisionCraftDialogOptionRow, VisionCraftAndroidButtonStyle, VisionCraftScreenTitleRow, VisionCraftSelectionDialog, VisionCraftSettingsGroup, ...) and the tokens in `VisionCraftUI` / `VisionCraftHomeUI`. Do not redraw a style that already exists. Do not use system `.bordered` buttons or system colours (`.red`, `.blue`) in new code.
- Use `visionCraftAndroidText` for text sizes so Dynamic Type and the app font apply; use pt for layout.
- Keep touch targets at least 48pt.
- Text contrast should target 4.5:1 or better; non-text 3:1 or better.
- Do not communicate state by color alone.
- Avoid nested cards and decorative gradients.
- Avoid text under 12pt.
- Keep visual hierarchy strong and quiet.
- Match Android wording exactly (copy from `app/src/main/res/values/strings_*.xml`) and route every user-facing string through `AppLocalization.string`, adding en/ja to `*.lproj/Localizable.strings`.

Implementation style:

- Follow existing SwiftUI patterns; UIKit only where the screen already is UIKit (camera).
- Keep changes scoped to the requested screen.
- Preserve VoiceOver labels and improve them when needed.
- Verify with `xcodebuild -workspace shortcuts_example.xcworkspace -scheme shortcuts_example -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` (no simulator; run on the iPad for behaviour).
- Design docs describe only the current app. After changing UI, update the affected doc and its `점검일 · 기준 코드` line and the table in `docs/design/README.md`.

If redesigning Home:

- There are two layouts (list and 2x2 category tiles) sharing one item list in `HomeView.swift`; change both.
- Keep the title row icons (remote status, 전체 설정) and the guide card at the top.

If redesigning widgets:

- Widgets live in `rivoWidget/`. Keep labels 12pt or larger and read state in the accessibility label.

If redesigning voice/audio feedback:

- Separate sound effects from voice/TTS guidance.
- Failure must include text or TTS reason, not sound only.
- Respect the 효과음 피드백 and 음성 피드백 settings.

Do not copy Mobbin/Page Flows visuals directly. Extract layout intent, hierarchy, spacing, state handling, and flow patterns only.
```
