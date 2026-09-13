import SwiftUI
import UIKit
import ImageIO
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Public AsyncImage-like phase
public enum AsyncCachedImagePhase {
    case empty
    case progress(Double) // 0.0 ... 1.0
    case success(Image)
    case failure(Error)
}

// MARK: - Units for maxPixel
public enum AsyncCachedImagePixelUnit: Sendable {
    case points
    case pixels
}

// MARK: - Public configuration
public struct AsyncCachedImageConfiguration: Sendable {
    public var retryCount: Int
    public var retryDelay: TimeInterval
    public var session: URLSession
    public var taskPriority: TaskPriority?
    public var fadeInDuration: TimeInterval
    
    public init(
        retryCount: Int = 1,
        retryDelay: TimeInterval = 0.5,
        session: URLSession = AsyncCachedImageTools.makeDefaultSession(),
        taskPriority: TaskPriority? = nil,
        fadeInDuration: TimeInterval = 0.18
    ) {
        self.retryCount = retryCount
        self.retryDelay = retryDelay
        self.session = session
        self.taskPriority = taskPriority
        self.fadeInDuration = fadeInDuration
    }
}

public enum AsyncCachedImageTools {
    private static let configurationStorage = ImageConfigurationStorage()
    public static var configuration: AsyncCachedImageConfiguration {
        get { configurationStorage.get() }
        set { configurationStorage.set(newValue) }
    }
    
