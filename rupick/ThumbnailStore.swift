import AppKit
import ImageIO
import Observation
import SwiftUI

struct Thumbnail: Sendable {
    let url: URL
    let pixels: CGImage
    let width: Int
    let height: Int
    @MainActor var image: NSImage { NSImage(cgImage: pixels, size: .zero) }
}

/// A window-owned cache. The actor serializes decoding, including requests for the same file.
@MainActor @Observable
final class ThumbnailStore {
    let id = UUID()
    private let cache = ThumbnailCache()
    func load(url: URL, scope: URL, fullSize: Bool = false) async -> Thumbnail? {
        await cache.load(url: url, scope: scope, fullSize: fullSize)
    }
}

actor ThumbnailCache {
    private struct Key: Hashable {
        let url: URL
        let modified: Date?
        let size: Int?
        let fullSize: Bool
    }
    private var values: [Key: Thumbnail] = [:]
    private var order: [Key] = []
    private var cost = 0
    private let limit = 32 * 1024 * 1024

    func load(url: URL, scope: URL, fullSize: Bool) -> Thumbnail? {
        guard !Task.isCancelled else { return nil }
        let acquired = scope.startAccessingSecurityScopedResource()
        defer { if acquired { scope.stopAccessingSecurityScopedResource() } }
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let attributes = try? freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = Key(url: url, modified: attributes?.contentModificationDate,
                      size: attributes?.fileSize, fullSize: fullSize)
        if let value = values[key] {
            order.removeAll { $0 == key }; order.append(key)
            return value
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        // Actual-size inspection follows the comparison engine's memory limits.
        if fullSize && (width > 8192 || height > 8192 || width <= 0 || height <= 0 || width * height > 16_777_216) { return nil }
        guard !Task.isCancelled,
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: fullSize ? max(width, height) : 800
              ] as CFDictionary), !Task.isCancelled else { return nil }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let value = Thumbnail(url: url, pixels: pixels, width: rotated ? height : width, height: rotated ? width : height)
        let bytes = pixels.bytesPerRow * pixels.height
        if bytes <= limit {
            while (cost + bytes > limit || order.count >= 128), let oldest = order.first {
                order.removeFirst()
                if let removed = values.removeValue(forKey: oldest) { cost -= removed.pixels.bytesPerRow * removed.pixels.height }
            }
            values[key] = value; order.append(key); cost += bytes
        }
        return value
    }
}

enum PreviewBackground: String, CaseIterable, Identifiable {
    case checkerboard, light, dark
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .checkerboard: "Grid"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct PreviewBackdrop: View {
    let style: PreviewBackground
    var body: some View {
        switch style {
        case .light: Color.white
        case .dark: Color.black
        case .checkerboard:
            Canvas { context, size in
                let tile: CGFloat = 12
                for row in 0..<Int(ceil(size.height / tile)) {
                    for column in 0..<Int(ceil(size.width / tile)) {
                        let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                        context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2) ? .white : Color(white: 0.8)))
                    }
                }
            }.accessibilityHidden(true)
        }
    }
}
