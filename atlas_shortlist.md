# Open 3D Brain Atlas Shortlist

Date: 2026-10-11

Open atlases CortiQuiz could pull from, beyond the one it ships today. For the conversion pipeline (label volume → meshes → LODs → manifest) and the runtime atlas abstraction, see `human_atlas_integration_notes.md`. This file covers which sources to use and what each one adds.

## Baseline: what we already have

**SPL/PNL/NAC Brain Atlas 2017** (Open Anatomy; `brainAtlas2017-01/`). Licensed under the 3D Slicer license (BSD-style, permissive). It has about 393 named structures from a single subject, including thalamic nuclei, hypothalamic subdivisions, the STN, substantia nigra, red nucleus, dentate nucleus, cerebellar lobules and 24 sulci.

**Gaps a second source could fill:**

- No cerebral arteries or venous sinuses.
- No cranial nerves except the optic nerve.
- Only 4 white-matter tracts.
- Cortex is at gyrus level only (no Destrieux-style gyrus and sulcus split).
- Not in MNI space. Everything comes from one person's scan.

## License key

| Tag | Meaning for an App Store app |
| --- | --- |
| **OPEN** | CC BY / CC0 / BSD-style. Ship it with attribution. |
| **SA** | CC BY-SA. Fine to ship, but the derived meshes we ship must also be CC BY-SA. In the usual reading, this covers only those asset files, not the app's code. |
| **NC** | Non-commercial or research-only. Only usable while the app stays free, and some forbid redistribution entirely. Treat as "don't ship". |

All CC 4.0 licenses forbid DRM that restricts recipients' rights, and App Store binaries are DRM'd. The common fix is to also publish the converted assets openly, for example in this repo. This note is not legal advice.

## The shortlist

| # | Atlas | What to pull | Format | License | Effort |
| --- | --- | --- | --- | --- | --- |
| 1 | Brainder "Brain for Blender" | Per-parcel cortical meshes (DK, Destrieux, DKT) and subcortical surfaces | OBJ / PLY | SA (CC BY-SA 3.0) | Low |
| 2 | BodyParts3D (DBCLS) | Arteries, cranial nerves, and an alternate whole-brain mesh set | OBJ + IS-A/PART-OF trees | OPEN (CC BY 4.0) | Low–Med |
| 3 | Allen Human Reference Atlas 3D 2020 + NIH 3D/HRA model | Second full atlas (141 structures) plus a real label volume for MRI modes | NIfTI labels + GLB | OPEN (CC BY 4.0) | Med–High |
| 4 | Z-Anatomy | Cleaner, retopologized versions of the BodyParts3D brain, nerves and vessels | Blender `.blend` | SA (CC BY-SA 4.0) | Med |
| 5 | CerebrA (MNI) | About 100 cortical and subcortical labels on a real MNI T1, for the MRI quiz | NIfTI / MINC | OPEN (CC0), with an upstream caveat | Med |
| 6 | ICBM 2009 MNI152 templates | T1/T2 background volumes for #3, #5 and #7 | NIfTI / MINC | OPEN (MNI BSD-style) | Low |
| 7 | CIT168 subcortical (Pauli 2018) | Small nuclei we lack: habenula, VTA, ventral pallidum, SNc/SNr split | NIfTI (prob + det) | OPEN (CC BY 4.0) | Med |
| 8 | Diedrichsen cerebellar atlas (SUIT) | Fastigial and interposed nuclei. Lobules mostly overlap what we have. | NIfTI | OPEN (CC BY) | Med |
| 9 | Harvard-Oxford (FSL) | Coarse cortical and subcortical labels for an MRI "which region?" quiz | NIfTI | SA (CC BY-SA 4.0) | Low–Med |

### 1. Brainder "Brain for Blender"

