import Foundation

public enum SupportPaths {
    public static let statusNotification = "local.macsvn.status"

    /// 真实 home。访达扩展跑在沙盒里，`homeDirectoryForCurrentUser` 会被重定向到
    /// `~/Library/Containers/<bundle-id>/Data`，主程序则拿到真正的 home。两边必须用
    /// 同一个绝对路径才能共享 settings/status，所以这里统一走 getpwuid。
    public static var home: URL {
        var entry = passwd()
        var buffer = [CChar](repeating: 0, count: 4096)
        var result: UnsafeMutablePointer<passwd>?
        getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result)
        if result != nil {
            return URL(fileURLWithPath: String(cString: entry.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var root: URL {
        home.appendingPathComponent("Library/Application Support/macsvn", isDirectory: true)
    }

    public static func postChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(statusNotification as CFString),
            nil,
            nil,
            true
        )
    }
}

public enum PathID {
    public static func normalize(_ path: String) -> String {
        var value = URL(fileURLWithPath: path).standardizedFileURL.path
        if value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    public static func resolve(_ path: String, cwd: URL) -> String {
        if path.hasPrefix("/") {
            return normalize(path)
        }
        return normalize(cwd.appendingPathComponent(path).path)
    }

    public static func isInside(_ path: String, root: String) -> Bool {
        let path = normalize(path)
        let root = normalize(root)
        return path == root || path.hasPrefix(root + "/")
    }

    public static func longestRoot(for path: String, roots: [String]) -> String? {
        let path = normalize(path)
        return roots.map(normalize).filter { isInside(path, root: $0) }.max { $0.count < $1.count }
    }

    public static func isCloudMirror(_ path: String) -> Bool {
        path.contains("/Library/Mobile Documents/")
            || path.contains("/Library/CloudStorage/")
            || path.contains("com~apple~CloudDocs")
    }
}
