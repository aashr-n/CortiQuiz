# CortiQuiz — Code Notes

## Project State: ✅ Builds successfully (iOS Simulator, iPhone 17, iOS 26.5)

## Architecture
- **SwiftUI + SceneKit** — pure Apple frameworks, no SPM deps
- **@MainActor @Observable** view models for each mode
- **MDLAsset** loads OBJ models via `SceneKit.ModelIO` bridge
- **ModelCache** singleton caches loaded SCNNodes to avoid repeated disk reads
- **Task.detached** for background model loading, `await MainActor.run` to commit state

## Files
| File | Purpose |
|------|---------|
| `BrainStructure.swift` | JSON decoding (`AtlasEntry`) + domain model (`BrainStructure`, `baseName` for L/R pairing) |
| `AtlasLoader.swift` | Parses `atlasStructure.json` once (lazy static), builds hierarchy; `ModelCache` loads + deep-clones OBJ nodes on a serial queue |
| `BrainSceneLoader.swift` | Shared "brain-only structures → cloned nodes → bounds/centers" scene build used by every mode; honors task cancellation |
| `SceneUtilities.swift` | `Background.run` (`@concurrent` off-main work), `restyleNodes`, `ExplodeLayout`, clip-shader `SCNNode` helpers |
| `Theme.swift` | Design tokens (SwiftUI) + `SceneColors` (SceneKit material colors, nonisolated), haptics, `PressableStyle`, `Color.fromRGB` |
| `SharedViews.swift` | `LoadingStateView`, `ExplodeSlider`, `RecenterButton`, `SceneControlsBar`, `.bottomCard()` |
| `QuizSupport.swift` | `QuizOptionBuilder` (distractors), `QuizTargetPicker` (flagged → weak → unasked, by baseName), `QuizSession`, `AnswerOptionsView`, `ScoreLabel`, `QuizResultsView` |
| `ProgressStore.swift` | Persistent stats, best session streak, Learn-mode review queue (UserDefaults JSON; injectable defaults for tests) |
| `MRISlicing.swift` | `MRIAxis`, slice camera/clip/plane geometry + shared constants, `SliceRenderer` (snapshots on a private queue) |
| `SliceClassifier.swift` | Reads triangles from loaded SceneKit geometry, scores slice visibility for MRI Quiz, caches results per session |
| `MiniBrainBuilder.swift` | Gray translucent mini-brain scene + slice plane for the MRI modes |
| `SceneKitView.swift` | `UIViewRepresentable` wrapping `SCNView` — camera/lights via `ensureSceneSetup`, tap → all hits |
| `MainMenuView.swift` | `AppMode` enum + menu; destinations built lazily via `navigationDestination` |
| `LearnView.swift` / `QuizView.swift` / `ExploreView.swift` / `MRIView.swift` / `MRIQuizView.swift` | The five modes. Each view model loads in `load() async`, started by `.task` (cancelled on disappear) |
| `CortiQuizSwiftApp.swift` | Entry point → `MainMenuView` |
| `../tools/convert_vtk_to_obj.py` | Regenerates `BrainModels/*.obj` from `brainAtlas2017-01/models/*.vtk` (byte-identical to the shipped files) |

## Data
- OBJ models in `BrainModels/`, converted from the atlas VTK triangle strips by `tools/convert_vtk_to_obj.py`
- `atlasStructure.json` in bundle root
- Only the 255 brain structures (252 files, including the 22 sulci) are used; muscles/skin (Model_4xxx, Model_3_skin) are filtered by `isBrainStructure`. The non-`1` copies of the sulci, colliculi and left optic nerve aren't referenced by the atlas JSON (it uses the `…1.obj` versions). See `todo.md` for removing the unused files.

## Known Considerations
- SCNSceneSource does NOT load .obj — using MDLAsset + SceneKit.ModelIO bridge
- iOS deployment target is 26.2; Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency
- Quiz L/R merging strips prefixes from names for answer matching
- Explode view: factor 0 is the natural layout (vertices are world-space; node positions are offsets)
- SceneKit `orthographicScale` is half the visible height: the slice camera shows 180 mm across 512 px (`MRISlicing.pixelsPerUnit`)
- iPhone is portrait-only; the app forces dark appearance (`UIUserInterfaceStyle = Dark`)

