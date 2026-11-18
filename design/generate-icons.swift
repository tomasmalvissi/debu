// Genera los íconos de Debu a partir de dibujos vectoriales.
// Uso (desde la carpeta del repo):
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift design/generate-icons.swift
//
// Produce:
//   Debu/Assets.xcassets/AppIcon.appiconset     → ícono de la app: palanca con detalle rojo (el que se usa)
//   Debu/Assets.xcassets/MenuBarIcon.imageset   → silueta de la palanca para la barra de menú (plantilla)
//   design/alternativa-D/                       → ícono alternativo "D en bloque" negro (no se usa en la app)
//
// Estilo: objeto isométrico, contorno blanco grueso, separación negra, caras superior y derecha blancas.

import AppKit

// MARK: - Colores

let white = NSColor(white: 0.97, alpha: 1)
let black = NSColor(white: 0.06, alpha: 1)
let red = NSColor(red: 0.90, green: 0.20, blue: 0.17, alpha: 1)

/// Cómo se pinta cada parte: con un color o recortando (transparente, para la plantilla de la barra de menú).
enum Paint { case ink(NSColor), cut }

struct Style {
    var outline: Paint      // contorno exterior y caras claras
    var gap: Paint          // separación y caras oscuras
    var accent: Paint       // la palanca
    var outlineWidth: CGFloat
    var gapWidth: CGFloat
}

// MARK: - Geometría isométrica

let cos30 = cos(CGFloat.pi / 6)

struct P3 { var x: CGFloat, y: CGFloat, z: CGFloat }

func iso(_ p: P3) -> NSPoint { NSPoint(x: (p.x - p.y) * cos30, y: -(p.x + p.y) * 0.5 + p.z) }

func polygon(_ points: [P3]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: iso(points[0]))
    points.dropFirst().forEach { path.line(to: iso($0)) }
    path.close()
    return path
}

enum Role { case light, dark, accent }

struct Face { var path: NSBezierPath; var role: Role }
struct Solid { var silhouette: NSBezierPath; var faces: [Face]; var details: [Face] = [] }

func box(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat, _ d: CGFloat, _ h: CGFloat,
         top: Role = .light, right: Role = .light, left: Role = .dark) -> Solid {
    let topFace = polygon([P3(x: x, y: y, z: z + h), P3(x: x + w, y: y, z: z + h), P3(x: x + w, y: y + d, z: z + h), P3(x: x, y: y + d, z: z + h)])
    let rightFace = polygon([P3(x: x + w, y: y, z: z), P3(x: x + w, y: y + d, z: z), P3(x: x + w, y: y + d, z: z + h), P3(x: x + w, y: y, z: z + h)])
    let leftFace = polygon([P3(x: x, y: y + d, z: z), P3(x: x + w, y: y + d, z: z), P3(x: x + w, y: y + d, z: z + h), P3(x: x, y: y + d, z: z + h)])
    let silhouette = NSBezierPath()
    [topFace, rightFace, leftFace].forEach { silhouette.append($0) }
    return Solid(silhouette: silhouette, faces: [Face(path: leftFace, role: left), Face(path: rightFace, role: right), Face(path: topFace, role: top)])
}

// MARK: - Dibujos

/// Palanca: bloque macizo con una ranura y la palanca (en el color de acento).
func leverSolids() -> [Solid] {
    var body = box(0, 0, 0, 260, 260, 150)
    body.details = [Face(path: polygon([P3(x: 90, y: 40, z: 150), P3(x: 170, y: 40, z: 150),
                                        P3(x: 170, y: 220, z: 150), P3(x: 90, y: 220, z: 150)]), role: .dark)]
    let lever = box(100, 60, 150, 60, 70, 150, top: .accent, right: .accent, left: .dark)
    return [body, lever]
}

/// "D" de Debu parada, extruida hacia atrás, con su hueco.
func dFace(inset: CGFloat, y: CGFloat) -> NSBezierPath {
    let h: CGFloat = 360 - inset * 2, r = h / 2, straight = max(120 - inset, 0)
    var points = [P3(x: inset, y: y, z: inset), P3(x: inset + straight, y: y, z: inset)]
    for k in 0...28 {
        let angle = -CGFloat.pi / 2 + CGFloat(k) / 28 * .pi
        points.append(P3(x: inset + straight + r * cos(angle), y: y, z: inset + r + r * sin(angle)))
    }
    points.append(P3(x: inset, y: y, z: inset + h))
    return polygon(points)
}

func dSolids() -> [Solid] {
    let depth: CGFloat = 110
    let sweep = NSBezierPath()
    stride(from: 0, through: depth, by: 3).forEach { sweep.append(dFace(inset: 0, y: $0)) }
    var solid = Solid(silhouette: sweep, faces: [Face(path: sweep.copy() as! NSBezierPath, role: .dark),
                                                  Face(path: dFace(inset: 0, y: depth), role: .light)])
    solid.details = [Face(path: dFace(inset: 92, y: depth), role: .dark)]
    return [solid]
}

// MARK: - Render

func use(_ paint: Paint) {
    switch paint {
    case .ink(let color):
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        color.setFill(); color.setStroke()
    case .cut:
        NSGraphicsContext.current?.compositingOperation = .clear
    }
}

