#if DEBUG
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Explicitly enabled with RUPICK_STRESS_UI=1; never included in Release builds.
    enum StressDataset: String, CaseIterable, Identifiable, Sendable {
        case demo
        case worst
        case empty
        case one
        case thousand
        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .demo:
                "Demo"

            case .worst:
                "Worst case"

            case .empty:
                "Empty"

            case .one:
                "One"

            case .thousand:
                "1,000 assets"
            }
        }

        func makeIncomingImages(in root: URL) throws -> [URL] {
            guard self != .empty,
                  let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
                  let source = files.compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "illustration-dark-contrast@3x.png" })
            else {
                return []
            }

            let folder = root.appendingPathComponent("Incoming")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let names = self == .worst
                ? ["PaymentConfirmationIllustration-Dark-HighContrast-Final.png", "王秀英-نور-الهدى-👩🏽‍💻.png", "J.png"]
                : ["incoming.png", "another.png"]
            return try names.map { name in
                let url = folder.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: url)
                return url
            }
        }

        func makeProject() throws -> URL {
            let root = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("Rupick UI Fixtures/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                let count =
                    switch self {
                    case .empty:
                        0

                    case .one:
                        1

                    case .demo:
                        3

                    case .worst:
                        16

                    case .thousand:
                        1000
                    }
                // Transparent artwork exercises light, dark, and checkerboard backgrounds.
                let bytes = Data([20, 20, 20, 255, 0, 0, 0, 0])
                guard let provider = CGDataProvider(data: bytes as CFData),
                      let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
                else {
                    throw CocoaError(.fileWriteUnknown)
                }

                let names = ["PaymentConfirmationIllustration-Dark-HighContrast-Final",
                             "Icon", "J", "Đặng-Thị-Ngọc-Hân", "王秀英", "نور-الهدى", "👩🏽‍💻-Workspace"]
                for index in 0 ..< count {
                    try Task.checkCancellation()
                    let name = self == .worst ? names[index % names.count] : "Image\(index)"
                    let entry = root.appendingPathComponent("Packages/Feature\(index)/Resources/Assets.xcassets/\(name).imageset")
                    try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
                    let url = entry.appendingPathComponent("illustration-dark-contrast@3x.png")
                    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                        throw CocoaError(.fileWriteUnknown)
                    }

                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else {
                        throw CocoaError(.fileWriteUnknown)
                    }

                    try Data(#"{"images":[{"filename":"illustration-dark-contrast@3x.png","scale":"3x","appearances":[{"appearance":"luminosity","value":"dark"}]}]}"#.utf8)
                        .write(to: entry.appendingPathComponent("Contents.json"))
                }
                if self == .worst {
                    // Realistic media extremes and a missing alternative preview.
                    for (name, width, height) in [("Panorama", 4000, 200), ("Portrait", 200, 4000)] {
                        let data = Data(repeating: 255, count: width * height * 4)
                        guard let provider = CGDataProvider(data: data as CFData),
                              let pixels = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
                        else {
                            throw CocoaError(.fileWriteUnknown)
                        }

                        for index in 0 ..< 2 {
                            let entry = root.appendingPathComponent("Media.xcassets/\(name)\(index).imageset")
                            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
                            guard let destination = CGImageDestinationCreateWithURL(entry.appendingPathComponent("image.png") as CFURL,
                                                                                    UTType.png.identifier as CFString, 1, nil)
                            else {
                                throw CocoaError(.fileWriteUnknown)
                            }

                            CGImageDestinationAddImage(destination, pixels, nil)
                            guard CGImageDestinationFinalize(destination) else {
                                throw CocoaError(.fileWriteUnknown)
                            }

                            let metadata = index == 0
                                ? #"{"images":[{"filename":"image.png","scale":"1x"},{"filename":"missing-dark.png","scale":"2x"}]}"#
                                : #"{"images":[{"filename":"image.png","scale":"1x"}]}"#
                            try Data(metadata.utf8).write(to: entry.appendingPathComponent("Contents.json"))
                        }
                    }
                    let corrupt = root.appendingPathComponent("Unreadable.xcassets/Unavailable.imageset")
                    try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
                    try Data("unreadable".utf8).write(to: corrupt.appendingPathComponent("Contents.json"))
                }
                return root
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }
#endif
