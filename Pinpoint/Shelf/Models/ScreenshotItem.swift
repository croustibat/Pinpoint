import Foundation

struct ScreenshotItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let filename: String
    let createdAt: Date
    let fileExtension: String

    init(url: URL, createdAt: Date) {
        self.id = url
        self.url = url
        self.filename = url.lastPathComponent
        self.createdAt = createdAt
        self.fileExtension = url.pathExtension.lowercased()
    }
}