- **Adds:**
  - A cortex quiz pack from per-region meshes for Desikan-Killiany, **Destrieux** (gyri and sulci split), and DKT.
  - Pial, white and **inflated** surfaces. Inflated surfaces make sulcal anatomy easy to teach.
  - Subcortical surfaces from FreeSurfer's aseg.
- **Pull:** `pial_Destrieux_obj.tar.bz2`, `inflated_Destrieux_obj.tar.bz2`, `subcortical_obj.tar.bz2`. The files are already one OBJ per region, the closest match to our current `BrainModels/` contract.
- **Watch:**
  - The meshes come uncoloured, so take colours from the parcellation's colour table.
  - It's a single subject (FreeSurfer 5.2), so it won't line up with the SPL brain without registration.
  - Share-alike.
- <https://brainder.org/brain-for-blender>

### 2. BodyParts3D (DBCLS)

- **Adds:**
  - Named arteries (circle of Willis) and cranial nerves. This could be a new "vessels & nerves" category, since the SPL atlas has neither.
  - IS-A and PART-OF trees as TSV, which map almost directly onto `atlasStructure.json`.
- **Pull:** `partof_BP3D_4.0_obj_99.zip` (62 MB) and the element-ID → name tables. Filter by the PART-OF tree under "brain" and the cranial nerve and arterial branches.
- **Watch:**
  - Meshes are 99% polygon-reduced, and release 4.0 dates from 2013.
  - Coordinates are in whole-body space, so recentre them.
  - Brain gyri may be coarser than SPL's.
  - The README text says CC BY 4.0 with a fixed attribution string ("BodyParts3D, © The Database Center for Life Science licensed under CC Attribution 4.0 International"), but it still links an old CC BY-SA 2.1 JP deed. Use the 4.0 terms and keep the exact string.
- <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/download.html>

### 3. Allen Human Reference Atlas 3D 2020 + NIH 3D / HRA model

- **Adds:**
  - A second full atlas with an expert hierarchy (Ding et al.) in MNI space (ICBM 2009b).
  - A voxel label volume, which would let MRI Quiz move from clipped meshes to real slices.
  - CC BY 4.0 since 2022-09-01.
