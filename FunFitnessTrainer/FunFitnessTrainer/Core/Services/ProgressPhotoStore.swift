import Foundation
import UIKit

struct ProgressPhotoRecord: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let capturedAt: Date
    var isBaseline: Bool
    let fileName: String
}

/// On-device day-one and weekly progress photos. Nothing is uploaded.
@MainActor
final class ProgressPhotoStore: ObservableObject {
    static let shared = ProgressPhotoStore()

    @Published private(set) var photos: [ProgressPhotoRecord] = []

    private let indexKey = "progressPhotoIndex"
    private let folderName = "ProgressPhotos"

    private init() {
        photos = loadIndex().sorted { $0.capturedAt > $1.capturedAt }
    }

    var baseline: ProgressPhotoRecord? {
        photos.first(where: \.isBaseline)
            ?? photos.min(by: { $0.capturedAt < $1.capturedAt })
    }

    var latest: ProgressPhotoRecord? {
        photos.max(by: { $0.capturedAt < $1.capturedAt })
    }

    var hasBaseline: Bool {
        photos.contains(where: \.isBaseline) || !photos.isEmpty
    }

    func hasPhotoThisWeek(now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
        return photos.contains { weekInterval.contains($0.capturedAt) }
    }

    @discardableResult
    func add(image: UIImage, isBaseline: Bool = false, capturedAt: Date = Date()) -> ProgressPhotoRecord? {
        guard let data = Self.jpegData(from: image) else { return nil }

        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let url = folderURL().appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        var next = photos
        let makeBaseline = isBaseline || next.isEmpty
        if makeBaseline {
            for index in next.indices {
                next[index].isBaseline = false
            }
        }

        let record = ProgressPhotoRecord(
            id: id,
            capturedAt: capturedAt,
            isBaseline: makeBaseline,
            fileName: fileName
        )
        next.insert(record, at: 0)
        photos = next.sorted { $0.capturedAt > $1.capturedAt }
        persistIndex()
        return record
    }

    func delete(_ record: ProgressPhotoRecord) {
        let url = folderURL().appendingPathComponent(record.fileName)
        try? FileManager.default.removeItem(at: url)
        photos.removeAll { $0.id == record.id }
        persistIndex()
    }

    func image(for record: ProgressPhotoRecord) -> UIImage? {
        let url = folderURL().appendingPathComponent(record.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func folderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func loadIndex() -> [ProgressPhotoRecord] {
        guard let data = UserDefaults.standard.data(forKey: indexKey) else { return [] }
        return (try? JSONDecoder().decode([ProgressPhotoRecord].self, from: data)) ?? []
    }

    private func persistIndex() {
        if let data = try? JSONEncoder().encode(photos) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }

    private static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: 0.72) }

        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.72)
    }
}
