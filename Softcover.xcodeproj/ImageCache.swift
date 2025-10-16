import SwiftUI
import UIKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageCache: minne + disk med asynkron laddning
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "ImageCache.IO")

    // Diskplats: Caches/Images (snabb, auto-evict av iOS vid behov)
    private lazy var cacheDirectoryURL: URL = {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("Images", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    // Hämta bild (minne -> disk -> nät). Optionellt downsample med maxPixel (längsta sidan).
    func image(for url: URL, maxPixel: Int? = nil, cacheKeySuffix: String? = nil) async throws -> UIImage {
        let key = cacheKey(for: url, maxPixel: maxPixel, suffix: cacheKeySuffix)

        // 1) Minne
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        // 2) Disk
        let diskURL = diskURLForKey(key)
        if fileManager.fileExists(atPath: diskURL.path) {
            if let data = try? Data(contentsOf: diskURL),
               let img = UIImage(data: data, scale: UIScreen.main.scale) {
                memory.setObject(img, forKey: key as NSString)
                return img
            }
            // Om filen är korrupt, ta bort
            try? fileManager.removeItem(at: diskURL)
        }

        // 3) Nätverk
        let (data, _) = try await URLSession.shared.data(from: url)

        // 4) Downsample vid behov
        let finalImage: UIImage
        if let maxPixel {
            finalImage = (downsampledImage(data: data, maxPixel: maxPixel) ?? UIImage(data: data)) ?? UIImage()
        } else {
            finalImage = UIImage(data: data) ?? UIImage()
        }

        // 5) Cachea
        memory.setObject(finalImage, forKey: key as NSString)
        ioQueue.async { [data, diskURL] in
            // Spara originaldata om möjligt; annars PNG från finalImage
            if (try? data.write(to: diskURL, options: .atomic)) == nil,
               let png = finalImage.pngData() {
                try? png.write(to: diskURL, options: .atomic)
            }
        }

        return finalImage
    }

    // Manuellt sätt in bild i cache (om du redan har UIImage)
    func set(_ image: UIImage, for url: URL, maxPixel: Int? = nil, cacheKeySuffix: String? = nil) {
        let key = cacheKey(for: url, maxPixel: maxPixel, suffix: cacheKeySuffix)
        memory.setObject(image, forKey: key as NSString)
        let diskURL = diskURLForKey(key)
        if let data = image.pngData() {
            ioQueue.async {
                try? data.write(to: diskURL, options: .atomic)
            }
        }
    }

    // Rensa enskild post
    func remove(for url: URL, maxPixel: Int? = nil, cacheKeySuffix: String? = nil) {
        let key = cacheKey(for: url, maxPixel: maxPixel, suffix: cacheKeySuffix)
        memory.removeObject(forKey: key as NSString)
        let diskURL = diskURLForKey(key)
        try? fileManager.removeItem(at: diskURL)
    }

    // Rensa allt
    func clearAll() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectoryURL)
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    private func cacheKey(for url: URL, maxPixel: Int?, suffix: String?) -> String {
        // Stabil hash av URL + variant (t.ex. storlek)
        let base = url.absoluteString + (maxPixel.map { "|mp=\($0)" } ?? "") + (suffix.map { "|\($0)" } ?? "")
        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        let hex = digest.map { String(format: "%02hhx", $0) }.joined()
        return hex
    }

    private func diskURLForKey(_ key: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(key).appendingPathExtension("img")
    }

    // Effektiv downsampling till given maxPixel (längsta sidan)
    private func downsampledImage(data: Data, maxPixel: Int) -> UIImage? {
        guard maxPixel > 0 else { return UIImage(data: data) }
        let srcOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceTypeIdentifierHint: (UTType.jpeg.identifier as CFString)
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions as CFDictionary) else {
            return nil
        }
        let downOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, downOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImg, scale: UIScreen.main.scale, orientation: .up)
    }
}

// MARK: - AsyncCachedImage: SwiftUI-vy med cache + fallback till Data
struct AsyncCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixel: Int?
    let dataFallback: Data?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var task: Task<Void, Never>?

    init(
        url: URL?,
        maxPixel: Int? = nil,
        dataFallback: Data? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixel = maxPixel
        self.dataFallback = dataFallback
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if let data = dataFallback, let img = UIImage(data: data) {
                // Fallback direkt om URL saknas eller ej laddad än
                content(Image(uiImage: img))
                    .onAppear(perform: startLoadingIfNeeded) // starta ändå URL-laddning i bakgrunden
            } else {
                placeholder()
                    .onAppear(perform: startLoadingIfNeeded)
            }
        }
        .onDisappear {
            task?.cancel()
            task = nil
        }
    }

    private func startLoadingIfNeeded() {
        guard task == nil else { return }
        guard let url else { return }
        task = Task {
            if Task.isCancelled { return }
            do {
                let img = try await ImageCache.shared.image(for: url, maxPixel: maxPixel)
                if Task.isCancelled { return }
                await MainActor.run { self.uiImage = img }
            } catch {
                // Tyst fel – placeholder eller dataFallback visas redan
            }
        }
    }
}

// MARK: - Bekvämlighetsinit med standardinnehåll
extension AsyncCachedImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?, maxPixel: Int? = nil, dataFallback: Data? = nil) {
        self.init(
            url: url,
            maxPixel: maxPixel,
            dataFallback: dataFallback,
            content: { $0.resizable() },
            placeholder: { ProgressView() }
        )
    }
}