    // Skapa en URLSession med större URLCache och bra defaults
    public static func makeDefaultSession() -> URLSession {
        let memory = 64 * 1024 * 1024  // 64 MB
        let disk = 512 * 1024 * 1024   // 512 MB
        let cache = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "AsyncCachedImageURLCache")
        
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.urlCache = cache
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }
    
    // Diskcache-konfiguration
    public static func configureDiskCache(ttl: TimeInterval, maxSizeMB: Int) {
        Task {
            await DiskCache.shared.configure(ttl: ttl, maxSizeBytes: max(1, maxSizeMB) * 1024 * 1024)
        }
    }
    
    // Manuell cachehantering
    public static func clearMemory() {
        MemoryImageCache.shared.removeAll()
    }
    
    public static func clearDisk() {
        Task { await DiskCache.shared.removeAll() }
    }
    
    public static func clearAll() {
        clearMemory()
        clearDisk()
    }
    
    public static func remove(for url: URL, maxPixel: Int? = nil, pixelUnit: AsyncCachedImagePixelUnit = .points, scale: CGFloat = 0) {
        let scales = scale > 0 ? [Int(scale.rounded())] : [1, 2, 3]
        let processedKeys = scales.map { cacheKeyProcessed(url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: $0) }
        let originalKey = cacheKeyOriginal(url: url)
        for key in processedKeys { MemoryImageCache.shared.remove(forKey: key) }
        Task {
            for key in processedKeys { await DiskCache.shared.remove(forKey: key) }
            await DiskCache.shared.remove(forKey: originalKey)
        }
    }
    
    public static func remove(for request: URLRequest, maxPixel: Int? = nil, pixelUnit: AsyncCachedImagePixelUnit = .points, scale: CGFloat = 0) {
        guard let url = request.url else { return }
        remove(for: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: scale)
    }
    
    // Prefetch-stöd
    public static func prefetch(urls: [URL], maxPixel: Int? = nil, pixelUnit: AsyncCachedImagePixelUnit = .points, scale: CGFloat = 0) {
        guard !urls.isEmpty else { return }
        let cfg = configuration
        Task(priority: cfg.taskPriority) {
            let resolvedScale = scale > 0 ? scale : await defaultDisplayScale()
            for url in urls {
                if Task.isCancelled { return }
                await prefetchOne(url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: resolvedScale, cfg: cfg)
            }
        }
    }
    
    public static func prefetch(requests: [URLRequest], maxPixel: Int? = nil, pixelUnit: AsyncCachedImagePixelUnit = .points, scale: CGFloat = 0) {
        guard !requests.isEmpty else { return }
        let cfg = configuration
        Task(priority: cfg.taskPriority) {
            let resolvedScale = scale > 0 ? scale : await defaultDisplayScale()
            for req in requests {
                if Task.isCancelled { return }
                guard let url = req.url else { continue }
                await prefetchOne(request: req, url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: resolvedScale, cfg: cfg)
            }
        }
    }

    @MainActor
    private static func defaultDisplayScale() -> CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.scale }.first ?? 2
    }
    
    private static func prefetchOne(url: URL, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, scale: CGFloat, cfg: AsyncCachedImageConfiguration) async {
        let processedKey = cacheKeyProcessed(url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: Int(scale.rounded()))
        let originalKey = cacheKeyOriginal(url: url)
        
        if MemoryImageCache.shared.image(forKey: processedKey) != nil { return }
        if let img = await DiskCache.shared.loadImage(forKey: processedKey) {
            MemoryImageCache.shared.store(image: img, forKey: processedKey)
            return
        }
        if let data = await DiskCache.shared.loadData(forKey: originalKey) {
            if let processed = await downsampledImage(data: data, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: scale) {
                await DiskCache.shared.storeImage(processed, forKey: processedKey)
                MemoryImageCache.shared.store(image: processed, forKey: processedKey)
                return
            } else if let ui = UIImage(data: data) {
                await DiskCache.shared.storeImage(ui, forKey: processedKey)
                MemoryImageCache.shared.store(image: ui, forKey: processedKey)
                return
            }
        }
        do {
            let data = try await RequestCoalescer.shared.fetch(url: url, session: cfg.session, retries: cfg.retryCount, delay: cfg.retryDelay)
            await DiskCache.shared.storeData(data, forKey: originalKey)
            if let processed = await downsampledImage(data: data, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: scale) {
                await DiskCache.shared.storeImage(processed, forKey: processedKey)
                MemoryImageCache.shared.store(image: processed, forKey: processedKey)
            } else if let ui = UIImage(data: data) {
                await DiskCache.shared.storeImage(ui, forKey: processedKey)
                MemoryImageCache.shared.store(image: ui, forKey: processedKey)
            }
        } catch {
            // Ignorera tysta prefetch-fel
        }
    }
    
    private static func prefetchOne(request: URLRequest, url: URL, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, scale: CGFloat, cfg: AsyncCachedImageConfiguration) async {
        let processedKey = cacheKeyProcessed(url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: Int(scale.rounded()))
        let originalKey = cacheKeyOriginal(url: url)
        
        if MemoryImageCache.shared.image(forKey: processedKey) != nil { return }
        if let img = await DiskCache.shared.loadImage(forKey: processedKey) {
            MemoryImageCache.shared.store(image: img, forKey: processedKey)
            return
        }
        if let data = await DiskCache.shared.loadData(forKey: originalKey) {
            if let processed = await downsampledImage(data: data, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: scale) {
                await DiskCache.shared.storeImage(processed, forKey: processedKey)
                MemoryImageCache.shared.store(image: processed, forKey: processedKey)
                return
            } else if let ui = UIImage(data: data) {
                await DiskCache.shared.storeImage(ui, forKey: processedKey)
                MemoryImageCache.shared.store(image: ui, forKey: processedKey)
                return
            }
        }
        do {
            let data = try await RequestCoalescer.shared.fetch(request: request, session: cfg.session, retries: cfg.retryCount, delay: cfg.retryDelay)
            await DiskCache.shared.storeData(data, forKey: originalKey)
            if let processed = await downsampledImage(data: data, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: scale) {
                await DiskCache.shared.storeImage(processed, forKey: processedKey)
                MemoryImageCache.shared.store(image: processed, forKey: processedKey)
            } else if let ui = UIImage(data: data) {
                await DiskCache.shared.storeImage(ui, forKey: processedKey)
                MemoryImageCache.shared.store(image: ui, forKey: processedKey)
            }
        } catch {
            // Ignorera tysta prefetch-fel
        }
    }
}

