import CoreFoundation
import Foundation

enum ScreenshotLocationResolver {
    static func currentLocation() -> URL {
        if let location = CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String,
           location.isEmpty == false {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }

        let picturesScreenshots = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Screenshots", isDirectory: true)

        if let picturesScreenshots,
           FileManager.default.fileExists(atPath: picturesScreenshots.path) {
            return picturesScreenshots
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
