# Human 3D Brain Atlas Integration Notes

Date: 2026-06-08

## Current Baseline

CortiQuiz currently ships the SPL/PNL/NAC Brain Atlas 2017 as per-structure OBJ models plus `atlasStructure.json`. The runtime is built around SwiftUI + SceneKit, with `MDLAsset` loading OBJ meshes and `AtlasLoader` parsing the hierarchy.

That means the easiest new atlas integrations are not necessarily the highest-resolution sources. The best candidates are sources that can be reduced to the same core contract:

- one stable structure id per region
- display name and aliases
- parent/child hierarchy when available
- RGB color
- one or more mesh files per structure
- optional volume/slice data for MRI modes

## Recommended Inclusion Order

### 1. NIH 3D Allen-Derived Human Brain Model

Source: https://3d.nih.gov/entries/20960/1

This should be the first serious candidate. NIH 3D provides a whole-brain 3D model derived from the Allen Human Reference Atlas - 3D, 2020. The source notes say the Allen half-brain was mirrored into a whole human brain, includes 141 anatomical structures, and is licensed CC BY 4.0.

Why include it:

- Human neuroanatomy specific.
- Clearer licensing than many educational 3D brain products.
- Already closer to a 3D app asset than raw NIfTI-only atlases.
- Small enough conceptually to become a polished educational atlas rather than a research-only parcellation.

How to include:

- Download the available 3D assets and inspect file format, polygon count, structure naming, and material separation.
- Split into one mesh per anatomical structure if the source is a combined mesh.
- Normalize structure names to CortiQuiz style.
- Generate `atlasStructure.json` equivalent with Allen ids, names, colors, hierarchy, source URL, license, and attribution.
- Export low/medium/high LODs per structure.
- Prefer `.scn` or `.usdz` for final bundled assets; use OBJ only if conversion introduces problems.

Use this as the next "default human atlas" candidate if the geometry is clean enough after processing.

### 2. Allen Human Reference Atlas - 3D, 2020

Source: https://download.alleninstitute.org/informatics-archive/allen_human_reference_atlas_3d_2020/version_1/README.pdf

The Allen source atlas is the authoritative upstream for the NIH 3D model. It is a 3D parcellation of the adult human brain in ICBM/MNI space, labeling every voxel across 141 structures, and is CC BY 4.0.

Why include it:

- Strong source of truth for structure ids, labels, hierarchy, and anatomical coverage.
- Useful for MRI-style slice modes because the source is voxel-labeled.
- More reproducible than manually curated mesh-only data.

How to include:

- Treat this as the canonical data source even if NIH 3D is used for the initial meshes.
- Convert label volumes into per-structure meshes using marching cubes.
- Preserve voxel-space coordinates and record the transform into the app's SceneKit coordinate system.
- Generate slice-friendly assets: label volume metadata, structure extents, centroids, and axis bounds.
- Use for validating that NIH 3D mesh names and ids still map to the true Allen labels.

Processing path:

```text
Allen label volume
  -> per-label binary mask
  -> marching cubes mesh
  -> mesh cleanup
  -> smoothing/decimation
  -> LOD export
  -> atlas manifest + structure hierarchy
```

### 3. EBRAINS Human Brain Atlas / Julich-Brain / BigBrain

Sources:

- https://ebrains.eu/data-tools-services/brain-atlases/human-brain
- https://ebrains.eu/brain-atlases/apis/
- https://julich-brain-atlas.de/atlas/bigbrain
- https://atlases.ebrains.eu/

EBRAINS is the best research-grade option. It includes the Julich-Brain cytoarchitectonic atlas, BigBrain, siibra-explorer, siibra-python, and an HTTP API. EBRAINS documents BigBrain as a microscopic-resolution human brain model at 20 micrometres in the siibra ecosystem.

Why include it:

- Scientifically richer than the Allen 141-structure atlas.
- Good long-term foundation for advanced anatomy, cytoarchitecture, and multi-scale views.
- Has programmatic access through siibra-python and siibra-api.