// MARK: - Public SwiftUI view
public struct AsyncCachedImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let request: URLRequest?
    private let maxPixel: Int?
    private let pixelUnit: AsyncCachedImagePixelUnit
    private let dataFallback: Data?
    private let fadeInDuration: TimeInterval
    private let progressBinding: Binding<Double?>?
    
    // Two rendering modes: either classic (image + placeholder) or phase-based
    private let imageContent: ((Image) -> Content)?
    private let phaseContent: ((AsyncCachedImagePhase) -> Content)?
    private let placeholder: (() -> Placeholder)?
    
    @StateObject private var loader: ImageLoader
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // Classic initializer (URL)
    public init(
        url: URL?,
        maxPixel: Int? = nil,
        pixelUnit: AsyncCachedImagePixelUnit = .points,
        dataFallback: Data? = nil,
        fadeInDuration: TimeInterval = AsyncCachedImageTools.configuration.fadeInDuration,
        progress: Binding<Double?>? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.request = nil
        self.maxPixel = maxPixel
        self.pixelUnit = pixelUnit
        self.dataFallback = dataFallback
        self.fadeInDuration = fadeInDuration
        self.progressBinding = progress
        self.imageContent = content
        self.phaseContent = nil
        self.placeholder = placeholder
        _loader = StateObject(wrappedValue: ImageLoader(url: url, request: nil, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback, configuration: AsyncCachedImageTools.configuration, progressBinding: progress))
    }
    
    // Classic initializer (URLRequest)
    public init(
        request: URLRequest?,
        maxPixel: Int? = nil,
        pixelUnit: AsyncCachedImagePixelUnit = .points,
        dataFallback: Data? = nil,
        fadeInDuration: TimeInterval = AsyncCachedImageTools.configuration.fadeInDuration,
        progress: Binding<Double?>? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = request?.url
        self.request = request
        self.maxPixel = maxPixel
        self.pixelUnit = pixelUnit
        self.dataFallback = dataFallback
        self.fadeInDuration = fadeInDuration
        self.progressBinding = progress
        self.imageContent = content
        self.phaseContent = nil
        self.placeholder = placeholder
        _loader = StateObject(wrappedValue: ImageLoader(url: request?.url, request: request, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback, configuration: AsyncCachedImageTools.configuration, progressBinding: progress))
    }
    
    // Phase-based initializer (URL)
    public init(
        url: URL?,
        maxPixel: Int? = nil,
        pixelUnit: AsyncCachedImagePixelUnit = .points,
        dataFallback: Data? = nil,
        fadeInDuration: TimeInterval = AsyncCachedImageTools.configuration.fadeInDuration,
        progress: Binding<Double?>? = nil,
        @ViewBuilder content: @escaping (AsyncCachedImagePhase) -> Content
    ) where Placeholder == EmptyView {
        self.url = url
        self.request = nil
        self.maxPixel = maxPixel
        self.pixelUnit = pixelUnit
        self.dataFallback = dataFallback
        self.fadeInDuration = fadeInDuration
        self.progressBinding = progress
        self.imageContent = nil
        self.phaseContent = content
        self.placeholder = nil
        _loader = StateObject(wrappedValue: ImageLoader(url: url, request: nil, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback, configuration: AsyncCachedImageTools.configuration, progressBinding: progress))
    }
    
    // Phase-based initializer (URLRequest)
    public init(
        request: URLRequest?,
        maxPixel: Int? = nil,
        pixelUnit: AsyncCachedImagePixelUnit = .points,
        dataFallback: Data? = nil,
        fadeInDuration: TimeInterval = AsyncCachedImageTools.configuration.fadeInDuration,
        progress: Binding<Double?>? = nil,
        @ViewBuilder content: @escaping (AsyncCachedImagePhase) -> Content
    ) where Placeholder == EmptyView {
        self.url = request?.url
        self.request = request
        self.maxPixel = maxPixel
        self.pixelUnit = pixelUnit
        self.dataFallback = dataFallback
        self.fadeInDuration = fadeInDuration
        self.progressBinding = progress
        self.imageContent = nil
        self.phaseContent = content
        self.placeholder = nil
        _loader = StateObject(wrappedValue: ImageLoader(url: request?.url, request: request, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback, configuration: AsyncCachedImageTools.configuration, progressBinding: progress))
    }
    
    public var body: some View {
        Group {
            if let phaseContent {
                phaseContent(loader.phase)
                    .animation(reduceMotion ? nil : .easeInOut(duration: fadeInDuration), value: loader.isShowingFinalImage)
            } else if let imageContent, let ui = loader.image {
                imageContent(Image(uiImage: ui))
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: fadeInDuration), value: loader.isShowingFinalImage)
            } else if let imageContent, let fallback = loader.fallback {
                imageContent(Image(uiImage: fallback))
            } else if let placeholder {
                placeholder()
            } else {
                EmptyView()
            }
        }
        .onAppear { loader.loadIfNeeded(displayScale: displayScale) }
        .onChange(of: displayScale) { _, scale in loader.loadIfNeeded(displayScale: scale) }
        .onChange(of: url) { _, newURL in
            loader.update(url: newURL, request: request, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback)
        }
        .onChange(of: request) { _, newReq in
            loader.update(url: newReq?.url, request: newReq, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback)
        }
        .onChange(of: maxPixel) { _, _ in
            loader.update(url: url, request: request, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: dataFallback)
        }
        .onChange(of: dataFallback) { _, newData in
            loader.update(url: url, request: request, maxPixel: maxPixel, pixelUnit: pixelUnit, dataFallback: newData)
        }
        .onDisappear { loader.cancel() }
    }
}

