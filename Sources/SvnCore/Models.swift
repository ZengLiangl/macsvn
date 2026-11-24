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
    /// 从子菜单提到访达主菜单的动作（rawValue）。文档可配五项：提交、更新、比较、粘贴、加锁。
    public var promotedActions: [String]
    public var toolbarUsesSelection: Bool
    public var externalDiffTool: String
    public var commitMessageHistory: [String]
    /// 执行前先弹「选择路径」窗口的动作（rawValue）。文档：添加、删除、恢复、加锁。
    public var confirmCommands: [String]
    /// 命令执行成功时不弹进度窗口，只在失败时弹出来给出错信息。
    public var hideProgressOnSuccess: Bool

    public static var detected: AppSettings {
        AppSettings(
            svnPath: detectSvn(),
            promotedActions: [],
            toolbarUsesSelection: false,
            externalDiffTool: "",
            commitMessageHistory: [],
            confirmCommands: ["add", "revert", "deleteVersioned", "lock"],
            hideProgressOnSuccess: true
        )
    }

    public func promotes(_ action: SvnAction) -> Bool {
        promotedActions.contains(action.rawValue)
    }

    public func asksForPaths(_ action: SvnAction) -> Bool {
        confirmCommands.contains(action.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case svnPath, promotedActions, toolbarUsesSelection, externalDiffTool
        case commitMessageHistory, confirmCommands, hideProgressOnSuccess
        case promoteCommitAndUpdate
    }

    public init(
        svnPath: String,
        promotedActions: [String],
        toolbarUsesSelection: Bool,
        externalDiffTool: String,
        commitMessageHistory: [String],
        confirmCommands: [String],
        hideProgressOnSuccess: Bool = true
    ) {
        self.svnPath = svnPath
        self.promotedActions = promotedActions
        self.toolbarUsesSelection = toolbarUsesSelection
        self.externalDiffTool = externalDiffTool
        self.commitMessageHistory = commitMessageHistory
        self.confirmCommands = confirmCommands
        self.hideProgressOnSuccess = hideProgressOnSuccess
    }

    public init(from decoder: Decoder) throws {
        let fallback = AppSettings.detected
        let c = try decoder.container(keyedBy: CodingKeys.self)
        svnPath = try c.decodeIfPresent(String.self, forKey: .svnPath) ?? fallback.svnPath
        toolbarUsesSelection = try c.decodeIfPresent(Bool.self, forKey: .toolbarUsesSelection) ?? fallback.toolbarUsesSelection
        externalDiffTool = try c.decodeIfPresent(String.self, forKey: .externalDiffTool) ?? ""
        commitMessageHistory = try c.decodeIfPresent([String].self, forKey: .commitMessageHistory) ?? []
        confirmCommands = try c.decodeIfPresent([String].self, forKey: .confirmCommands) ?? fallback.confirmCommands
        hideProgressOnSuccess = try c.decodeIfPresent(Bool.self, forKey: .hideProgressOnSuccess) ?? fallback.hideProgressOnSuccess
        if let promoted = try c.decodeIfPresent([String].self, forKey: .promotedActions) {
            promotedActions = promoted
        } else {
            // 旧配置只有 promoteCommitAndUpdate，迁移成「提交+更新 进主菜单」
            let legacy = try c.decodeIfPresent(Bool.self, forKey: .promoteCommitAndUpdate) ?? true
            promotedActions = legacy ? ["commit", "update"] : []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(svnPath, forKey: .svnPath)
        try c.encode(promotedActions, forKey: .promotedActions)
        try c.encode(toolbarUsesSelection, forKey: .toolbarUsesSelection)
        try c.encode(externalDiffTool, forKey: .externalDiffTool)
        try c.encode(commitMessageHistory, forKey: .commitMessageHistory)
        try c.encode(confirmCommands, forKey: .confirmCommands)
        try c.encode(hideProgressOnSuccess, forKey: .hideProgressOnSuccess)
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
    /// 带 svn:needs-lock 的路径。「加锁」菜单只对它们可用。
    public var needsLock: [String]

    public init(
        roots: [String] = [],
        scanned: [String] = [],
        badges: [String: String] = [:],
        updatedAt: Date = Date(),
        needsLock: [String] = []
    ) {
        self.roots = roots
        self.scanned = scanned
        self.badges = badges
        self.updatedAt = updatedAt
        self.needsLock = needsLock
    }

    private enum CodingKeys: String, CodingKey {
        case roots, scanned, badges, updatedAt, needsLock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        scanned = try c.decodeIfPresent([String].self, forKey: .scanned) ?? []
        badges = try c.decodeIfPresent([String: String].self, forKey: .badges) ?? [:]
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        needsLock = try c.decodeIfPresent([String].self, forKey: .needsLock) ?? []
    }

    public func requiresLock(_ path: String) -> Bool {
        needsLock.contains(PathID.normalize(path))
    }

    public func badge(for path: String) -> BadgeKind? {
        guard let raw = badges[PathID.normalize(path)] else { return nil }
        return BadgeKind(rawValue: raw)
    }

    /// 取生效角标：自己没有角标时，沿用最近祖先的。
    ///
    /// `svn status` 只报有变化的节点，未版本化目录里的文件不会单独出现。
    /// 若只查精确匹配，这类文件会「看起来干净」，菜单就什么都不能做。
    /// 它们在未版本化目录里，因此继承 unversioned 才是对的。
    public func effectiveBadge(for path: String) -> BadgeKind? {
        let path = PathID.normalize(path)
        if let raw = badges[path] { return BadgeKind(rawValue: raw) }
        var current = path
        while true {
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { break }
            if let raw = badges[parent] { return BadgeKind(rawValue: raw) }
            current = parent
        }
        return nil
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
    // 复制 / 移动：先记下来源，再由「粘贴」落到目标目录
    case copy
    case move
    case paste
    // 加锁 / 解锁
    case lock
    case unlock
    // 稍后比较 / 与…比较
    case compareLater
    case compareWith
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
    public var copy = false
    public var move = false
    public var paste = false
    public var lock = false
    public var unlock = false
    public var compareLater = false
    public var compareWith = false
}

/// 复制/移动暂存区与「稍后比较」的基准文件。
/// 扩展与主程序是两个进程，必须落盘共享，否则菜单可用性与实际执行看到的不是同一份状态。
public struct ClipboardState: Codable, Equatable {
    public var paths: [String]
    public var isMove: Bool
    public var compareBase: String?

    public init(paths: [String] = [], isMove: Bool = false, compareBase: String? = nil) {
        self.paths = paths
        self.isMove = isMove
        self.compareBase = compareBase
    }
}

