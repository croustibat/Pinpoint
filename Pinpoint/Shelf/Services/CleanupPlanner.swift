import CoreServices
import CryptoKit
import Foundation
import ImageIO

/// How the cleanup sheet picks screenshots: a fixed set of heuristics, or the
/// user's own age threshold.
enum CleanupMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case custom

    var id: String { rawValue }
}

struct CleanupCriteria: Equatable, Sendable {
    var mode: CleanupMode = .smart
    /// Custom mode: minimum age, in days.
    var minimumAgeDays = 30
    /// Custom mode: skip anything that was opened again after being taken.
    var neverReopenedOnly = false
    /// Custom mode: skip images macOS didn't produce as screenshots. Always on
    /// in smart mode — the watched folder may well be the Desktop.
    var screenshotsOnly = true

    static let ageChoices = [7, 30, 90, 180, 365]
}

/// Why a screenshot is proposed, in the order the sheet lists them. A capture
/// matching several reasons is filed under the first one.
enum CleanupReason: Int, CaseIterable, Identifiable, Sendable {
    /// Same bytes as another capture, which is kept.
    case duplicate
    /// Taken seconds before another capture of the same burst — a retake.
    case burst
    /// Past the age threshold and never opened again.
    case stale
    /// Past the age threshold.
    case old

    var id: Int { rawValue }
}

struct CleanupCandidate: Identifiable, Sendable {
    let item: ScreenshotItem
    let reason: CleanupReason
    let fileSize: Int64

    var id: URL { item.id }
}

/// Picks the screenshots worth moving to the Trash. Pure and synchronous —
/// call it off the main actor, it reads file metadata and may hash files.
///
/// Never proposed, whatever the mode: favorites and captures given a custom
/// title (both are the user saying "keep this"). Smart mode also leaves alone
/// the last week and anything macOS didn't take as a screenshot.
enum CleanupPlanner {
    /// Smart mode thresholds.
    static let recentDays = 7
    static let staleDays = 30
    static let oldDays = 90
    /// Two captures closer than this belong to the same burst.
    static let burstGap: TimeInterval = 30

    static func plan(
        items: [ScreenshotItem],
        protectedPaths: Set<String>,
        criteria: CleanupCriteria,
        now: Date = .now
    ) -> [CleanupCandidate] {
        let facts = Dictionary(uniqueKeysWithValues: items.map { ($0.url, ScreenshotFacts(url: $0.url)) })
        let screenshotsOnly = criteria.mode == .smart || criteria.screenshotsOnly
        let pool = items.filter { item in
            screenshotsOnly == false || facts[item.url]?.isScreenshot == true
        }

        func isProtected(_ item: ScreenshotItem) -> Bool {
            protectedPaths.contains(item.url.path)
                || (criteria.mode == .smart && age(of: item, now: now) < days(recentDays))
        }

        var reasons: [URL: CleanupReason] = [:]
        func propose(_ item: ScreenshotItem, _ reason: CleanupReason) {
            guard isProtected(item) == false, reasons[item.url] == nil else { return }
            reasons[item.url] = reason
        }

        switch criteria.mode {
        case .smart:
            for item in duplicates(in: pool, facts: facts, isProtected: isProtected) {
                propose(item, .duplicate)
            }
            // A retake that was opened again was useful after all.
            for item in burstRetakes(in: pool) where facts[item.url]?.neverReopened == true {
                propose(item, .burst)
            }
            for item in pool {
                let itemAge = age(of: item, now: now)
                if itemAge >= days(staleDays), facts[item.url]?.neverReopened == true {
                    propose(item, .stale)
                } else if itemAge >= days(oldDays) {
                    propose(item, .old)
                }
            }

        case .custom:
            for item in pool where age(of: item, now: now) >= days(criteria.minimumAgeDays) {
                let neverReopened = facts[item.url]?.neverReopened == true
                if criteria.neverReopenedOnly, neverReopened == false { continue }
                propose(item, neverReopened ? .stale : .old)
            }
        }

        return items.compactMap { item in
            reasons[item.url].map {
                CleanupCandidate(item: item, reason: $0, fileSize: facts[item.url]?.fileSize ?? 0)
            }
        }
    }

    // MARK: - Heuristics

    /// Every capture but one per group of identical files. Sizes are compared
    /// first so only same-size files are ever read and hashed.
    private static func duplicates(
        in items: [ScreenshotItem],
        facts: [URL: ScreenshotFacts],
        isProtected: (ScreenshotItem) -> Bool
    ) -> [ScreenshotItem] {
        let bySize = Dictionary(grouping: items) { facts[$0.url]?.fileSize ?? 0 }
        var extras: [ScreenshotItem] = []

        for (size, sameSize) in bySize where size > 0 && sameSize.count > 1 {
            let byHash = Dictionary(grouping: sameSize) { contentHash(of: $0.url) }
            for (hash, group) in byHash where hash != nil && group.count > 1 {
                // Keep a copy the user protected if there is one, else the newest.
                let kept = group.first(where: isProtected) ?? group.max { $0.createdAt < $1.createdAt }
                extras += group.filter { $0.url != kept?.url }
            }
        }
        return extras
    }

    /// Every capture of a burst except its last one: when shots follow each
    /// other within `burstGap`, the earlier ones are usually retakes.
    private static func burstRetakes(in items: [ScreenshotItem]) -> [ScreenshotItem] {
        let chronological = items.sorted { $0.createdAt < $1.createdAt }
        return zip(chronological, chronological.dropFirst()).compactMap { current, next in
            next.createdAt.timeIntervalSince(current.createdAt) < burstGap ? current : nil
        }
    }

    private static func contentHash(of url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return Data(SHA256.hash(data: data))
    }

    private static func age(of item: ScreenshotItem, now: Date) -> TimeInterval {
        now.timeIntervalSince(item.createdAt)
    }

    private static func days(_ count: Int) -> TimeInterval {
        TimeInterval(count) * 86_400
    }
}

/// What the planner needs to know about a file beyond its date.
private struct ScreenshotFacts {
    let fileSize: Int64
    /// Whether macOS took it as a screenshot.
    let isScreenshot: Bool
    /// Nil when Spotlight can't say — an unindexed volume, for instance. Never
    /// treated as "never reopened": unknown usage proposes nothing.
    let neverReopened: Bool?

    init(url: URL) {
        fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        let metadata = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL)
        func attribute(_ name: String) -> Any? {
            metadata.flatMap { MDItemCopyAttribute($0, name as CFString) }
        }

        // Spotlight flags screenshots, and macOS also stamps "Screenshot" in
        // the image's EXIF comment — the fallback when Spotlight is off. The
        // crops the editor writes beside a shelf file carry neither, but they
        // are screenshots all the same.
        isScreenshot = (attribute("kMDItemIsScreenCapture") as? Bool) == true
            || Self.isEditorCrop(url)
            || Self.hasScreenshotComment(url)

        // A screenshot starts with a use count of 1: the capture itself. No
        // count at all means Spotlight never saw the file, not that it's unused.
        neverReopened = (attribute("kMDItemUseCount") as? Int).map { $0 <= 1 }
    }

    /// `<stem>-cropped.png`, `-cropped-2.png`… — the naming of
    /// `AppDelegate.uniqueCroppedURL(nextTo:)`.
    private static func isEditorCrop(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "png"
            && url.deletingPathExtension().lastPathComponent
                .range(of: #"-cropped(-\d+)?$"#, options: .regularExpression) != nil
    }

    private static func hasScreenshotComment(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return false }
        return (exif[kCGImagePropertyExifUserComment] as? String) == "Screenshot"
    }
}