// MARK: - Loader + Cache
@MainActor
private final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var fallback: UIImage?
    @Published var phase: AsyncCachedImagePhase = .empty
    @Published var isShowingFinalImage: Bool = false
    
    private var task: Task<Void, Never>?
    private var currentURL: URL?
    private var currentRequest: URLRequest?
    private var currentMaxPixel: Int?
    private var currentPixelUnit: AsyncCachedImagePixelUnit = .points
    private var currentFallbackData: Data?
    private var currentDisplayScale: CGFloat = 1
    private var configuration: AsyncCachedImageConfiguration
    private var progressBinding: Binding<Double?>?
    
    init(url: URL?, request: URLRequest?, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, dataFallback: Data?, configuration: AsyncCachedImageConfiguration, progressBinding: Binding<Double?>?) {
        self.currentURL = url
        self.currentRequest = request
        self.currentMaxPixel = maxPixel
        self.currentPixelUnit = pixelUnit
        self.currentFallbackData = dataFallback
        self.configuration = configuration
        self.progressBinding = progressBinding
        if let data = dataFallback, let ui = UIImage(data: data) {
            self.fallback = ui
        }
    }
    
    func update(url: URL?, request: URLRequest?, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, dataFallback: Data?) {
        let shouldReload = url?.absoluteString != currentURL?.absoluteString
            || maxPixel != currentMaxPixel
            || pixelUnit != currentPixelUnit
            || request?.url?.absoluteString != currentRequest?.url?.absoluteString
        currentURL = url
        currentRequest = request
        currentMaxPixel = maxPixel
        currentPixelUnit = pixelUnit
        currentFallbackData = dataFallback
        if let data = dataFallback, let ui = UIImage(data: data) {
            self.fallback = ui
        } else {
            self.fallback = nil
        }
        if shouldReload {
            task?.cancel()
            image = nil
            isShowingFinalImage = false
            phase = .empty
            progressBinding?.wrappedValue = nil
            loadIfNeeded()
        }
    }
    
    func loadIfNeeded(displayScale: CGFloat? = nil) {
        if let displayScale, displayScale != currentDisplayScale {
            currentDisplayScale = max(1, displayScale)
            task?.cancel()
            image = nil
        }
        guard image == nil else { return }
        guard let url = currentURL else { return } // endast fallback
        
        let scale = Int(currentDisplayScale.rounded())
        let processedKey = cacheKeyProcessed(url: url, maxPixel: currentMaxPixel, pixelUnit: currentPixelUnit, scale: scale)
        let originalKey = cacheKeyOriginal(url: url)
        
        // Minnescache (processed)
        if let cached = MemoryImageCache.shared.image(forKey: processedKey) {
            self.image = cached
            self.phase = .success(Image(uiImage: cached))
            self.isShowingFinalImage = true
            progressBinding?.wrappedValue = 1.0
            return
        }
        
        // Asynkron laddning (disk + nät)
        task?.cancel()
        task = Task(priority: configuration.taskPriority) { [weak self] in
            guard let self else { return }
            let expectedKey = processedKey
            
            // 1) Diskcache: processed image
            if let diskImage = await DiskCache.shared.loadImage(forKey: expectedKey) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    MemoryImageCache.shared.store(image: diskImage, forKey: expectedKey)
                    if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                        self.image = diskImage
                        self.phase = .success(Image(uiImage: diskImage))
                        self.isShowingFinalImage = true
                        self.fallback = nil
                        self.progressBinding?.wrappedValue = 1.0
                    }
                }
                return
            }
            
            // 2) Diskcache: original data -> downsample/decode
            if let originalData = await DiskCache.shared.loadData(forKey: originalKey) {
                if Task.isCancelled { return }
                if let processed = await downsampledImage(data: originalData, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: CGFloat(scale)) {
                    if Task.isCancelled { return }
                    await DiskCache.shared.storeImage(processed, forKey: expectedKey)
                    await MainActor.run {
                        MemoryImageCache.shared.store(image: processed, forKey: expectedKey)
                        if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                            self.image = processed
                            self.phase = .success(Image(uiImage: processed))
                            self.isShowingFinalImage = true
                            self.fallback = nil
                            self.progressBinding?.wrappedValue = 1.0
                        }
                    }
                    return
                } else if let ui = UIImage(data: originalData) {
                    await DiskCache.shared.storeImage(ui, forKey: expectedKey)
                    await MainActor.run {
                        MemoryImageCache.shared.store(image: ui, forKey: expectedKey)
                        if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                            self.image = ui
                            self.phase = .success(Image(uiImage: ui))
                            self.isShowingFinalImage = true
                            self.fallback = nil
                            self.progressBinding?.wrappedValue = 1.0
                        }
                    }
                    return
                }
            }
            
            // 3) Nätverk
            do {
                // Om vi har en progressBinding: använd bytes(for:) och rapportera progress. Annars koalescera.
                if let progressBinding = self.progressBinding {
                    let req = self.currentRequest ?? URLRequest(url: url)
                    let (bytes, response) = try await self.configuration.session.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    let expected = response.expectedContentLength
                    var received = 0
                    var reportedBytes = 0
                    var collected: [UInt8] = []
                    if expected > 0 {
                        collected.reserveCapacity(Int(expected))
                        await MainActor.run {
                            self.phase = .progress(0.0)
                            progressBinding.wrappedValue = 0.0
                        }
                    }
                    
                    for try await byte in bytes {
                        if Task.isCancelled { return }
                        collected.append(byte)
                        received += 1
                        if expected > 0 && (received - reportedBytes >= max(16_384, Int(expected / 100)) || received == expected) {
                            reportedBytes = received
                            let p = min(1.0, Double(received) / Double(expected))
                            await MainActor.run {
                                self.phase = .progress(p)
                                progressBinding.wrappedValue = p
                            }
                        }
                    }
                    
                    let buffer = Data(collected)
                    
                    // Lagra originaldata oförändrad
                    await DiskCache.shared.storeData(buffer, forKey: originalKey)
                    
                    if let processed = await downsampledImage(data: buffer, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: CGFloat(scale)) {
                        if Task.isCancelled { return }
                        await DiskCache.shared.storeImage(processed, forKey: expectedKey)
                        await MainActor.run {
                            MemoryImageCache.shared.store(image: processed, forKey: expectedKey)
                            if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                                self.image = processed
                                self.phase = .success(Image(uiImage: processed))
                                self.isShowingFinalImage = true
                                self.fallback = nil
                                progressBinding.wrappedValue = 1.0
                            }
                        }
                    } else if let ui = UIImage(data: buffer) {
                        await DiskCache.shared.storeImage(ui, forKey: expectedKey)
                        await MainActor.run {
                            MemoryImageCache.shared.store(image: ui, forKey: expectedKey)
                            if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                                self.image = ui
                                self.phase = .success(Image(uiImage: ui))
                                self.isShowingFinalImage = true
                                self.fallback = nil
                                progressBinding.wrappedValue = 1.0
                            }
                        }
                    }
                } else {
                    // Koalescerad fetch (snabbast när man inte behöver progress)
                    let data: Data
                    if let req = self.currentRequest {
                        data = try await RequestCoalescer.shared.fetch(request: req, session: self.configuration.session, retries: self.configuration.retryCount, delay: self.configuration.retryDelay)
                    } else {
                        data = try await RequestCoalescer.shared.fetch(url: url, session: self.configuration.session, retries: self.configuration.retryCount, delay: self.configuration.retryDelay)
                    }
                    if Task.isCancelled { return }
                    
                    await DiskCache.shared.storeData(data, forKey: originalKey)
                    
                    if let processed = await downsampledImage(data: data, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: CGFloat(scale)) {
                        if Task.isCancelled { return }
                        await DiskCache.shared.storeImage(processed, forKey: expectedKey)
                        await MainActor.run {
                            MemoryImageCache.shared.store(image: processed, forKey: expectedKey)
                            if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                                self.image = processed
                                self.phase = .success(Image(uiImage: processed))
                                self.isShowingFinalImage = true
                                self.fallback = nil
                                self.progressBinding?.wrappedValue = 1.0
                            }
                        }
                    } else if let ui = UIImage(data: data) {
                        await DiskCache.shared.storeImage(ui, forKey: expectedKey)
                        await MainActor.run {
                            MemoryImageCache.shared.store(image: ui, forKey: expectedKey)
                            if expectedKey == self.makeCacheKeyProcessed(url: self.currentURL ?? url, maxPixel: self.currentMaxPixel, pixelUnit: self.currentPixelUnit, scale: scale) {
                                self.image = ui
                                self.phase = .success(Image(uiImage: ui))
                                self.isShowingFinalImage = true
                                self.fallback = nil
                                self.progressBinding?.wrappedValue = 1.0
                            }
                        }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.phase = .failure(error)
                }
            }
        }
    }
    
    func cancel() {
        task?.cancel()
    }
    
    // Renamed to avoid clashing with the free functions and to prevent accidental recursion.
    private func makeCacheKeyOriginal(url: URL) -> String {
        cacheKeyOriginal(url: url)
    }
    
    private func makeCacheKeyProcessed(url: URL, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, scale: Int) -> String {
        guard currentURL != nil else { return "" }
        return cacheKeyProcessed(url: url, maxPixel: maxPixel, pixelUnit: pixelUnit, scale: Int(currentDisplayScale.rounded()))
    }
}

