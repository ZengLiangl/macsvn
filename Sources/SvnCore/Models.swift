import Foundation

public enum BadgeKind: String, Codable, Equatable {
    case conflict
    case missing
    case modified
    case added
    case deleted
    case unversioned
    case locked

    public var rank: Int {
        switch self {
        case .conflict: return 7
        case .missing: return 6
        case .modified: return 5
        case .added: return 4
        case .deleted: return 3
        case .unversioned: return 2
        case .locked: return 1
        }
    }

    public static func from(item: String, hasLock: Bool) -> BadgeKind? {
        switch item {
        case "conflicted", "obstructed", "incomplete":
            return .conflict
        case "missing":
            return .missing
        case "modified", "merged", "replaced":
            return .modified
        case "added":
            return .added
        case "deleted":
            return .deleted
        case "unversioned":
            return .unversioned
        case "normal", "none", "external", "ignored":
            return hasLock ? .locked : nil
        default:
            return hasLock ? .locked : nil
        }
    }
}

public struct StatusEntry: Equatable {
    public var path: String
    public var item: String
    public var badge: BadgeKind?

    public init(path: String, item: String, badge: BadgeKind?) {
        self.path = path
        self.item = item
        self.badge = badge
    }
}

public struct RepositoryInfo: Equatable {
    public var path: String
    public var url: String
    public var revision: String
    public var repositoryRoot: String
    public var relativeURL: String
    public var schedule: String
    public var depth: String
    public var wcRoot: String

    public init(
        path: String = "",
        url: String = "",
        revision: String = "",
        repositoryRoot: String = "",
        relativeURL: String = "",
        schedule: String = "",
        depth: String = "",
        wcRoot: String = ""
    ) {
        self.path = path
        self.url = url
        self.revision = revision
        self.repositoryRoot = repositoryRoot
        self.relativeURL = relativeURL
        self.schedule = schedule
        self.depth = depth
        self.wcRoot = wcRoot
    }
}

public struct LogEntry: Equatable {
    public var revision: String
    public var author: String
    public var date: String
    public var message: String
    public var paths: [String]

    public init(revision: String, author: String, date: String, message: String, paths: [String]) {
        self.revision = revision
        self.author = author
        self.date = date
        self.message = message
        self.paths = paths
    }
}

public struct WorkingCopy: Codable, Equatable, Identifiable {
    public var path: String
    public var url: String
    public var revision: String
    public var repositoryRoot: String
    public var username: String

    public var id: String { path }

    public init(path: String, url: String, revision: String, repositoryRoot: String, username: String = "") {
        self.path = path
        self.url = url
        self.revision = revision
        self.repositoryRoot = repositoryRoot
        self.username = username
    }
}

public struct AppSettings: Codable, Equatable {
    public var svnPath: String
    public var promoteCommitAndUpdate: Bool
    public var toolbarUsesSelection: Bool
    public var externalDiffTool: String
    public var commitMessageHistory: [String]
    public var confirmCommands: [String]

    public static var detected: AppSettings {
        AppSettings(
            svnPath: detectSvn(),
            promoteCommitAndUpdate: true,
            toolbarUsesSelection: false,
            externalDiffTool: "",
            commitMessageHistory: [],
            confirmCommands: ["commit", "add", "revert", "deleteVersioned"]
        )
    }

    public static func detectSvn() -> String {
        let candidates = ["/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/svn"
    }
}

public struct StatusFile: Codable, Equatable {
    public var roots: [String]
    public var scanned: [String]
    public var badges: [String: String]
    public var updatedAt: Date

    public init(roots: [String] = [], scanned: [String] = [], badges: [String: String] = [:], updatedAt: Date = Date()) {
        self.roots = roots
        self.scanned = scanned
        self.badges = badges
        self.updatedAt = updatedAt
    }

    public func badge(for path: String) -> BadgeKind? {
        guard let raw = badges[PathID.normalize(path)] else { return nil }
        return BadgeKind(rawValue: raw)
    }

    public func contains(_ path: String) -> Bool {
        PathID.longestRoot(for: path, roots: roots) != nil
    }

    public func isScanned(_ path: String) -> Bool {
        PathID.longestRoot(for: path, roots: scanned) != nil
    }
}

public enum SvnAction: String, Codable, CaseIterable {
    case update
    case updateToRevision
    case commit
    case add
    case undoAdd
    case revert
    case deleteVersioned
    case trashUnversioned
    case diffBase
    case diffTwo
    case info
    case changes
    case log
    case cleanup
    case refresh
    case copyURL
    case checkout
    case register
    case open
}

public struct CommandInvocation: Equatable {
    public var action: SvnAction
    public var paths: [String]
    public var shift: Bool

    public init(action: SvnAction, paths: [String], shift: Bool = false) {
        self.action = action
        self.paths = paths
        self.shift = shift
    }
}

public struct MenuFlags: Equatable {
    public var inWorkingCopy = false
    public var unknown = false
    public var update = false
    public var updateToRevision = false
    public var commit = false
    public var add = false
    public var undoAdd = false
    public var revert = false
    public var deleteVersioned = false
    public var trashUnversioned = false
    public var diffBase = false
    public var diffTwo = false
    public var info = false
    public var changes = false
    public var log = false
    public var cleanup = false
    public var refresh = false
    public var copyURL = false
}