## Bug Fixes Applied (2026-03-03)
- **Model Loading Fix**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` made `AtlasLoader`, `ModelCache`, `AtlasEntry`, `BrainStructure`, and `Color.fromRGB` implicitly `@MainActor` — they couldn't be called from `Task.detached`. Fixed by adding explicit `nonisolated` to all data/utility types. `ModelCache` also marked `@unchecked Sendable` (uses internal `DispatchQueue` for thread safety).
- **SceneKitView**: Camera/lights now added via `ensureSceneSetup()` on every scene change (was lost on new scenes)
- **All ViewModels**: Added `@MainActor`, switched to `Task.detached` + `weak self` + `nonisolated static` helpers
- **Setup guards**: `setupStarted` flag prevents double-setup race conditions
- **QuizView Performance**: Offloaded heavy 3D model parsing (`AtlasLoader.load`) and target scene assembling (`buildSceneNode`) to `Task.detached` to resolve critical Main thread blocking and UI freezing. Implemented `isLoading` unified indicator. Verified thread safety for `applyTransparency/Color`. Code inspected and passed 3 back-to-back checks.
- **OBJ Asset Reconversion (2026-03-03)**: All 359 OBJ files had 0 face definitions (only vertex data) — previous VTK→OBJ conversion was broken. Reconverted using Python VTK lib with custom writer (simple `f v1 v2 v3` format for MDLAsset compatibility). Every file now has proper vertex + face data. No Swift code changes needed for loading.
- **Concurrency Fix (2026-03-03)**: Added `[weak self]` capture lists to all `MainActor.run` closures in `ExploreView`, `MRIView`, `QuizView`. Captured mutable local vars (`nodes`, `positions`, `globalMinY`, `globalMaxY`) into `let` constants before `MainActor.run` boundary.
- **Bundle Path Fix (2026-03-03)**: `ModelCache.node(for:)` used `subdirectory: "BrainModels"` but `PBXFileSystemSynchronizedRootGroup` copies OBJ files to bundle root (no subdirectory). Removed `subdirectory` param — was the actual cause of invisible models (Bundle.main.url always returned nil).
- **Deep Clone Fix (2026-03-05)**: `SCNNode.clone()` shares geometry/materials. MRI mode's `applyShader` was permanently corrupting cached geometry for all subsequent clones (causing Quiz mode to show only a slice after visiting MRI). Fixed `ModelCache.deepClone()` to copy geometry + materials recursively.
- **Brain Orientation Fix (2026-03-05)**: VTK models use RAS coordinates (Y=anterior/posterior, Z=superior/inferior). Camera repositioned from `(0,0,300)` to `(0,-300,10)` looking along +Y with Z as up vector. Brain now renders right-side-up in all modes.
- **Pan/Recenter (2026-03-05)**: Added `orbitTurntable` interaction mode for two-finger pan in Quiz/Explore. Added `recenterTrigger` toggle + scope button overlay to re-center camera with animation.
- **MRI 2D Rendering (2026-03-05)**: Replaced 3D thin-slice view with orthographic `SCNRenderer` snapshots. Camera looks from superior (+Z) down for axial cross-sections. Fragment shader clips along Z axis (superior-inferior). Renders to 512×512 `UIImage` displayed as a 2D MRI-style slice.
- **Reset on Disappear (2026-03-05)**: Added `resetForReentry()` + `.onDisappear` to all view models so scenes reinitialize with fresh deep-cloned nodes when navigating back from other modes.
- **Rotation Fix (2026-03-05)**: Set `defaultCameraController.worldUp = SCNVector3(0, 0, 1)` to match RAS Z-up orientation. Fixes inverted-feeling rotation gestures.
- **Quiz Filter Fix (2026-03-05)**: Quiz now uses same filter as Explore mode (`isBrainStructure && !isGroup`) — only asks about structures visible to the user. Removed keyword-based `isCorticalStructure` approach.
- **MRI White/Gray Matter (2026-03-05)**: Added `isWhiteMatter` property to `BrainStructure` (checks filename for `white_matter`). MRI renders white matter at brightness 0.95, gray matter at 0.60, with color legend. Loads ALL brain structures for dense filled cross-sections.
- **Rotation Fix (2026-03-06)**: Replaced `orbitTurntable` with `orbitArcball` in `SceneKitView` for free-form 3D rotation, resolving unnatural constraints when viewing the RAS-oriented brain.
- **MRI 4-Color Theorem (2026-03-06)**: Removed fragile `isWhiteMatter` logic. MRI mode now assigns 4 distinct anatomical colors (cream, blue, rose, sage) deterministically by structure index.
- **MRI Black Screen Fix (2026-03-06)**: Fixed bug where MRI showed a black screen because `_surface.position.z` in SceneKit's fragment shader is view-space, not world-space. Subtracted camera's Z position (`300`) from the world-space `clipZ` to compare accurately against view-space fragments.
- **Navigation Fix (2026-03-14)**: Switched `SceneKitView` from `orbitArcball` to `orbitAngleMapping` to prevent inverse/gimbal-flip spinning. Elevated default camera to `(0,-300,40)` for a more natural anterior-elevated view instead of dead-on horizontal.
- **MRI 4-Color Palette (2026-03-14)**: Updated 4-color palette to warm sand `(0.92,0.82,0.62)`, slate blue `(0.45,0.58,0.78)`, dusty mauve `(0.76,0.52,0.62)`, eucalyptus `(0.48,0.72,0.58)` — better contrast and medical-imaging aesthetic.
- **MRI Slice-Only Coloring (2026-03-14)**: 4-color scheme now applied only to the `SCNRenderer` scene used for 2D slice snapshots. The mini-brain uses original atlas colors at 35% opacity.
- **MRI Mini-Brain (2026-03-14)**: Added `MiniBrainView` (140×140pt) in MRI mode's bottom-left corner. Shows translucent brain with atlas colors + `SCNPlane` slice indicator tracking slider position. Self-contained `UIViewRepresentable` with `orbitAngleMapping`, independently spinnable.
- **MRI Quiz Mode (2026-03-14)**: New `MRIQuizView.swift` — picks random structure, slices at its Z range, highlights target in cyan `(0.1,0.95,0.85)`, renders 2D snapshot. 4 multiple-choice answers with score tracking. Added as 4th card in `MainMenuView`.
- **Atlas Colors in MRI Modes (2026-03-14)**: Removed 4-color theory palette from both `MRIView` and `MRIQuizView`. Both now use `UIColor(s.color)` (original brain atlas colors) for 2D slice rendering.
- **MRI Quiz Pulsing Highlight (2026-03-14)**: Target region in MRI quiz renders two snapshots (bright white at peak, dim teal at trough) and SwiftUI `.opacity` animation pulses between them at 0.8s ease-in-out. Replaces static cyan highlight.
- **Monochrome Main Menu (2026-03-14)**: Background changed to pure black gradient `(0a0a0a→151515)`. Title is solid white (no purple gradient). All mode card icon backgrounds use gray `(404040→2a2a2a)`.
- **Mini-Brain in MRI Quiz (2026-03-14)**: Added single-color gray mini-brain (120×120pt) with slice plane indicator to `MRIQuizView`. Uses shared `MiniBrainView` (made internal from private in `MRIView.swift`). All nodes rendered in `UIColor(white: 0.7, alpha: 0.35)`.
- **Unified Gray Mini-Brain (2026-03-14)**: MRI explore mode mini-brain changed from atlas colors to single gray `UIColor(white: 0.7, alpha: 0.35)` — now matches MRI quiz mini-brain.
- **Stronger MRI Quiz Pulse (2026-03-14)**: Pulse highlight changed from subtle teal/white to full white→black cycle for maximum contrast. Dot indicator now matches target region's atlas color.
- **Wrong Answer Flash (2026-03-14)**: Incorrect MRI quiz answers flash red→white 3 times via `repeatCount(3)` animation on background color.
- **Lateral Camera View (2026-03-14)**: Default camera moved from anterior `(0,-300,40)` to left-lateral `(300,0,40)` for side profile view of brain. FOV widened from 40° to 55° so entire brain visible without zooming. `recenterCamera` and `focusOn` updated to match lateral orientation.
- **MRI Layout (2026-03-14)**: MRI explore mode changed from `ZStack` overlay to `HStack` — mini-brain (100×100pt) sits beside the MRI slice instead of blocking it.
- **MRI Quiz Dimmed Regions (2026-03-14)**: Non-target regions rendered at 20% brightness / 40% alpha for muted appearance. Target continues pulsing white↔black.
- **MRI Quiz Flash Removed (2026-03-14)**: Removed `wrongFlash` state and `triggerWrongFlash()` animation. Wrong answers show static red background with ✕ icon.
- **MRI Quiz Mini-Brain Feedback (2026-03-14)**: After answering, correct region turns green `(0.2,0.9,0.3)` and wrong pick turns red `(0.9,0.2,0.2)` on mini-brain. Mini-brain nodes now named by structure ID. Reset to gray on next question.

## De-Vibecoding Refactor (2026-05-21)
- **Design System (`Theme.swift`)**: Centralized all colors, typography, and haptics. Monochrome palette (near-black backgrounds, white text) with dusty brain-pink accent `#D4829A`. New York serif (`.design(.serif)`) for headings — gives academic/medical feel without custom fonts. Eliminated all Tailwind CSS hex colors (`fbbf24`, `8b5cf6`, `06b6d4`, `10b981`).
- **Shared `SCNNode` Extensions (`SceneUtilities.swift`)**: Consolidated 4 duplicated `applyColor`/`applyMaterial`/`applyTransparency` implementations into single `SCNNode` extensions. Added uniform-based MRI clip shader (`installClipShader` + `updateClipUniforms`) to eliminate shader recompilation on every slider drag.
- **OBJ Mesh Parser Extraction (`OBJMeshParser.swift`)**: Moved ~200 lines of raw OBJ parsing, slice footprint calculation, and quiz target classification out of `MRIQuizView.swift`. Renamed `MRIQuiz`-prefixed structs to clean names (`OBJVertex`, `SliceFootprint`, `TargetCandidate`, etc.).
- **Mini-Brain Builder (`MiniBrainBuilder.swift`)**: Extracted ~40 lines of duplicated mini-brain scene setup (camera, lights, slice plane, gray material) shared between `MRIView` and `MRIQuizView`.
- **Atlas Caching**: `AtlasLoader` changed from `class` to `enum`, added `DispatchQueue`-guarded cache. 379KB JSON now parsed once per app session instead of 4 times.
- **MainMenuView Redesign**: Data-driven mode cards with staggered spring animations (`0.08s` delay per card). `PressableStyle` button style for tactile press feedback. `appear` resets on disappear for animation replay. Icons tinted with `Theme.accent`.
- **Haptic Feedback**: Added `UIImpactFeedbackGenerator(.light)` on all taps, `UINotificationFeedbackGenerator` `.success`/`.error` on quiz answers across all modes.
- **SCNTransaction Animation**: Explore mode selection/deselection now animated with 0.25s `SCNTransaction` instead of instant color snap.
- **Dead Code Removal**: Deleted `isCorticalStructure` (superseded), `focusOn(node:)` (never called), `smallRegionStudyList` (never displayed), `ContentView.swift` (vestigial indirection). All archived to scratch/.
- **MRIQuizView Slimmed**: 698 → 330 lines. All parsing, classification, and material helpers extracted to shared files.
- **Build**: Clean build, 0 errors, 0 warnings (iPhone 17 Pro Simulator, iOS 26.2).

