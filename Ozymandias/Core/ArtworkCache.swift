import CryptoKit
import ImageIO
import UIKit

/// Cache de duas camadas para as artes, com deduplicação das requisições em voo.
/// A memória evita rebaixar a mesma imagem enquanto a lista rola; o disco evita
/// rebaixar o acervo inteiro de novo a cada lançamento do app.
actor ArtworkCache {
  static let shared = ArtworkCache()

  private let images = NSCache<NSString, UIImage>()
  private let directory: URL
  private let diskByteLimit: Int
  private var inFlight: [String: Task<UIImage?, Never>] = [:]
  private var didPrune = false

  init(
    countLimit: Int = 300,
    memoryByteLimit: Int = 96 * 1024 * 1024,
    diskByteLimit: Int = 256 * 1024 * 1024,
    directory: URL? = nil
  ) {
    images.countLimit = countLimit
    images.totalCostLimit = memoryByteLimit
    self.diskByteLimit = diskByteLimit
    self.directory =
      directory
      ?? URL.cachesDirectory.appending(path: "Artwork", directoryHint: .isDirectory)
  }

  func image(
    for key: String,
    maximumPixelSize: CGFloat,
    load: @escaping @Sendable () async throws -> Data
  ) async -> UIImage? {
    if let cached = images.object(forKey: key as NSString) { return cached }
    if let running = inFlight[key] { return await running.value }

    pruneOnce()
    let fileURL = fileURL(for: key)
    let task = Task<UIImage?, Never> {
      if let stored = try? Data(contentsOf: fileURL), let image = UIImage(data: stored) {
        return image
      }
      guard let data = try? await load(),
        let image = Self.downsample(data, maximumPixelSize: maximumPixelSize)
      else { return nil }
      Self.store(image, at: fileURL)
      return image
    }

    inFlight[key] = task
    let image = await task.value
    inFlight.removeValue(forKey: key)

    if let image {
      images.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }
    return image
  }

  /// Chamado ao sair da conta e quando o conteúdo muda no servidor: as artes são
  /// específicas do servidor, do token e do estado dos metadados.
  func clear() {
    images.removeAllObjects()
    for task in inFlight.values { task.cancel() }
    inFlight.removeAll()
    try? FileManager.default.removeItem(at: directory)
  }

  private func fileURL(for key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: digest, directoryHint: .notDirectory)
  }

  /// Uma varredura por sessão basta: o cache cresce devagar e o objetivo é só
  /// impedir que ele engula o armazenamento do aparelho.
  private func pruneOnce() {
    guard !didPrune else { return }
    didPrune = true
    let directory = directory
    let limit = diskByteLimit
    Task.detached(priority: .utility) { Self.prune(directory, to: limit) }
  }

  private static func prune(_ directory: URL, to byteLimit: Int) {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: keys)
    else { return }

    let described = entries.compactMap { url -> (URL, Date, Int)? in
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        let modified = values.contentModificationDate,
        let size = values.fileSize
      else { return nil }
      return (url, modified, size)
    }

    var total = described.reduce(0) { $0 + $1.2 }
    guard total > byteLimit else { return }
    for entry in described.sorted(by: { $0.1 < $1.1 }) {
      guard total > byteLimit else { break }
      try? FileManager.default.removeItem(at: entry.0)
      total -= entry.2
    }
  }

  private static func store(_ image: UIImage, at url: URL) {
    guard let encoded = image.jpegData(compressionQuality: 0.9) else { return }
    try? encoded.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  /// Redimensiona no decode em vez de carregar o bitmap inteiro na memória.
  private static func downsample(_ data: Data, maximumPixelSize: CGFloat) -> UIImage? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }

    let options =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: max(maximumPixelSize, 1),
      ] as [CFString: Any] as CFDictionary

    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
      return UIImage(data: data)
    }
    return UIImage(cgImage: thumbnail)
  }

  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else { return 0 }
    return cgImage.bytesPerRow * cgImage.height
  }
}
