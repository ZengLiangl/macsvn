import Foundation

public final class AppDatabase {
    public let root: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func loadSettings() -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return read(AppSettings.self, file: "settings.json") ?? .detected
    }

    public func saveSettings(_ settings: AppSettings) {
        lock.lock()
        write(settings, file: "settings.json")
        lock.unlock()
        SupportPaths.postChanged()
    }

    public func loadWorkingCopies() -> [WorkingCopy] {
        lock.lock()
        defer { lock.unlock() }
        return read([WorkingCopy].self, file: "working-copies.json") ?? []
    }

    public func upsert(_ copy: WorkingCopy) {
        lock.lock()
        var all = read([WorkingCopy].self, file: "working-copies.json") ?? []
        let path = PathID.normalize(copy.path)
        var stored = copy
        stored.path = path
        all.removeAll { PathID.normalize($0.path) == path }
        all.append(stored)
        all.sort { $0.path < $1.path }
        write(all, file: "working-copies.json")
        lock.unlock()
        SupportPaths.postChanged()
    }

    public func removeWorkingCopy(path: String) {
        lock.lock()
        var all = read([WorkingCopy].self, file: "working-copies.json") ?? []
        let path = PathID.normalize(path)
        all.removeAll { PathID.normalize($0.path) == path }
        write(all, file: "working-copies.json")
        var status = readStatusUnlocked()
        status.roots.removeAll { PathID.normalize($0) == path }
        status.scanned.removeAll { PathID.normalize($0) == path }
        status.badges = status.badges.filter { !PathID.isInside($0.key, root: path) }
        status.updatedAt = Date()
        write(status, file: "status.json")
        lock.unlock()
        SupportPaths.postChanged()
    }

    public func workingCopy(containing path: String) -> WorkingCopy? {
        let copies = loadWorkingCopies()
        guard let root = PathID.longestRoot(for: path, roots: copies.map(\.path)) else { return nil }
        return copies.first { PathID.normalize($0.path) == root }
    }

    public func loadStatus() -> StatusFile {
        lock.lock()
        defer { lock.unlock() }
        return readStatusUnlocked()
    }

    public func loadClipboard() -> ClipboardState {
        lock.lock()
        defer { lock.unlock() }
        return read(ClipboardState.self, file: "clipboard.json") ?? ClipboardState()
    }

    public func saveClipboard(_ state: ClipboardState) {
        lock.lock()
        write(state, file: "clipboard.json")
        lock.unlock()
        SupportPaths.postChanged()
    }

    public func replaceStatus(root: String, badges: [String: String], scanned: Bool, needsLock: [String]? = nil) {
        lock.lock()
        var status = readStatusUnlocked()
        let root = PathID.normalize(root)
        if !status.roots.contains(root) {
            status.roots.append(root)
            status.roots.sort()
        }
        if scanned {
            if !status.scanned.contains(root) {
                status.scanned.append(root)
            }
        }
        status.badges = status.badges.filter { !PathID.isInside($0.key, root: root) }
        for (key, value) in badges {
            status.badges[PathID.normalize(key)] = value
        }
        if let needsLock {
            status.needsLock = status.needsLock.filter { !PathID.isInside($0, root: root) }
            status.needsLock.append(contentsOf: needsLock.map(PathID.normalize))
            status.needsLock.sort()
        }
        status.updatedAt = Date()
        write(status, file: "status.json")
        lock.unlock()
        SupportPaths.postChanged()
    }

    public func rememberCommitMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var settings = loadSettings()
        settings.commitMessageHistory.removeAll { $0 == trimmed }
        settings.commitMessageHistory.insert(trimmed, at: 0)
        if settings.commitMessageHistory.count > 20 {
            settings.commitMessageHistory = Array(settings.commitMessageHistory.prefix(20))
        }
        saveSettings(settings)
    }

    private func readStatusUnlocked() -> StatusFile {
        read(StatusFile.self, file: "status.json") ?? StatusFile()
    }

    private func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        let url = root.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, file: String) {
        let url = root.appendingPathComponent(file)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
