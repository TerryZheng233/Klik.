import AppKit
import ImageIO

final class CaptureHistory {
    private let directory: URL
    private let files: FileManager
    var limit = 10

    init(directory: URL? = nil, files: FileManager = .default) {
        self.files = files
        self.directory = directory ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klik", isDirectory: true)
            .appendingPathComponent("Recent Captures", isDirectory: true)
    }

    func entries() throws -> [URL] {
        guard files.fileExists(atPath: directory.path) else { return [] }
        let urls = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.filter { $0.lastPathComponent.hasPrefix("capture-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func record(_ png: Data) throws {
        guard limit > 0 else { return }
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let filename = String(format: "capture-%020lld-%@.png", timestamp, UUID().uuidString)
        let url = directory.appendingPathComponent(filename)
        try png.write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try enforceLimit()
    }

    func enforceLimit() throws {
        guard limit > 0 else { return }
        for old in try entries().dropFirst(limit) {
            try files.removeItem(at: old)
        }
    }

    func clear() throws {
        for url in try entries() {
            try files.removeItem(at: url)
        }
    }

    func copy(_ url: URL, to pasteboard: NSPasteboard = .general) throws {
        let png = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              ClipboardImage.write(png: png, image: image, to: pasteboard) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
              ] as CFDictionary) else { return nil }
        let scale = min(48.0 / CGFloat(image.width), 36.0 / CGFloat(image.height))
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) * scale,
                                                    height: CGFloat(image.height) * scale))
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
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
