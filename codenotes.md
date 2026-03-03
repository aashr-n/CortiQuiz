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
| `MRIView.swift` | MRI mode — white matter with fragment shader clipping plane |
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
- **SceneKitView**: Camera/lights now added via `ensureSceneSetup()` on every scene change (was lost on new scenes)
- **All ViewModels**: Added `@MainActor`, switched to `Task.detached` + `weak self` + `nonisolated static` helpers
- **Setup guards**: `setupStarted` flag prevents double-setup race conditions
- **QuizView Performance**: Offloaded heavy 3D model parsing (`AtlasLoader.load`) and target scene assembling (`buildSceneNode`) to `Task.detached` to resolve critical Main thread blocking and UI freezing. Implemented `isLoading` unified indicator. Verified thread safety for `applyTransparency/Color`. Code inspected and passed 3 back-to-back checks.