## App Icon & App Store Connect Fixes (2026-05-21)
- **Master Icon Art**: Generated a premium, full-bleed 1024x1024 master app icon with a detailed glowing pink 3D brain model on a deep dark gradient. Natively converted to strict PNG format using macOS `sips`.
- **Scaling & Formats**: Generated all 18 standard iOS app icon sizes using native `sips` resizing to resolve missing `120x120` (iPhone) and `152x152` (iPad) icon issues on App Store Connect.
- **Asset Catalog (`Contents.json`)**: Configured the complete set of assets across all idioms and scales.
- **Verification**: Ran `xcodebuild` clean/build successfully. Verified that `CFBundleIconName` => `AppIcon` is correctly synthesized in the compiled app bundle `Info.plist` and correct icon asset resources are embedded.

## View Orientation & Perspective Fixes (2026-05-21)
- **Fisheye Distortion Fix**: Reduced `SceneKitView` camera `fieldOfView` from 55 to 30. A wide FOV of 55 caused significant edge stretching (fisheye effect) when objects moved outward radially from the center during the "Explode" interaction in `ExploreView`.
- **Default Camera Angle**: Moved default camera position from a flat left-lateral profile `(300, 0, 40)` to a natural anterior-oblique view `(200, 400, 150)`. This looks at the brain from the front-right-top, making the 3D structures instantly recognizable rather than "pointed in weird ways." Up vector remains Z `(0, 0, 1)`.