/// Dibuja los sólidos centrados en `center`, con su lado mayor de `span` puntos.
func render(_ solids: [Solid], style: Style, center: NSPoint, span: CGFloat) {
    let all = NSBezierPath()
    solids.forEach { all.append($0.silhouette) }
    let bounds = all.bounds
    var transform = AffineTransform(translationByX: -bounds.midX, byY: -bounds.midY)
    transform.append(AffineTransform(scale: span / max(bounds.width, bounds.height)))
    transform.append(AffineTransform(translationByX: center.x, byY: center.y))
    for solid in solids {
        solid.silhouette.transform(using: transform)
        solid.faces.forEach { $0.path.transform(using: transform) }
        solid.details.forEach { $0.path.transform(using: transform) }
    }

    func paint(for role: Role) -> Paint {
        switch role { case .light: style.outline; case .dark: style.gap; case .accent: style.accent }
    }

    // 1) contorno exterior y 2) separación
    for (width, p) in [((style.outlineWidth + style.gapWidth) * 2, style.outline), (style.gapWidth * 2, style.gap)] {
        for solid in solids {
            let path = solid.silhouette.copy() as! NSBezierPath
            path.lineWidth = width; path.lineJoinStyle = .round
            use(p); path.stroke(); path.fill()
        }
    }
    // 3) caras, de atrás hacia adelante, con su separación
    for solid in solids {
        for face in solid.faces {
            use(paint(for: face.role)); face.path.fill()
            let edge = face.path.copy() as! NSBezierPath
            edge.lineWidth = style.gapWidth; edge.lineJoinStyle = .round
            use(style.gap); edge.stroke()
        }
        for detail in solid.details {
            use(paint(for: detail.role)); detail.path.fill()
        }
    }
    NSGraphicsContext.current?.compositingOperation = .sourceOver
}

/// Fondo del ícono según la plantilla de macOS: 824×824 centrado en 1024, esquinas redondeadas, sombra.
func drawAppIconBackground() {
    let path = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: black)!.draw(in: path, angle: -90)
}

func appIconStyle(accent: NSColor) -> Style {
    Style(outline: .ink(white), gap: .ink(black), accent: .ink(accent), outlineWidth: 26, gapWidth: 22)
}

/// Dibuja en un mapa de bits de `pixels` × `pixels`; el dibujo usa coordenadas de un lienzo de `canvas`.
func bitmap(pixels: Int, canvas: CGFloat, height: Int? = nil, width canvasWidth: CGFloat? = nil, draw: () -> Void) -> Data {
    let pw = canvasWidth.map { Int((CGFloat(pixels) * $0 / canvas).rounded()) } ?? pixels
    let ph = height ?? pixels
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(ph) / canvas, y: CGFloat(ph) / canvas)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Salidas

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func writeAppIconSet(to folder: URL, solids: @escaping () -> [Solid], style: Style) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    var entries: [String] = []
    for (points, scale) in sizes {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = bitmap(pixels: points * scale, canvas: 1024) {
            drawAppIconBackground()
            render(solids(), style: style, center: NSPoint(x: 512, y: 512), span: 560)
        }
        try data.write(to: folder.appendingPathComponent(name))
        entries.append("{ \"idiom\": \"mac\", \"size\": \"\(points)x\(points)\", \"scale\": \"\(scale)x\", \"filename\": \"\(name)\" }")
    }
    let json = "{\n  \"images\": [\n    " + entries.joined(separator: ",\n    ") + "\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 }\n}\n"
    try json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// 1) Ícono de la app: palanca roja.
try writeAppIconSet(to: repo.appendingPathComponent("Debu/Assets.xcassets/AppIcon.appiconset"),
                    solids: leverSolids, style: appIconStyle(accent: red))

// 2) Barra de menú: silueta de la palanca como plantilla (macOS la pinta según el tema).
//    Trazos más gruesos para que se lea a 18 puntos.
let menuFolder = repo.appendingPathComponent("Debu/Assets.xcassets/MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: menuFolder, withIntermediateDirectories: true)
let menuStyle = Style(outline: .ink(.black), gap: .cut, accent: .ink(.black), outlineWidth: 50, gapWidth: 50)
for scale in [1, 2] {
    let data = bitmap(pixels: 18 * scale, canvas: 1024) {
        render(leverSolids(), style: menuStyle, center: NSPoint(x: 512, y: 512), span: 820)
    }
    try data.write(to: menuFolder.appendingPathComponent("menubar@\(scale)x.png"))
}
try """
{
  "images": [
    { "idiom": "mac", "scale": "1x", "filename": "menubar@1x.png" },
    { "idiom": "mac", "scale": "2x", "filename": "menubar@2x.png" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": { "template-rendering-intent": "template" }
}

""".write(to: menuFolder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// 3) Alternativa "D en bloque" negra: se guarda en design/, no se usa en la app.
let alternative = repo.appendingPathComponent("design/alternativa-D")
try writeAppIconSet(to: alternative.appendingPathComponent("AppIcon.appiconset"),
                    solids: dSolids, style: appIconStyle(accent: white))
try bitmap(pixels: 1024, canvas: 1024) {
    drawAppIconBackground()
    render(dSolids(), style: appIconStyle(accent: white), center: NSPoint(x: 512, y: 512), span: 560)
}.write(to: alternative.appendingPathComponent("icono-D-1024.png"))

// Vista previa del ícono en uso, para el repo.
try bitmap(pixels: 1024, canvas: 1024) {
    drawAppIconBackground()
    render(leverSolids(), style: appIconStyle(accent: red), center: NSPoint(x: 512, y: 512), span: 560)
}.write(to: repo.appendingPathComponent("design/icono-palanca-1024.png"))

print("Íconos generados.")