// MARK: - Helpers for keys (shared)
private func cacheKeyOriginal(url: URL) -> String {
    url.absoluteString // stabiliseras av sha i DiskCache
}

private func cacheKeyProcessed(url: URL, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, scale: Int) -> String {
    let unitTag: String = {
        switch pixelUnit {
        case .points: return "pt"
        case .pixels: return "px"
        }
    }()
    if let m = maxPixel {
        switch pixelUnit {
        case .points:
            return "\(url.absoluteString)#p=\(m)\(unitTag)@\(scale)x"
        case .pixels:
            return "\(url.absoluteString)#p=\(m)\(unitTag)"
        }
    }
    // Ingen maxPixel: markera vilken skalenhet som gällde
    switch pixelUnit {
    case .points: return "\(url.absoluteString)#orig@\(scale)x"
    case .pixels: return "\(url.absoluteString)#origpx"
    }
}

// MARK: - Memory cache
// NSCache synchronizes access; the observer is installed only during initialization.
private final class MemoryImageCache: @unchecked Sendable {
    static let shared = MemoryImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var didSetUpWarningObserver = false
    
    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 128 * 1024 * 1024 // ~128 MB
        setupMemoryWarningObserver()
    }
    
    private func setupMemoryWarningObserver() {
        guard !didSetUpWarningObserver else { return }
        didSetUpWarningObserver = true
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }
    
    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func store(image: UIImage, forKey key: String) {
        let scale = image.scale
        let pixels = Int(image.size.width * scale) * Int(image.size.height * scale)
        let cost = pixels * 4 // 4 bytes per pixel (RGBA)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func removeAll() {
        cache.removeAllObjects()
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

private final class ImageConfigurationStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var value = AsyncCachedImageConfiguration()

    func get() -> AsyncCachedImageConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: AsyncCachedImageConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}