## MRI Multi-Axis Support (2026-05-21)
- **Coronal & Sagittal Views**: Upgraded `MRIView.swift` to support three dimensions: Axial (Z), Coronal (Y), and Sagittal (X). A new segmented `Picker` lets users select the desired slicing axis. The 2D slice image seamlessly updates.
- **View-Space Clipping Architecture**: The MRI fragment shader was verified to work universally for all axes without modification. By altering the `SCNRenderer` camera's position to face the origin along the active axis, `_surface.position.z` natively maps to depth along that axis.
- **Dynamic Mini-Brain Updates**: `MiniBrainBuilder.swift` now calculates and returns multi-axis 3D bounds. In `MRIView`, the semi-transparent pink `slicePlaneNode` dynamically reorients (`eulerAngles`) and positions itself to visualize the current cutting plane relative to the full brain volume.

## Swift 6 Concurrency & Actor Isolation Fixes (2026-05-21)
- **Nested Structs Actor Isolation**: Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, nested structs in a type inherit the type's default actor isolation. `MiniBrainBuilder.Bounds` and `MiniBrainBuilder.Result` were implicitly isolated to `@MainActor`, preventing their initializers and properties (like `maxExtent`) from being accessed from nonisolated concurrent contexts (e.g. `Task.detached` blocks in both `MRIViewModel` and `MRIQuizViewModel`).
- **Nonisolated Struct Refactor**: Defined `MiniBrainBounds` and `MiniBrainResult` as root-level `nonisolated` structs. Exposed them as typealiases (`Bounds` and `Result`) inside `MiniBrainBuilder` to preserve backwards compatibility without modifying any reference sites.
- **Verification**: Ran clean compilation and successfully passed 3 subsequent build checks.