Why not first:

- Too large and complex to bundle directly.
- Probabilistic maps and multi-space transforms add significant complexity.
- Better suited for an advanced online/reference mode unless aggressively reduced.

How to include:

- Phase 1: add source links and attribution in a "reference atlas" note section, not as bundled app data.
- Phase 2: use siibra-python/API in preprocessing scripts to extract selected regions only.
- Phase 3: generate a curated "Julich Lite" asset pack for high-value structures, not the full EBRAINS dataset.
- Keep BigBrain as a background/reference template or optional downloadable pack, not a required app-bundle asset.

Good use cases:

- Advanced structure info cards.
- Optional "research atlas" mode.
- Cross-reference names and aliases for cortical areas.
- High-resolution reference renderings outside the main interactive quiz loop.

### 4. FreeSurfer Cortical Atlases: Desikan-Killiany, Destrieux, DKT

Source: https://www.freesurfer.net/fswiki/CorticalParcellation

FreeSurfer provides widely used cortical parcellations, including Desikan-Killiany, Destrieux, and DKT. The documentation notes these labels are stored in `.annot` files after FreeSurfer processing and label the cortical surface into sulci and gyri.

Why include it:

- Excellent for cortex-focused teaching.
- Gives familiar gyral/sulcal names used in neuroimaging and clinical literature.
- Complements the existing atlas, which already emphasizes many named structures.

Limitations:

- Mostly cortical surface labeling, not a full volumetric whole-brain teaching atlas.
- Requires conversion from surface annotation labels into per-region meshes.
- Licensing and redistribution terms should be checked carefully before bundling derived FreeSurfer assets.

How to include:

- Use a standard FreeSurfer subject/template, such as `fsaverage`, as the surface base.
- Read `.annot` files for left/right hemisphere labels.
- Extract one mesh per cortical parcel from the surface.
- Convert parcel meshes to SceneKit coordinates and generate LODs.
- Add as a cortex-specific atlas mode rather than replacing the whole-brain atlas.

Best app feature fit:

- "Cortical Gyri & Sulci" quiz pack.
- Cortex-only explore mode.
- Overlay mode on top of the current full-brain ghost.

### 5. Brainnetome Atlas

Sources:

- https://atlas.brainnetome.org/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC4961028/

Brainnetome contains 246 bilateral subregions and is based on connectional architecture. It is a strong human research atlas with functional and connectivity metadata.

Why include it:

- Detailed human cortical and subcortical parcellation.
- Useful for advanced learners who want function/connectivity context.
- Better anatomical grounding than purely functional network atlases.

Why not first:

- 246 subregions may be too granular for a first-pass anatomy teaching experience.
- Some labels are connectivity-driven and less intuitive than classic anatomy terms.
- Mesh generation and label cleanup would be needed.

How to include:

- Treat as an advanced quiz pack, not the default atlas.
- Convert downloadable MPM/probability maps into per-label meshes.
- Map Brainnetome labels to simpler aliases where possible.
- Add metadata fields for function/connectivity descriptions if redistribution is allowed.

Best app feature fit:

- Advanced neuroanatomy mode.
- Connectivity/function info cards.
- "Name the subregion" quiz after users master the core atlas.

### 6. Harvard-Oxford, Juelich, and Other TemplateFlow/Nilearn Volumetric Atlases

Sources:

- https://www.templateflow.org/
- https://nilearn.github.io/stable/modules/generated/nilearn.datasets.fetch_atlas_harvard_oxford.html

TemplateFlow is a versioned, programmatic resource for neuroimaging templates and atlas labels. Nilearn exposes fetchers for common atlases; its Harvard-Oxford fetcher returns deterministic 3D NIfTI atlas images with 48 regions plus background for deterministic atlases.

Why include it:

- Good for MRI slice labeling and coordinate-space features.
- Standard neuroimaging spaces make it easier to align atlas regions to MRI volumes.
- Useful as validation/reference data.

Why not first:

