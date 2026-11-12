import AppKit
import ImageIO

final class CaptureHistory {
    private let directory: URL
    private let files: FileManager
    private let writeData: (Data, URL) throws -> Void
    private let lock = NSRecursiveLock()
    private final class ThumbnailEntry {
        let image: NSImage
        let modified: Date?
        let size: Int?
        init(image: NSImage, modified: Date?, size: Int?) {
            self.image = image
            self.modified = modified
            self.size = size
        }
    }
    private let thumbnails = NSCache<NSURL, ThumbnailEntry>()
    private var storedLimit = 10
    private var clearGeneration = 0
    var limit: Int {
        get { lock.lock(); defer { lock.unlock() }; return storedLimit }
        set { lock.lock(); defer { lock.unlock() }; storedLimit = newValue }
    }

    init(directory: URL? = nil, files: FileManager = .default,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.files = files
        self.writeData = writeData
        self.directory = directory ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klik", isDirectory: true)
            .appendingPathComponent("Recent Captures", isDirectory: true)
    }

    func entries() throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        guard files.fileExists(atPath: directory.path) else { return [] }
        let urls = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.filter { $0.lastPathComponent.hasPrefix("capture-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func record(_ png: Data) throws {
        lock.lock()
        let initialGeneration = clearGeneration
        let enabled = storedLimit > 0
        lock.unlock()
        guard enabled else { return }
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let filename = String(format: "capture-%020lld-%@.png", timestamp, UUID().uuidString)
        let url = directory.appendingPathComponent(filename)
        let temporary = directory.appendingPathComponent(".capture-\(UUID().uuidString).tmp")
        defer { try? files.removeItem(at: temporary) }
        try writeData(png, temporary)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        lock.lock()
        defer { lock.unlock() }
        // Do not resurrect an item after history was cleared or disabled.
        guard initialGeneration == clearGeneration, storedLimit > 0 else { return }
        try files.moveItem(at: temporary, to: url)
        try enforceLimit()
    }

    func enforceLimit() throws {
        lock.lock()
        defer { lock.unlock() }
        guard limit > 0 else { return }
        for old in try entries().dropFirst(limit) {
            try files.removeItem(at: old)
            thumbnails.removeObject(forKey: old as NSURL)
        }
    }

    func remove(_ url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard try entries().contains(url) else { throw CocoaError(.fileNoSuchFile) }
        try files.removeItem(at: url)
        thumbnails.removeObject(forKey: url as NSURL)
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        clearGeneration &+= 1
        for url in try entries() {
            try files.removeItem(at: url)
            thumbnails.removeObject(forKey: url as NSURL)
        }
    }

    func clipboardData(_ url: URL) throws -> (Data, Data?) {
        let png = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (png, ClipboardImage.tiff(image))
    }

    func copy(_ url: URL, to pasteboard: NSPasteboard = .general) throws {
        let (png, tiff) = try clipboardData(url)
        guard ClipboardImage.write(png: png, tiff: tiff, to: pasteboard) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func preview(_ url: URL, maxPixelSize: Int = 1024) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    func thumbnail(_ url: URL) -> NSImage? {
        let attributes = try? files.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue
        if let cached = thumbnails.object(forKey: url as NSURL), attributes != nil,
           cached.modified == modified, cached.size == fileSize {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
              ] as CFDictionary) else { return nil }
        let scale = min(48.0 / CGFloat(image.width), 36.0 / CGFloat(image.height))
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) * scale,
                                                          height: CGFloat(image.height) * scale))
        if attributes != nil {
            thumbnails.setObject(ThumbnailEntry(image: thumbnail, modified: modified,
                                                size: fileSize), forKey: url as NSURL)
        }
        return thumbnail
    }
}

struct HistoryDateFormatter {
    static func label(for url: URL, strings: AppStrings, now: Date = Date(),
                      calendar: Calendar = .current) -> String {
        let parts = url.lastPathComponent.split(separator: "-")
        guard parts.count > 1, let micros = Double(parts[1]) else { return url.lastPathComponent }
        let date = Date(timeIntervalSince1970: micros / 1_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: strings.language.rawValue)
        formatter.calendar = calendar
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = strings(.historyToday)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            day = strings(.historyYesterday)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            day = formatter.string(from: date)
        }
        return "\(day)  \(time)"
    }
}

enum ClipboardImage {
    static func write(png: Data, image: CGImage, to pasteboard: NSPasteboard) -> Bool {
        write(png: png, tiff: tiff(image), to: pasteboard)
    }

    static func tiff(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).tiffRepresentation
    }

    static func write(png: Data, tiff: Data?, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        if let tiff {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