// MARK: - Disk cache with configurable TTL + LRU
private actor DiskCache {
    static let shared = DiskCache()

    private struct Record: Codable {
        let storedAt: Date
        var lastAccess: Date
        let size: Int
    }

    private let folderURL: URL
    private let fm = FileManager.default
    private let now: @Sendable () -> Date
    private var records: [String: Record] = [:]
    private var totalBytes = 0
    private var indexLoaded = false
    private var maintenanceTask: Task<Void, Never>?
    private var ttl: TimeInterval = 7 * 24 * 60 * 60
    private var maxSizeBytes: Int = 200 * 1024 * 1024

    // Internal injection keeps disk policy independently testable without the UI.
    init(folderURL: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = folderURL ?? base.appendingPathComponent("ImageCache", isDirectory: true)
        self.folderURL = folder
        self.now = now
        Self.prepareDirectory(folder)
    }

    func configure(ttl: TimeInterval, maxSizeBytes: Int) {
        self.ttl = max(60, ttl)
        self.maxSizeBytes = max(1 * 1024 * 1024, maxSizeBytes)
        ensureIndex()
        scheduleMaintenance()
    }

    func loadImage(forKey key: String) -> UIImage? {
        guard let data = loadData(at: imageFileURL(forKey: key)) else { return nil }
        return UIImage(data: data)
    }

    func storeImage(_ image: UIImage, forKey key: String) {
        let data = imageHasAlpha(image) ? image.pngData() : image.jpegData(compressionQuality: 0.9)
        guard let data else { return }
        storeData(data, at: imageFileURL(forKey: key))
    }

    func loadData(forKey key: String) -> Data? {
        loadData(at: dataFileURL(forKey: key))
    }

    func storeData(_ data: Data, forKey key: String) {
        storeData(data, at: dataFileURL(forKey: key))
    }

    func remove(forKey key: String) {
        ensureIndex()
        for url in [imageFileURL(forKey: key), dataFileURL(forKey: key)] {
            removeFile(named: url.lastPathComponent)
        }
        scheduleMaintenance()
    }

    func removeAll() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        try? fm.removeItem(at: folderURL)
        Self.prepareDirectory(folderURL)
        records.removeAll()
        totalBytes = 0
        indexLoaded = true
    }

    private func imageFileURL(forKey key: String) -> URL {
        folderURL.appendingPathComponent(sha256(key)).appendingPathExtension("img")
    }
    
    private func dataFileURL(forKey key: String) -> URL {
        folderURL.appendingPathComponent(sha256(key)).appendingPathExtension("bin")
    }
    
    private func loadData(at url: URL) -> Data? {
        ensureIndex()
        let name = url.lastPathComponent
        guard var record = records[name] else { return nil }
        guard now().timeIntervalSince(record.storedAt) < ttl,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            removeFile(named: name)
            scheduleMaintenance()
            return nil
        }
        // Access affects eviction order, never the original freshness deadline.
        record.lastAccess = now()
        records[name] = record
        scheduleMaintenance()
        return data
    }

    private func storeData(_ data: Data, at url: URL) {
        ensureIndex()
        guard data.count <= maxSizeBytes else { return }
        do {
            try data.write(to: url, options: .atomic)
            let date = now()
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            let name = url.lastPathComponent
            totalBytes -= records[name]?.size ?? 0
            records[name] = Record(storedAt: date, lastAccess: date, size: data.count)
            totalBytes += data.count
            // Bound temporary overflow during a long burst without a filesystem scan.
            if totalBytes > maxSizeBytes + maxSizeBytes / 4 { trim() }
            scheduleMaintenance()
        } catch {
            // Cache writes are optional; a removed cache directory is recreated.
            Self.prepareDirectory(folderURL)
        }
    }

    private var indexURL: URL { folderURL.appendingPathComponent(".index.json") }

    private func ensureIndex() {
        guard !indexLoaded else { return }
        indexLoaded = true
        let saved = (try? Data(contentsOf: indexURL)).flatMap {
            try? JSONDecoder().decode([String: Record].self, from: $0)
        } ?? [:]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        // Reconcile once per process, including legacy files and an interrupted index write.
        for url in files where ["img", "bin"].contains(url.pathExtension) {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let storedAt = values.contentModificationDate, let size = values.fileSize
            else { continue }
            let name = url.lastPathComponent
            let previous = saved[name]
            let matches = previous?.size == size && abs((previous?.storedAt ?? .distantPast).timeIntervalSince(storedAt)) < 1
            records[name] = Record(storedAt: storedAt, lastAccess: matches ? previous!.lastAccess : storedAt, size: size)
            totalBytes += size
        }
        trim()
    }

    private func scheduleMaintenance() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.performMaintenance()
        }
    }

    private func performMaintenance() {
        maintenanceTask = nil
        trim()
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func trim() {
        let date = now()
        for (name, record) in records where date.timeIntervalSince(record.storedAt) >= ttl {
            removeFile(named: name)
        }
        guard totalBytes > maxSizeBytes else { return }
        let target = maxSizeBytes * 9 / 10
        for (name, _) in records.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard totalBytes > target else { break }
            removeFile(named: name)
        }
    }

    private func removeFile(named name: String) {
        try? fm.removeItem(at: folderURL.appendingPathComponent(name))
        totalBytes -= records.removeValue(forKey: name)?.size ?? 0
    }

    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
    
    private nonisolated static func prepareDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var u = url
        var res = URLResourceValues()
        res.isExcludedFromBackup = true
        try? u.setResourceValues(res)
    }
    
    private func sha256(_ s: String) -> String {
        guard let data = s.data(using: .utf8) else { return UUID().uuidString }
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
        #else
        // Stabil fallback: Base64 utan slashar
        return data.base64EncodedString().replacingOccurrences(of: "/", with: "_")
        #endif
    }
}

