// Renders the atlas brain from the left, each lobe in a flat ID color, for the app icon's
// layer masks. Run by make_icon_layers.py, which writes the lobe list this reads.
//
// usage: render_lobes <lobes.tsv> <BrainModels dir> <out.png> [size]

import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO

let args = CommandLine.arguments
let tsvPath = args[1], modelDir = args[2], outPath = args[3]
let size = args.count > 4 ? Int(args[4])! : 2048

/// Must match LOBE_COLORS in make_icon_layers.py.
let colors: [String: NSColor] = [
    "frontal": NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
    "parietal": NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
    "temporal": NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
    "occipital": NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1),
    "cerebellum": NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1),
    "brainstem": NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1),
    "insula": NSColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 1),
    "other": NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
]

let rows = try String(contentsOfFile: tsvPath, encoding: .utf8)
    .split(separator: "\n")
    .map { $0.split(separator: "\t").map(String.init) }

let scene = SCNScene()
var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
for row in rows where row.count == 2 {
    let (file, lobe) = (row[0], row[1])
    let asset = MDLAsset(url: URL(fileURLWithPath: modelDir).appendingPathComponent(file))
    guard asset.count > 0 else { continue }
    let node = SCNNode(mdlObject: asset.object(at: 0))
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = colors[lobe] ?? colors["other"]!
    material.isDoubleSided = true
    node.geometry?.materials = [material]
    let (bmin, bmax) = node.boundingBox
    lo = simd_min(lo, SIMD3(Float(bmin.x), Float(bmin.y), Float(bmin.z)))
    hi = simd_max(hi, SIMD3(Float(bmax.x), Float(bmax.y), Float(bmax.z)))
    scene.rootNode.addChildNode(node)
}

// Orthographic, from the patient's left (RAS: -X), superior up: frontal lobe on the left.
let center = (lo + hi) / 2
let camera = SCNCamera()
camera.usesOrthographicProjection = true
camera.orthographicScale = Double(max(hi.y - lo.y, hi.z - lo.z)) / 2 * 1.02
camera.zNear = 1
camera.zFar = 2000
let cameraNode = SCNNode()
cameraNode.camera = camera
cameraNode.simdPosition = SIMD3(lo.x - 300, center.y, center.z)
cameraNode.simdLook(at: center, up: SIMD3(0, 0, 1), localFront: SIMD3(0, 0, -1))
scene.rootNode.addChildNode(cameraNode)
scene.background.contents = NSColor.black

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .none)
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
