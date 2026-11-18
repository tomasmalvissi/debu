import SwiftUI
import AppKit

/// Ícono de un proyecto: su favicon si tiene uno; si no, un cuadrado con sus iniciales.
/// Con duplicados lleva un borde rojo. Detenido, se ve atenuado.
struct ProjectAvatar: View {
    let project: DotnetProject
    var size: CGFloat = 40
    var isRunning = true
    var hasDuplicates = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)

        Group {
            if let icon = Self.icon(for: project) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
                    .background(Color(nsColor: .controlBackgroundColor))
            } else {
                Text(project.monogram)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    // Invertido según el tema: negro con letras blancas en claro, al revés en oscuro.
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isRunning ? Color.primary : Color.secondary.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(hasDuplicates ? Color.red : Color.primary.opacity(0.12),
                                    lineWidth: hasDuplicates ? 2 : 0.5))
        .opacity(isRunning ? 1 : 0.7)
    }

    /// Los favicons se leen una sola vez (como un MemoryCache).
    private static var cache: [String: NSImage] = [:]

    private static func icon(for project: DotnetProject) -> NSImage? {
        guard let path = project.iconPath else { return nil }
        if let cached = cache[path] { return cached }
        let image = NSImage(contentsOfFile: path)
        cache[path] = image
        return image
    }
}
