import Foundation

enum SvnCommands {
    static func globals(interactive: Bool, username: String?, trust: Bool) -> [String] {
        var args: [String] = []
        if !interactive {
            args.append("--non-interactive")
        }
        if trust {
            args.append("--trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other")
        }
        if let username, !username.isEmpty {
            args.append(contentsOf: ["--username", username])
        }
        return args
    }

    static func version() -> [String] { ["--version", "--quiet"] }
    static func info(_ paths: [String]) -> [String] { ["info", "--xml", "--"] + paths }
    static func status(_ path: String) -> [String] { ["status", "--xml", "--", path] }
    static func update(_ paths: [String], revision: String?) -> [String] {
        var args = ["update"]
        if let revision { args.append(contentsOf: ["-r", revision]) }
        return args + ["--"] + paths
    }
    static func commit(_ paths: [String], message: String) -> [String] {
        ["commit", "-m", message, "--"] + paths
    }
    static func add(_ paths: [String], depth: String) -> [String] {
        // --parents 必需：depth=empty 的稀疏检出里，目标文件的上级目录常常还没纳入
        // 版本控制，不带 --parents 会报 E150000「Can't find parent directory's node」。
        ["add", "--parents", "--depth", depth, "--"] + paths
    }
    static func revert(_ paths: [String], recursive: Bool) -> [String] {
        var args = ["revert"]
        if recursive { args.append("-R") }
        return args + ["--"] + paths
    }
    static func delete(_ paths: [String]) -> [String] { ["delete", "--"] + paths }
    static func copy(_ paths: [String], to target: String) -> [String] {
        ["copy", "--parents", "--"] + paths + [target]
    }
    static func move(_ paths: [String], to target: String) -> [String] {
        ["move", "--parents", "--"] + paths + [target]
    }
    static func lock(_ paths: [String], message: String?) -> [String] {
        var args = ["lock"]
        if let message, !message.isEmpty { args.append(contentsOf: ["-m", message]) }
        return args + ["--"] + paths
    }
    static func unlock(_ paths: [String]) -> [String] { ["unlock", "--"] + paths }
    /// 找出带 svn:needs-lock 的路径，决定「加锁」菜单是否可用
    static func needsLock(_ root: String) -> [String] {
        ["propget", "-R", "--xml", "svn:needs-lock", "--", root]
    }
    static func diff(_ paths: [String]) -> [String] { ["diff", "--"] + paths }
    static func diffRevision(_ path: String, revision: String) -> [String] {
        ["diff", "-c", revision, "--", path]
    }
    static func diffTwo(old: String, new: String) -> [String] {
        ["diff", "--old", old, "--new", new]
    }
    static func catBase(_ path: String) -> [String] { ["cat", "-r", "BASE", "--", path] }
    static func log(_ path: String) -> [String] { ["log", "--xml", "-v", "-l", "50", "--", path] }
    static func cleanup(_ path: String, unversioned: Bool, ignored: Bool) -> [String] {
        var args = ["cleanup"]
        if unversioned { args.append("--remove-unversioned") }
        if ignored { args.append("--remove-ignored") }
        return args + ["--", path]
    }
    static func checkout(url: String, target: String, revision: String?) -> [String] {
        var args = ["checkout"]
        if let revision, !revision.isEmpty { args.append(contentsOf: ["-r", revision]) }
        return args + [url, target]
    }
}

enum SvnFailure {
    static func isAuth(_ result: SvnResult) -> Bool {
        let text = result.combinedText.lowercased()
        return text.contains("e170001")
            || text.contains("e215004")
            || text.contains("authorization failed")
            || text.contains("authentication failed")
    }

    static func isCertificate(_ result: SvnResult) -> Bool {
        let text = result.combinedText.lowercased()
        return text.contains("certificate") && (text.contains("e230001") || text.contains("not trusted") || text.contains("issuer"))
    }
}