// MARK: - Request coalescing
private actor RequestCoalescer {
    static let shared = RequestCoalescer()
    private var inFlight: [URL: Task<Data, Error>] = [:]
    
    func fetch(url: URL, session: URLSession, retries: Int, delay: TimeInterval) async throws -> Data {
        if let task = inFlight[url] {
            return try await task.value
        }
        let task = Task<Data, Error> {
            defer { self.remove(url) }
            return try await fetchWithRetry(url: url, session: session, retries: retries, delay: delay)
        }
        inFlight[url] = task
        return try await task.value
    }
    
    func fetch(request: URLRequest, session: URLSession, retries: Int, delay: TimeInterval) async throws -> Data {
        guard let url = request.url else { throw URLError(.badURL) }
        if let task = inFlight[url] {
            return try await task.value
        }
        let task = Task<Data, Error> {
            defer { self.remove(url) }
            return try await fetchWithRetry(request: request, session: session, retries: retries, delay: delay)
        }
        inFlight[url] = task
        return try await task.value
    }
    
    private func remove(_ url: URL) {
        inFlight[url] = nil
    }
}

// MARK: - Downsampling helper
private func downsampledImage(data: Data, maxPixel: Int?, pixelUnit: AsyncCachedImagePixelUnit, scale: CGFloat) async -> UIImage? {
    guard let maxPixel, maxPixel > 0 else {
        return UIImage(data: data)
    }
    return await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
                cont.resume(returning: UIImage(data: data))
                return
            }
            let target: Int
            switch pixelUnit {
            case .points:
                target = Int(CGFloat(maxPixel) * max(1, scale))
            case .pixels:
                target = maxPixel
            }
            let downOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: target
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, downOptions as CFDictionary) {
                cont.resume(returning: UIImage(cgImage: cg, scale: scale, orientation: .up))
            } else {
                cont.resume(returning: UIImage(data: data))
            }
        }
    }
}

