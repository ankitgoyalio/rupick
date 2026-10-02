import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

private struct NormalizedImage {
    let image: CIImage
    let width: Int
    let height: Int

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        image = CIImage(cgImage: cgImage).oriented(forExifOrientation: orientation)
        width = Int(image.extent.width); height = Int(image.extent.height)
        // Bound temporary decode memory; an oversized file is reported, never called a non-match.
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216 else { throw CocoaError(.fileReadTooLarge) }
    }
}

private struct DecodedPixels: Equatable {
    let width: Int
    let height: Int
    let values: [Float]

    init(url: URL, context: CIContext) throws {
        self.init(image: try NormalizedImage(url: url), context: context)
    }

    init(image: NormalizedImage, context: CIContext) {
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            context.render(image.image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                           bounds: image.image.extent, format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!)
        }
        pixels.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress!
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                if pointer[offset + 3] == 0 {
                    pointer[offset] = 0; pointer[offset + 1] = 0; pointer[offset + 2] = 0
                }
                // Float equality treats negative zero as zero. Canonicalize it before hashing.
                for channel in 0..<4 where pointer[offset + channel] == 0 { pointer[offset + channel] = 0 }
            }
        }
        values = pixels
    }
}

private struct PixelFingerprint: Equatable {
    let width: Int
    let height: Int
    let digest: SHA256.Digest
    init(_ pixels: DecodedPixels) {
        width = pixels.width; height = pixels.height
        digest = pixels.values.withUnsafeBytes { SHA256.hash(data: $0) }
    }
}

private struct CatalogContents: Decodable {
    struct Image: Decodable {
        struct Appearance: Decodable { let appearance: String; let value: String }
        let filename: String?
        let idiom: String?
        let scale: String?
        let appearances: [Appearance]?
        var label: String {
            ([idiom ?? "universal", scale ?? "any scale"] +
             (appearances ?? []).map { "\($0.appearance): \($0.value)" }).joined(separator: " · ")
        }
    }
    let images: [Image]
}

enum CatalogComparison {
    static func run(root: URL, incoming: [URL], publish: @Sendable (ScanSnapshot) async -> Void) async {
        var snapshot = ScanSnapshot(results: incoming.map { IncomingResult(url: $0) })
        let boundary = root.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: boundary.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            snapshot.error = "The project folder is unavailable. Choose it again."
            await publish(snapshot); return
        }
        func withinRoot(_ url: URL) -> Bool {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(boundary.path.hasSuffix("/") ? boundary.path : boundary.path + "/")
        }
        var entries: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: boundary,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [],
            errorHandler: { _, _ in snapshot.skipped += 1; return true }) else {
            snapshot.error = "The project folder could not be read. Choose it again."
            await publish(snapshot); return
        }
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { return }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if url.pathExtension == "imageset", values?.isDirectory == true {
                enumerator.skipDescendants()
                var parent = url.deletingLastPathComponent()
                while parent.path != boundary.path, parent.pathExtension != "xcassets" { parent.deleteLastPathComponent() }
                if parent.pathExtension == "xcassets" { entries.append(url) }
            }
            if entries.count != snapshot.discovered {
                snapshot.discovered = entries.count
                await publish(snapshot)
            }
        }
        let context = CIContext(options: [.useSoftwareRenderer: true, .outputPremultiplied: false,
                                         .workingFormat: CIFormat.RGBAf,
                                         .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!])
        var incomingFingerprints: [PixelFingerprint?] = []
        snapshot.phase = "Reading incoming images…"
        for index in incoming.indices {
            if Task.isCancelled { return }
            snapshot.results[index].status = .decoding
            await publish(snapshot)
            do {
                incomingFingerprints.append(try autoreleasepool {
                    PixelFingerprint(try DecodedPixels(url: incoming[index], context: context))
                })
            }
            catch {
                snapshot.results[index].status = .unreadable
                incomingFingerprints.append(nil)
                snapshot.results[index].error = "Could not read this PNG or JPEG. Check file access or choose another image, up to 16 megapixels and 8,192 pixels per side."
            }
            if snapshot.results[index].error == nil { snapshot.results[index].status = .comparing }
            snapshot.decoded += 1
            await publish(snapshot)
        }
        snapshot.phase = "Comparing image assets…"
        await publish(snapshot)
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            if Task.isCancelled { return }
            do {
                let contentsURL = entry.appendingPathComponent("Contents.json")
                guard withinRoot(contentsURL) else { throw CocoaError(.fileReadNoPermission) }
                let contents = try JSONDecoder().decode(CatalogContents.self, from: Data(contentsOf: contentsURL))
                var variants: [(url: URL, label: String, matchingInputs: Set<Int>)] = []
                for image in contents.images {
                    guard let filename = image.filename else { continue }
                    let url = entry.appendingPathComponent(filename)
                    guard withinRoot(url), url.deletingLastPathComponent().standardizedFileURL == entry.standardizedFileURL else {
                        snapshot.skipped += 1; continue
                    }
                    let matchingInputs: Set<Int>? = autoreleasepool {
                        guard let image = try? NormalizedImage(url: url) else { return nil }
                        guard incomingFingerprints.contains(where: {
                            $0?.width == image.width && $0?.height == image.height
                        }) else { return [] }
                        let pixels = DecodedPixels(image: image, context: context)
                        let fingerprint = PixelFingerprint(pixels)
                        // Hash only narrows the search. Verify every actual match with component equality.
                        return Set(incoming.indices.filter { index in
                            guard incomingFingerprints[index] == fingerprint else { return false }
                            return (try? DecodedPixels(url: incoming[index], context: context)) == pixels
                        })
                    }
                    if matchingInputs == nil { snapshot.skipped += 1 }
                    variants.append((url, image.label, matchingInputs ?? []))
                }
                for index in incoming.indices {
                    guard variants.contains(where: { $0.matchingInputs.contains(index) }) else { continue }
                    let representations = variants.map {
                        Representation(id: $0.url.path + $0.label, url: $0.url, label: $0.label,
                                       matches: $0.matchingInputs.contains(index))
                    }
                    snapshot.results[index].candidates.append(AssetCandidate(id: entry.path,
                        name: entry.deletingPathExtension().lastPathComponent,
                        location: String(entry.path.dropFirst(boundary.path.hasSuffix("/") ? boundary.path.count : boundary.path.count + 1)), representations: representations))
                }
            } catch { snapshot.skipped += 1 }
            snapshot.compared += 1
            await publish(snapshot)
        }
    }
}
