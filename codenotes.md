# CortiQuiz — Code Notes

## Project State: ✅ Builds successfully (iOS Simulator, iPhone 17 Pro)

## Architecture
- **SwiftUI + SceneKit** — pure Apple frameworks, no SPM deps
- **@MainActor @Observable** view models for each mode
- **MDLAsset** loads OBJ models via `SceneKit.ModelIO` bridge
- **ModelCache** singleton caches loaded SCNNodes to avoid repeated disk reads
- **Task.detached** for background model loading, `await MainActor.run` to commit state

## Files
| File | Purpose |
|------|---------|
| `BrainStructure.swift` | JSON decoding (`AtlasEntry`) + domain model (`BrainStructure`) |
| `AtlasLoader.swift` | Parses `atlasStructure.json`, builds hierarchy, `ModelCache` for OBJ loading |
| `SceneKitView.swift` | `UIViewRepresentable` wrapping `SCNView` — camera/lights via `ensureSceneSetup` |
| `MainMenuView.swift` | 3-mode menu with dark gradient design |
| `QuizView.swift` | Quiz mode — random structure quiz with ghost brain overlay |
| `ExploreView.swift` | Explore mode — all structures, search, tap-select, explode slider |
| `MRIView.swift` | MRI mode — 2D slice rendering with 4-color palette + mini-brain |
| `MRIQuizView.swift` | MRI quiz — identify structures from 2D MRI slices |
| `ContentView.swift` | Entry point → `MainMenuView` |

## Data
- 359 OBJ models in `BrainModels/` (converted from VTK)
- `atlasStructure.json` in bundle root
- Non-brain structures (muscles, skin: Model_4xxx, Model_3_skin) filtered at runtime via `isBrainStructure`
- All models shipped in bundle for future "all structures" mode

## Known Considerations
- Bundle size is ~120MB due to 359 OBJ models
- SCNSceneSource does NOT load .obj — using MDLAsset + SceneKit.ModelIO bridge
- iOS deployment target is 26.2 (Xcode 26.3 beta)
- Quiz L/R merging strips prefixes from names for answer matching
- Explode view: factor 0 = collapsed to origin (by design — offset-based), factor > 0 spreads outward

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