// MARK: - Networking with retry
private func fetchWithRetry(url: URL, session: URLSession, retries: Int, delay: TimeInterval) async throws -> Data {
    var attempts = 0
    var lastError: Error?
    while attempts <= retries {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                struct HTTPError: LocalizedError { let code: Int; var errorDescription: String? { "HTTP \(code)" } }
                throw HTTPError(code: http.statusCode)
            }
            return data
        } catch {
            lastError = error
            attempts += 1
            if attempts > retries { break }
            try? await Task.sleep(nanoseconds: UInt64((delay * pow(2, Double(attempts - 1))) * 1_000_000_000))
        }
    }
    throw lastError ?? URLError(.unknown)
}

private func fetchWithRetry(request: URLRequest, session: URLSession, retries: Int, delay: TimeInterval) async throws -> Data {
    var attempts = 0
    var lastError: Error?
    while attempts <= retries {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                struct HTTPError: LocalizedError { let code: Int; var errorDescription: String? { "HTTP \(code)" } }
                throw HTTPError(code: http.statusCode)
            }
            return data
        } catch {
            lastError = error
            attempts += 1
            if attempts > retries { break }
            try? await Task.sleep(nanoseconds: UInt64((delay * pow(2, Double(attempts - 1))) * 1_000_000_000))
        }
    }
    throw lastError ?? URLError(.unknown)
}
