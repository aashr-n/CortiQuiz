Brain Anatomy Game
A study tool built to help users memorize the anatomy of the human brain through interactive 3D exploration and quizzing. It's powered by the SPL/PNL/NAC Brain Atlas (2017), an open-source dataset containing hundreds of individually labeled brain structures as 3D models, along with MRI volume data.

Main Menu
The app opens to a simple menu with four game modes: Normal Mode, Explore Mode, MRI Mode, and MRI Quiz. The menu also shows lifetime study stats (questions answered, accuracy, best streak) once you've played.

Normal Mode — 3D Quiz
The core study mode. The app picks a random brain structure, renders it highlighted in red within a transparent ghost of the full brain (so you can see where it sits anatomically), and asks you to identify it from four multiple-choice options.

The 3D view is fully interactive — you can rotate, zoom, and pan around the brain.
The camera auto-centers on the target structure each round.
Left/right hemisphere equivalents are treated as the same answer (e.g., picking "left putamen" when the answer is "right putamen" still counts).
Options that have both left and right versions are merged into a single choice (e.g., "putamen (left/right)").
After answering, you see immediate green/red feedback and the correct answer if wrong.
A running score is tracked in the top bar.
Explore Mode — Free Exploration
A sandbox for browsing the entire brain. Every structure from the atlas is loaded into one interactive 3D scene.

Tap any structure to select it. It highlights in green; everything else fades to transparent grey.
An info card at the bottom shows the selected structure's name and its full hierarchical path through the brain's anatomy (e.g., "Brain → Cerebrum → Frontal Lobe → left superior frontal gyrus").
A search bar lets you find structures by name — results filter in real-time as you type, and selecting one highlights it in the 3D view.
An explode view slider spreads all structures outward from their natural positions, letting you peer into the interior of the brain.
A focus button recenters the camera on your selected structure, or resets to the full brain view.
MRI Mode — Dynamic Slicer
A simulated MRI experience using 3D models. The left and right white matter hemispheres are loaded, and a clipping plane slices through them. A slice is taken through the brain, allowing for a mock mri to be visualized (allowing users to see different brain regions within that slice)

A slider moves the slice position from bottom to top of the brain.
As you drag, the model is dynamically cut away in real-time, revealing cross-sectional views similar to scrolling through axial MRI slices — but in a fully rotatable 3D space.
An axis picker switches between axial, coronal, and sagittal planes.

MRI Quiz — Identify From Slices
Generates a cross-section through the brain (axial, coronal, or sagittal) with one structure highlighted and pulsing, and asks you to identify it from four options. Only slices where the target is meaningfully visible are used, distractors favor anatomically related structures, and a mini-brain shows where the slice sits.

Both quiz modes run in fixed 10-question sessions that end on a results screen (score, accuracy, best streak, and the structures you missed), and they persist lifetime progress across launches.

Data & Assets
The brain atlas data includes a hierarchical JSON file that defines every structure's name, type, group membership, and associated 3D model file. The app loads this at startup and uses it to drive all modes.

Design
The app should be simple and intuitive. Worthy of an apple design award.