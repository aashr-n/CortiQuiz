"""Convert the SPL/PNL/NAC atlas VTK models into the OBJ files bundled with the app.

The atlas stores each surface as VTK triangle *strips*. vtkOBJWriter drops strips,
which is why an earlier conversion produced OBJs with vertices but no faces. This
script triangulates first and writes a minimal OBJ (`v x y z` / `f a b c`) that
MDLAsset loads directly.

Usage (requires `pip install vtk`):
    python3 tools/convert_vtk_to_obj.py [vtk_dir] [obj_dir]

Defaults convert brainAtlas2017-01/models into CortiQuizSwift/CortiQuizSwift/BrainModels.
Only files that already exist in the output directory are rewritten unless --all is
passed, so the app's curated model set (brain structures only) is preserved.
"""

import os
import sys

import vtk

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_IN = os.path.join(REPO, "brainAtlas2017-01", "models")
DEFAULT_OUT = os.path.join(REPO, "CortiQuizSwift", "CortiQuizSwift", "BrainModels")


def convert(vtk_path, obj_path):
    reader = vtk.vtkPolyDataReader()
    reader.SetFileName(vtk_path)
    triangles = vtk.vtkTriangleFilter()
    triangles.SetInputConnection(reader.GetOutputPort())
    triangles.Update()
    mesh = triangles.GetOutput()

    name = os.path.splitext(os.path.basename(obj_path))[0]
    lines = [f"# {name}"]
    points = mesh.GetPoints()
    for i in range(mesh.GetNumberOfPoints()):
        x, y, z = points.GetPoint(i)
        lines.append(f"v {x} {y} {z}")

    ids = vtk.vtkIdList()
    polys = mesh.GetPolys()
    polys.InitTraversal()
    while polys.GetNextCell(ids):
        if ids.GetNumberOfIds() == 3:
            a, b, c = (ids.GetId(k) + 1 for k in range(3))
            lines.append(f"f {a} {b} {c}")

    with open(obj_path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    convert_all = "--all" in sys.argv
    in_dir = args[0] if len(args) > 0 else DEFAULT_IN
    out_dir = args[1] if len(args) > 1 else DEFAULT_OUT
    os.makedirs(out_dir, exist_ok=True)

    existing = set(os.listdir(out_dir))
    for filename in sorted(os.listdir(in_dir)):
        if not filename.endswith(".vtk"):
            continue
        obj_name = filename[:-4] + ".obj"
        if not convert_all and obj_name not in existing:
            continue
        convert(os.path.join(in_dir, filename), os.path.join(out_dir, obj_name))
        print(f"Converted {filename} -> {obj_name}")


if __name__ == "__main__":
    main()