- **Pull:**
  - The annotation volume and ontology from the Allen archive. The ICBM 2009b template has to be downloaded separately (#6).
  - `hra-reference-organ-brain-male-v1.3.glb` from NIH 3D as a ready-made mesh. CC BY 4.0 as of v1.3.
- **Watch:**
  - The whole-brain model is a mirrored half-brain, so left and right are mirror copies.
  - The GLB is scaled to the Visible Human male.
  - Unconfirmed: whether the GLB has one node per structure. Check before planning around it.
  - Already the top recommendation in `human_atlas_integration_notes.md`.
- <https://download.alleninstitute.org/informatics-archive/allen_human_reference_atlas_3d_2020/version_1/> · <https://3d.nih.gov/entries/20960>

### 4. Z-Anatomy

- **Adds:**
  - BodyParts3D with added structures and retopologized (lighter) meshes.
  - Terminologia Anatomica names, which give good canonical quiz labels.
- **Pull:** Script a Blender export of the nervous system and vessel collections to OBJ or USDZ.
- **Watch:**
  - Share-alike.
  - Project activity is uncertain (a 2024 release was announced but I couldn't confirm it shipped).
  - If #2 looks good enough raw, skip this.
- <https://github.com/Z-Anatomy/Models-of-human-anatomy>

### 5. CerebrA (McConnell Brain Imaging Centre)

- **Adds:** Mindboggle-101 labels, hand-corrected onto the symmetric ICBM 2009c template. This gives a clean label volume plus a real T1 for MRI Quiz.
- **Pull:** NIfTI labels and template from the G-Node DOI (10.12751/g-node.be5e62).
- **Watch:** The dataset is CC0, but its labels derive from Mindboggle-101, which NITRC tags CC BY-NC-SA 3.0. Ask the authors before shipping.
- <https://nist.mni.mcgill.ca/cerebra>

### 6. ICBM 2009 MNI152 templates

- **Adds:** The anatomical background for any MNI-space atlas (#3, #5, #7–9).
- **License:** "Use, copy, modify, and distribute … for any purpose and without fee", provided the copyright notice is kept.
- <https://nist.mni.mcgill.ca/icbm-152-nonlinear-atlases-2009/>

### 7. CIT168 subcortical atlas (Pauli, Nili & Tyszka 2018)

- **Adds:** 16 subcortical nuclei. We already have the STN, SN, red nucleus, NAc, GPe/GPi and mammillary bodies. The new ones are the **habenula, VTA, parabrachial pigmented nucleus, ventral pallidum, the SNc/SNr split and the extended amygdala**.
- **Pull:** `CIT168_Reinf_Learn_v1.1.0`, the deterministic map in MNI152 2009c.
- **Watch:**
  - The published dataset is listed as CC BY 4.0, but the bioRxiv preprint was CC BY-NC-ND, so confirm on OSF.
  - The structures are tiny, so meshes need care: threshold the probabilistic map and smooth.
- <https://evendim.caltech.edu/subcortical-atlas>

### 8. Diedrichsen cerebellar atlas (2009)

- **Adds:** The fastigial and interposed deep nuclei. Its 28 lobules overlap the cerebellar pieces we already have, and those are 22% of quiz names already.
- **Pull:** `atl-Anatom` in `_space-MNISym.nii` (ICBM 2009c).
- <https://github.com/DiedrichsenLab/cerebellar_atlases>

### 9. Harvard-Oxford

- **Adds:** 48 cortical and 21 subcortical labels in MNI152, coarse enough for an "identify the region on this MRI slice" beginner quiz.
- **Watch:** The current FSL docs list it as CC BY-SA 4.0. Older FSL docs said non-commercial, so cite the current page. The *other* FSL atlases (Juelich, JHU, thalamus, striatum) remain under FSL's non-commercial license.
- <https://fsl.fmrib.ox.ac.uk/fsl/docs/license.html>

## Look, don't ship

Good references, but their licenses block bundling or are unclear.

| Atlas | Why not |
| --- | --- |
| Julich-Brain / EBRAINS | A registry lists CC BY-NC-SA 4.0. Terms vary per EBRAINS dataset, so check the Knowledge Graph entry. Probabilistic cytoarchitectonic areas suit a "research layer", not the quiz. |
| BigBrain | CC BY-NC-SA 4.0, and the FTP notice says "research purposes only". Surfaces (OBJ/GIfTI/STL, 163,842 vertices per hemisphere) are great for renders, not for bundling. |
| Mindboggle-101 | CC BY-NC-SA 3.0 per NITRC. |
| Brainnetome (246 regions) | Non-commercial and share-alike. Commercial use needs a licence from the Brainnetome Center. |
| HCP-MMP1.0 (Glasser) | HCP Open Access Data Use Terms: registration required, and redistribution only under the same terms. Awkward inside an app bundle. |
| Brainstem Navigator | Non-commercial research only, and **no distribution outside your organization**. Hard no. |
| FSL Juelich / JHU / thalamus / striatum | FSL non-commercial license. |
| DISTAL (Lead-DBS), MASSP, Melbourne Subcortex, Yeh tractography atlas | No clear data license found. The Yeh atlas (80 named white-matter tracts) would fill our tract gap, so it's worth emailing the authors. |
| Mouches & Forkert arterial atlas | Vessel probability map with no named arteries, so it's useless for a naming quiz. BodyParts3D (#2) covers this instead. |

## Suggested order

1. **Brainder Destrieux:** a cortex gyri and sulci pack. Low effort, since the files are already per-region OBJ.
2. **BodyParts3D arteries and cranial nerves:** a new quiz category that fills the biggest content gap.
3. **Allen 2020 + ICBM 2009b:** the second full atlas plus real-voxel MRI modes. This is the large, already-planned item.