- Coarser and less visually rich than a dedicated 3D teaching atlas.
- Mostly label volumes, not ready-to-display high-quality meshes.
- Region names are broad and less satisfying for a 3D explore app.

How to include:

- Use primarily for MRI mode and coordinate labeling.
- Generate meshes from labelmaps only for selected broad structures.
- Keep the data pipeline separate from polished 3D anatomy assets.

Best app feature fit:

- MRI slice quiz.
- "What region is this coordinate in?" tool.
- Broad cortical/subcortical region overview.

### 7. HCP-MMP1.0

Source: https://humanconnectome.org/storage/app/media/documentation/s1200/HCP_S1200_Release_Reference_Manual.pdf

The Human Connectome Project multimodal parcellation has 180 cortical areas per hemisphere. It is valuable, but it is more of a research parcellation than a beginner-friendly anatomy atlas.

Why include it:

- High-value for advanced cortical organization.
- Strong relationship to functional, structural, and multimodal neuroimaging literature.

Why not first:

- Cortical only.
- Labels are not always intuitive for anatomy learners.
- Integration is surface/parcellation oriented rather than whole-structure mesh oriented.

How to include:

- Use only after the app supports atlas packs and cortex-only overlays.
- Treat as an optional advanced cortical map.
- Build simplified aliases and groupings to avoid overwhelming users.

## Lower-Priority Educational Viewers

Sources:

- https://neurotorium.org/
- https://www.brainfacts.org/3d-brain

Neurotorium and BrainFacts have polished educational 3D brain experiences. They are useful design references, but they should not be treated as asset sources unless licensing and permission are explicit.

Use them for:

- UI inspiration.
- Educational copy patterns.
- Interaction ideas for isolate/hide/fade/label controls.

Do not assume:

- model redistribution rights
- app embedding rights
- reusable structure metadata

## Asset Processing Pipeline

### Source Intake

For each candidate atlas, create an intake record before processing:

```json
{
  "atlas_id": "allen_human_2020",
  "display_name": "Allen Human Reference Atlas 3D",
  "source_url": "...",
  "license": "CC BY 4.0",
  "citation": "...",
  "coordinate_space": "ICBM/MNI",
  "source_format": "NIfTI/NRRD/OBJ/PLY/etc",
  "structure_count": 141,
  "status": "candidate"
}
```

### Mesh Generation

For volume atlases:

```text
label volume
  -> isolate label id
  -> binary mask
  -> marching cubes
  -> remove tiny components
  -> repair normals
  -> smooth lightly
  -> decimate by LOD target
  -> export
```

For surface atlases:

```text
template surface
  -> read per-vertex labels
  -> split mesh by label
  -> close or leave open boundaries depending on visual quality
  -> smooth boundaries carefully
  -> decimate by LOD target
  -> export
```

### LOD Targets

Use rough targets rather than fixed numbers because structures vary greatly in size.

| LOD | Target | Use |
| --- | --- | --- |
| `low` | 300-1,000 triangles per structure | whole-brain ghost, thumbnails, quiz context |
| `medium` | 2,000-8,000 triangles per structure | normal Explore/Quiz interaction |
| `high` | 15,000-50,000 triangles per selected structure | selected structure, close zoom, screenshots |

Global budget goals:

- Keep initial full-brain low LOD under roughly 300k-500k triangles.
- Keep normal interactive visible geometry under roughly 1M-2M triangles on recent iPhones/iPads.
- Load high LOD only for selected or focused structures.
- Do not parse hundreds of text OBJ files on the main thread.

### Export Format

Preferred final formats:

1. `.scn` for SceneKit-native loading if conversion is reliable.
2. `.usdz` if asset tooling and size are acceptable.
3. `.obj` only as an intermediate or fallback format.

Current app compatibility is OBJ-based, but text OBJ parsing is not ideal for larger atlases. A future `AtlasModelCache` should hide the backing file format so atlas packs can migrate from OBJ to `.scn` or `.usdz` without touching quiz/explore logic.