## Environment Verification & Build Instructions (2026-06-03)
- **Xcode Select Path**: `/Applications/Xcode.app/Contents/Developer`
- **SDK & Runtime**: iOS 26.5 Simulator Runtime (`com.apple.CoreSimulator.SimRuntime.iOS-26-5`)
- **Preferred Simulator**: iPhone 17 (`46BD4F72-B5C6-4096-885B-6FD11E2E769B`)
- **Main App Scheme**: `CortiQuizSwift`
- **Build Command**:
  ```bash
  xcodebuild -project CortiQuizSwift/CortiQuizSwift.xcodeproj -scheme CortiQuizSwift -destination 'id=46BD4F72-B5C6-4096-885B-6FD11E2E769B' clean build
  ```
- **Install Command**:
  ```bash
  xcrun simctl install booted "/Users/aashray/Library/Developer/Xcode/DerivedData/CortiQuizSwift-gougtpmeqwafiofiwgvkhxnadmkk/Build/Products/Debug-iphonesimulator/CortiQuizSwift.app"
  ```
- **Launch Command**:
  ```bash
  xcrun simctl launch booted com.aashray.CortiQuizSwift
  ```
- **Smoke Test Verification**: Successfully completed clean build, installed app to booted simulator, and launched with process ID.

## 3D Quiz Enhancements (2026-06-03)
- **Full Brain Visualization**: Modified `QuizViewModel` to load the full brain (all `brainOnly` structures) during setup instead of loading a sparse subset of structures.
- **Dynamic Node State Highlights**: Added `updateNodeStates()` using `SCNNode.opacity`. Target region is colored cyan and set to `1.0` opacity before answering, with all other structures at `0.15` opacity. After answer submission, the correct structure highlights green (`Theme.correct`), and any incorrectly selected structure highlights red (`Theme.incorrect`).
- **Explode Slider Integration**: Added an explode slider (`explodeFactor` bounding to 3D node translations outward from the calculated brain center) in the quiz view overlay, resetting to `0` on each new question.

## Review Fixes (2026-10-04)
- **MRI Quiz visibility math**: slice footprints used 512/90 px per mm, but the camera shows 180 mm across, so sizes were 2× (areas 4×) too large and ~12 px targets passed a "24 px" rule. Now `MRISlicing.pixelsPerUnit` (512/180), with thresholds of 14 px / 80 px² (≈10 pt on screen): 249 of 252 structures stay quizzable.
- **MRI Quiz loading**: triangles are read from the already-loaded SceneKit geometry instead of re-parsing every OBJ, and classification results (not meshes) are cached for the session.
- **Off-main rendering**: `SliceRenderer` snapshots on a private queue; MRI Mode drops superseded slider frames, MRI Quiz swaps slice + answers in together.
- **Quiz targets**: picked per baseName (pairs no longer 2× as likely), no repeats within a session, Learn-mode "Study again" cards first, weak spots mixed in. Results show the session's best streak; lifetime best streak = best single session.
- **Loading**: `.task { await vm.load() }` replaces `Task.detached` + `setupStarted`/`resetForReentry`; leaving a mode mid-load cancels it.
- **Misc**: single haptic per answer, Reduce Motion respected (MRI pulse, menu), load-failure message instead of an endless spinner, MRI wrong answers mark both hemispheres, Explore taps prefer the opaque (selected) structure, iPhone portrait-only, forced dark mode, dead code removed, shared UI components extracted.
- **Tests**: unit tests for atlas filtering, option builder, target picker, session, progress persistence (incl. legacy blobs), explode layout, slice scale (rendered), footprint math, and mesh extraction; UI smoke tests for every mode.
