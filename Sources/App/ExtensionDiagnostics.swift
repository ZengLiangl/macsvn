import AppKit

enum ExtensionDiagnostics {
    static func finderSyncEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-v", "-p", "com.apple.FinderSync"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("local.macsvn.FinderSync")
    }

    static func showIfNeeded(workingCopyCount: Int) {
        var issues: [String] = []
        if !FileManager.default.fileExists(atPath: "/Applications/macsvn.app/Contents/MacOS/macsvn") {
            issues.append("请使用 /Applications/macsvn.app。从 build/ 直接运行，访达可能找不到扩展。")
        }
        if !finderSyncEnabled() {
            issues.append("""
            访达扩展还没被系统登记。请依次尝试：
            1. 终端执行：xattr -cr /Applications/macsvn.app
            2. 系统设置 → 扩展 → 点进「macsvn 扩展」→ 勾选「访达 / macsvn 访达」（不要只开「文件提供程序」）。
            3. 终端执行：pluginkit -a /Applications/macsvn.app/Contents/PlugIns/FinderSync.appex
            4. killall Finder
            5. 自检：pluginkit -m -v -p com.apple.FinderSync | grep macsvn
            """)
        }
        if workingCopyCount == 0 {
            issues.append("先在 macsvn 主窗口里「登记」或「检出」一个 Subversion 工作副本。没登记时访达不会出右键菜单。")
        }
        guard !issues.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "访达菜单还没就绪"
        alert.informativeText = issues.joined(separator: "\n\n")
        alert.addButton(withTitle: "打开扩展设置")
        alert.addButton(withTitle: "知道了")
        if alert.runModal() == .alertFirstButtonReturn {
            openExtensionSettings()
        }
    }

    static func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for item in urls {
            if let url = URL(string: item), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}