### Metadata Manifest

Each atlas should ship with an app-specific manifest:

```json
{
  "atlas_id": "allen_human_2020",
  "display_name": "Allen Human Reference Atlas 3D",
  "default_lod": "low",
  "coordinate_system": {
    "source": "RAS/MNI",
    "scene_up_axis": "Z",
    "transform_notes": "Record any flips/scales here"
  },
  "structures": [
    {
      "id": "allen_123",
      "name": "hippocampus",
      "side": "left",
      "aliases": ["left hippocampus", "hippocampal formation"],
      "parent_id": "allen_parent",
      "color": "#DAD814",
      "centroid": [0.0, 0.0, 0.0],
      "bounding_box": {
        "min": [0.0, 0.0, 0.0],
        "max": [0.0, 0.0, 0.0]
      },
      "models": {
        "low": "Models/low/allen_123.scn",
        "medium": "Models/medium/allen_123.scn",
        "high": "Models/high/allen_123.scn"
      },
      "quiz_enabled": true,
      "mri_enabled": true
    }
  ]
}
```

## Runtime Architecture Changes

Before adding multiple atlases, introduce an atlas abstraction instead of hardcoding the current single bundle.

Suggested types:

- `AtlasManifest`
- `AtlasStructure`
- `AtlasAssetProvider`
- `AtlasModelCache`
- `AtlasSelectionState`

Responsibilities:

- `AtlasManifest`: decode atlas-level metadata and structure list.
- `AtlasAssetProvider`: resolve model URLs by atlas id, structure id, and LOD.
- `AtlasModelCache`: lazy-load and clone SceneKit nodes, with per-atlas cache keys.
- `AtlasSelectionState`: active atlas, active quiz pack, active visible LOD.

Runtime loading strategy:

- Load manifest first.
- Load low LOD for context brain.
- Load medium LOD for structures in the active mode.
- Swap in high LOD only when a structure is selected or focused.
- Keep an LRU cache so repeated quiz targets do not reparse/reload.
- Keep all heavy loading off the main actor.

## App Feature Mapping

| Feature | Best atlas |
| --- | --- |
| Default whole-brain 3D quiz | NIH 3D Allen-derived model or Allen Human 2020 |
| MRI slice quiz | Allen Human 2020 label volume, Harvard-Oxford, TemplateFlow |
| Cortex gyri/sulci quiz | FreeSurfer DK/Destrieux/DKT |
| Advanced subregion quiz | Brainnetome |
| Research/cytoarchitecture reference | EBRAINS Julich-Brain / BigBrain |
| Visual/UI inspiration only | Neurotorium, BrainFacts |

## Near-Term Plan

1. Download and inspect the NIH 3D Allen-derived human brain model.
2. Determine whether structures are separable by object/material/group.
3. Convert a small subset first: hippocampus, amygdala, thalamus, caudate, putamen, cerebellum, corpus callosum, ventricles.
4. Generate low/medium/high LODs for that subset.
5. Build an `AtlasManifest` schema compatible with the existing `BrainStructure` model.
6. Add a development-only atlas switcher.
7. Compare load time, memory, triangle count, and visual quality against the current SPL atlas.
8. Only then convert the full 141-structure set.

## Open Questions

- Should future atlases be bundled in the app or offered as optional downloadable packs?
- Should the default app experience stay on the current SPL atlas until the Allen pipeline is fully polished?
- Is the goal classic gross anatomy, neuroimaging-style parcellation, or advanced cytoarchitecture?
- How much App Store bundle size increase is acceptable?
- Should MRI mode switch to true voxel labelmaps for future atlases rather than simulated mesh slices?

## Practical Recommendation

Use the NIH 3D Allen-derived model as the first target and the Allen Human Reference Atlas - 3D, 2020 as the canonical source of truth. Add EBRAINS/Jülich later as an advanced/reference layer. Add FreeSurfer cortical parcellations only after the app supports multiple atlas packs and cortex-only overlays.

