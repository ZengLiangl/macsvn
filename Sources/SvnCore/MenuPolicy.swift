import Foundation

/// 按 macSvn 文档实现「macsvn 版本控制」子菜单的可用性规则。
///
/// 文档要点：
/// - 提交：选中项含「已修改（已替换）」「新添加（复制的、新移来）」「已删除（已移走、已丢失）」时可用
/// - 更新：路径受版本控制时可用
/// - 比较：选两项 →「比较两者」；选一项且已修改/新添加/已删除 →「与 Base 版本比较」；
///   做过「稍后比较」后再选另一个文件 →「与 … 比较」
/// - 粘贴：做过「复制/移动 → 复制」或「剪切」后可用
/// - 加锁：文件带 svn:needs-lock 时可用；已加锁则显示为解锁
public enum MenuPolicy {
    public static func flags(
        paths: [String],
        status: StatusFile,
        clipboard: ClipboardState = ClipboardState()
    ) -> MenuFlags {
        let paths = paths.map(PathID.normalize)
        guard !paths.isEmpty, paths.allSatisfy({ status.contains($0) }) else {
            return MenuFlags()
        }
        if paths.contains(where: { !status.isScanned($0) }) {
            return unknownFlags(paths: paths, clipboard: clipboard)
        }
        return scannedFlags(paths: paths, status: status, clipboard: clipboard)
    }

    private static func unknownFlags(paths: [String], clipboard: ClipboardState) -> MenuFlags {
        var flags = MenuFlags()
        flags.inWorkingCopy = true
        flags.unknown = true
        flags.update = true
        flags.updateToRevision = true
        flags.commit = true
        flags.add = true
        flags.undoAdd = true
        flags.revert = true
        flags.deleteVersioned = true
        flags.trashUnversioned = true
        flags.diffBase = paths.count == 1
        flags.diffTwo = paths.count == 2
        flags.info = true
        flags.changes = true
        flags.log = true
        flags.cleanup = true
        flags.refresh = true
        flags.copyURL = true
        flags.copy = true
        flags.move = true
        flags.compareLater = paths.count == 1
        applyClipboard(&flags, paths: paths, clipboard: clipboard)
        // 状态还没扫完，不知道 needs-lock；先允许对单个版本控制文件尝试加锁
        flags.lock = paths.count == 1
        return flags
    }

    private static func scannedFlags(
        paths: [String],
        status: StatusFile,
        clipboard: ClipboardState
    ) -> MenuFlags {
        var flags = MenuFlags()
        flags.inWorkingCopy = true
        flags.update = true
        flags.updateToRevision = true
        flags.info = true
        flags.changes = true
        flags.cleanup = true
        flags.refresh = true

        let badges = paths.map { status.badge(for: $0) }
        let allUnversioned = badges.allSatisfy { $0 == .unversioned }

        // 提交：已修改(已替换)、新添加(复制的、新移来)、已删除(已移走、已丢失)
        flags.commit = badges.contains { badge in
            badge == .modified || badge == .added || badge == .deleted
                || badge == .missing || badge == .conflict
        }

        flags.log = !allUnversioned
        flags.copyURL = !allUnversioned

        // 比较
        flags.diffTwo = paths.count == 2
        flags.compareLater = paths.count == 1 && !allUnversioned
        if paths.count == 1, let badge = badges[0] {
            flags.diffBase = badge == .modified || badge == .added
                || badge == .deleted || badge == .conflict
        }
        if let base = clipboard.compareBase,
           paths.count == 1,
           PathID.normalize(paths[0]) != PathID.normalize(base) {
            flags.compareWith = true
        }

        flags.add = badges.contains(.unversioned)
        flags.undoAdd = badges.contains(.added)
        flags.trashUnversioned = badges.contains(.unversioned)
        flags.revert = badges.contains { $0 == .modified || $0 == .added || $0 == .deleted || $0 == .conflict }
        flags.deleteVersioned = badges.contains { $0 != .unversioned }

        // 复制 / 移动：受版本控制的项可用
        flags.copy = !allUnversioned
        flags.move = !allUnversioned

        // 加锁：文件带 svn:needs-lock 且当前未锁；已锁则显示解锁
        let locked = badges.contains(.locked)
        flags.unlock = locked
        flags.lock = !locked && paths.contains { status.requiresLock($0) }

        applyClipboard(&flags, paths: paths, clipboard: clipboard)
        return flags
    }

    private static func applyClipboard(
        _ flags: inout MenuFlags,
        paths: [String],
        clipboard: ClipboardState
    ) {
        guard !clipboard.paths.isEmpty else { return }
        let sources = Set(clipboard.paths.map(PathID.normalize))
        // 目标不能和来源重合，否则 svn copy 会撞名
        let targets = paths.map(PathID.normalize).filter { !sources.contains($0) }
        flags.paste = !targets.isEmpty
    }
}

public enum RevisionInput {
    public static func isValid(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        if value.allSatisfy(\.isNumber) { return true }
        return value.hasPrefix("{") && value.hasSuffix("}") && value.count > 2
    }
}
