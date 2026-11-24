import Foundation

public enum MenuPolicy {
    public static func flags(paths: [String], status: StatusFile) -> MenuFlags {
        let paths = paths.map(PathID.normalize)
        guard !paths.isEmpty, paths.allSatisfy({ status.contains($0) }) else {
            return MenuFlags()
        }
        if paths.contains(where: { !status.isScanned($0) }) {
            return unknownFlags(count: paths.count)
        }
        return scannedFlags(paths: paths, status: status)
    }

    private static func unknownFlags(count: Int) -> MenuFlags {
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
        flags.diffBase = count == 1
        flags.diffTwo = count == 2
        flags.info = true
        flags.changes = true
        flags.log = true
        flags.cleanup = true
        flags.refresh = true
        flags.copyURL = true
        return flags
    }

    private static func scannedFlags(paths: [String], status: StatusFile) -> MenuFlags {
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
        flags.log = !allUnversioned
        flags.copyURL = !allUnversioned
        flags.diffTwo = paths.count == 2
        if paths.count == 1, let badge = badges[0] {
            flags.diffBase = badge == .modified || badge == .added || badge == .deleted || badge == .conflict
        }
        flags.add = badges.contains(.unversioned)
        flags.undoAdd = badges.contains(.added)
        flags.trashUnversioned = badges.contains(.unversioned)
        flags.revert = badges.contains { $0 == .modified || $0 == .added || $0 == .deleted || $0 == .conflict }
        flags.commit = badges.contains { $0 == .modified || $0 == .added || $0 == .deleted || $0 == .conflict || $0 == .missing }
        flags.deleteVersioned = badges.contains { $0 != .unversioned }
        return flags
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
