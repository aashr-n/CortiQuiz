# CortiQuiz — To Do

Follow-ups from the 2026-10-04 code review and fixes (details in `codenotes.md` → "Review Fixes").

## Needs you

1. **Run the tests.** The review fixes build cleanly but the tests have never been run (the run was blocked in that session).
   ```bash
   cd CortiQuizSwift
   xcodebuild -scheme CortiQuizSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
   # unit tests only: add -only-testing:CortiQuizSwiftTests
   ```
   - Watch `SliceClassifierTests/triangleMeshMatchesTheBundledOBJ`. MRI Quiz now reads triangles from the loaded SceneKit geometry instead of re-parsing OBJ files; if that test fails, MRI Quiz will show "Couldn't load the brain atlas."
   - The UI tests (one smoke test per mode) have flaked in headless simulators before.

2. **Remove the 107 unused model files (51.7 MB) from the app bundle.**
   ```bash
   cd CortiQuizSwift/CortiQuizSwift/BrainModels
   rm Model_3_*.obj Model_4???_*.obj Model_50??_*_sulcus.obj \
      Model_302[0-3]_*_colliculus.obj Model_303[0-3]_brachia_*_colliculus.obj \
      Model_77_left_optic_nerve.obj
   ```
   - These are the skin and muscle models (filtered out at runtime) plus duplicate copies of the sulci, colliculi and left optic nerve that the atlas never references (it uses the `…1.obj` versions).
   - Afterwards, run `AtlasTests/everyBrainStructureHasABundledModel` to confirm nothing needed was removed.
   - They stay in git history, and `python3 tools/convert_vtk_to_obj.py --all` regenerates every model from the atlas VTK files.

3. **Review and commit.** Nothing from the review fixes is committed.
   - Already staged: untracking `.DS_Store` files and the `xcuserdata` plist, the `OBJMeshParser.swift` → `SliceClassifier.swift` rename, and deleting the UI launch-test template.
   - Everything else is unstaged.
   - `CortiQuizSwift.xcodeproj/xcshareddata/xcodecloud/manifest.json` was created by Xcode during a build. Commit it if you use Xcode Cloud; otherwise ignore it.

## Not done (deliberately)

- **Real MRI volumes for the MRI modes.** The repo already has a label map (`brainAtlas2017-01/volumes/labels/hncma-atlas.nrrd`, 466 KB) and 1 mm T1/T2 scans (`volumes/imaging/A1_grayT1-1mm_resample.nrrd`, 9 MB). Slicing these would give real MRI images with filled regions; today's clipped surface meshes only show each structure's shell. Picking MRI Quiz slices would become a simple voxel count. This is a new feature, not a fix.
- **Convert models to binary `.scn`.** Smaller and faster to load than text OBJ, but it changes the asset pipeline and adds many new binary files. Do it after item 2.
- **Git LFS for `brainAtlas2017-01/` (228 MB).** It only shrinks the repo if history is rewritten and force-pushed.
- **Cerebellar weighting.** Cerebellar lobule pieces are still about 22% of distinct quiz names. If that's too many, down-weight them in `QuizTargetPicker` (`QuizSupport.swift`).

## Other projects

- **Freeway CloudKit setup** (not part of CortiQuiz, which doesn't use CloudKit). Runbook: `~/Documents/freewayApp/CLOUDKIT_RESET.md`
  1. Verify the App IDs and the `iCloud.freewayappContainerOne` container.
  2. Reset the Development environment.
  3. Regenerate the schema from a signed-in device.
  4. Verify sync.
  5. Deploy the schema to Production.
