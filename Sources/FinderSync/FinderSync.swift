import AppKit
import FinderSync

/// 当前存活的扩展控制器。
/// 之前把 self 的裸指针交给通知中心，控制器释放后通知再到达就会在
/// objc_retain 处崩掉（实测崩溃报告：darwinCallback → objc_retain → SIGSEGV）。
fileprivate weak var liveController: FinderSyncController?

@objc(FinderSync)
final class FinderSyncController: FIFinderSync {
    private let database = AppDatabase(root: SupportPaths.root)
    private var cache = StatusFile()
    private var known: Set<URL> = []
    private var observerToken: UnsafeMutableRawPointer?

    override init() {
        super.init()
        cache = database.loadStatus()
        applyRoots()
        installBadges()
        liveController = self
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let token = Unmanaged.passUnretained(self).toOpaque()
        observerToken = token
        CFNotificationCenterAddObserver(
            center,
            token,
            darwinCallback,
            SupportPaths.statusNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        if let token = observerToken {
            // 传 nil 名称 = 注销该观察者的全部注册，避免类型不匹配的多余依赖
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                token,
                nil,
                nil
            )
        }
        if liveController === self { liveController = nil }
    }

    override var toolbarItemName: String { "macsvn" }
    override var toolbarItemToolTip: String { "macsvn 版本控制" }
    override var toolbarItemImage: NSImage { badgeImage(text: "S", color: .systemBlue) }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        cache = database.loadStatus()
        let controller = FIFinderSyncController.default()
        switch menuKind {
        case .contextualMenuForItems:
            return contextMenu(paths: (controller.selectedItemURLs() ?? []).map(\.path))
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            return contextMenu(paths: controller.targetedURL().map { [$0.path] } ?? [])
        case .toolbarItemMenu:
            let settings = database.loadSettings()
            if settings.toolbarUsesSelection, let selected = controller.selectedItemURLs(), !selected.isEmpty {
                return contextMenu(paths: selected.map(\.path))
            }
            return contextMenu(paths: controller.targetedURL().map { [$0.path] } ?? [])
        default:
            return NSMenu()
        }
    }

    override func requestBadgeIdentifier(for url: URL) {
        known.insert(url)
        applyBadge(url)
    }

    func reloadFromDisk() {
        cache = database.loadStatus()
        applyRoots()
        known.forEach(applyBadge)
    }

    private func applyRoots() {
        let roots = database.loadWorkingCopies().map { URL(fileURLWithPath: $0.path) }
        FIFinderSyncController.default().directoryURLs = Set(roots)
    }

    private func applyBadge(_ url: URL) {
        let identifier = cache.badge(for: url.path)?.rawValue ?? ""
        FIFinderSyncController.default().setBadgeIdentifier(identifier, for: url)
    }

    private func installBadges() {
        let items: [(BadgeKind, String, NSColor)] = [
            (.conflict, "C", .systemRed),
            (.missing, "!", .systemOrange),
            (.modified, "M", .systemYellow),
            (.added, "A", .systemGreen),
            (.deleted, "D", .systemGray),
            (.unversioned, "?", .systemBlue),
            (.locked, "K", .systemPurple)
        ]
        for item in items {
            FIFinderSyncController.default().setBadgeImage(badgeImage(text: item.1, color: item.2), label: item.0.rawValue, forBadgeIdentifier: item.0.rawValue)
        }
    }

    /// 按文档构建「macsvn 版本控制」子菜单，并把设置里勾选的项目提到访达主菜单。
    private func contextMenu(paths: [String]) -> NSMenu {
        let clipboard = database.loadClipboard()
        let flags = MenuPolicy.flags(paths: paths, status: cache, clipboard: clipboard)
        if !flags.inWorkingCopy {
            return outsideMenu(paths: paths)
        }
        let settings = database.loadSettings()
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 文档：提交、更新、比较、粘贴、加锁 可移到主菜单
        if settings.promotes(.commit) { add(menu, "提交…", .commit, flags.commit, paths) }
        if settings.promotes(.update) { add(menu, "更新", .update, flags.update, paths) }
        if settings.promotes(.diffTwo) || settings.promotes(.diffBase) {
            if let item = compareItem(flags: flags, paths: paths) { menu.addItem(item) }
        }
        if settings.promotes(.paste) { add(menu, "粘贴", .paste, flags.paste, paths) }
        if settings.promotes(.lock) {
            add(menu, "加锁…", .lock, flags.lock, paths)
            add(menu, "解锁", .unlock, flags.unlock, paths)
        }

        let sub = NSMenu()
        sub.autoenablesItems = false
        if !settings.promotes(.commit) { add(sub, "提交…", .commit, flags.commit, paths) }
        if !settings.promotes(.update) { add(sub, "更新", .update, flags.update, paths) }
        if !(settings.promotes(.diffTwo) || settings.promotes(.diffBase)),
           let item = compareItem(flags: flags, paths: paths) {
            sub.addItem(item)
        }
        if !settings.promotes(.paste) {
            add(sub, "粘贴", .paste, flags.paste, paths)
        }
        add(sub, "更新至指定版本…", .updateToRevision, flags.updateToRevision, paths)
        add(sub, "增加…", .add, flags.add, paths)

        // 复制 / 移动：文档要求先复制或剪切，粘贴项才可用
        let copyMove = NSMenu()
        copyMove.autoenablesItems = false
        add(copyMove, "复制到剪贴板", .copy, flags.copy, paths)
        add(copyMove, "剪切到剪贴板", .move, flags.move, paths)
        if copyMove.items.count > 0 {
            let item = NSMenuItem(title: "复制/移动", action: nil, keyEquivalent: "")
            item.submenu = copyMove
            sub.addItem(item)
        }

        add(sub, "撤销增加", .undoAdd, flags.undoAdd, paths)
        let deletion = NSMenu()
        deletion.autoenablesItems = false
        add(deletion, "从版本库删除", .deleteVersioned, flags.deleteVersioned, paths)
        add(deletion, "把未版本化文件移到废纸篓", .trashUnversioned, flags.trashUnversioned, paths)
        if deletion.items.count > 0 {
            let item = NSMenuItem(title: "删除", action: nil, keyEquivalent: "")
            item.submenu = deletion
            sub.addItem(item)
        }
        add(sub, "恢复…", .revert, flags.revert, paths)

        if !settings.promotes(.lock) {
            add(sub, "加锁…", .lock, flags.lock, paths)
            add(sub, "解锁", .unlock, flags.unlock, paths)
        }

        add(sub, "显示信息", .info, flags.info, paths)
        add(sub, "检视修改", .changes, flags.changes, paths)
        add(sub, "显示日志…", .log, flags.log, paths)
        add(sub, "清理…", .cleanup, flags.cleanup, paths)
        add(sub, "刷新图标", .refresh, flags.refresh, paths)
        add(sub, "复制 URL", .copyURL, flags.copyURL, paths)

        let parent = NSMenuItem(title: "macsvn 版本控制", action: nil, keyEquivalent: "")
        parent.submenu = sub
        menu.addItem(parent)
        return menu
    }

    /// 文档：选两项 →「比较两者」；选一项且已修改/新添加/已删除 →「与 Base 版本比较」；
    /// 做过「稍后比较」后再选另一文件 →「与 … 比较」。
    private func compareItem(flags: MenuFlags, paths: [String]) -> NSMenuItem? {
        let diff = NSMenu()
        diff.autoenablesItems = false
        add(diff, "比较两者", .diffTwo, flags.diffTwo, paths)
        add(diff, "与 BASE 版本比较", .diffBase, flags.diffBase, paths)
        let base = database.loadClipboard().compareBase
        if flags.compareWith, let base {
            add(diff, "与「\(URL(fileURLWithPath: base).lastPathComponent)」比较", .compareWith, true, paths)
        }
        add(diff, "稍后比较", .compareLater, flags.compareLater, paths)
        guard diff.items.count > 0 else { return nil }
        let item = NSMenuItem(title: "比较", action: nil, keyEquivalent: "")
        item.submenu = diff
        return item
    }

    private func outsideMenu(paths: [String]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add(menu, "打开 macsvn", .open, true, [])
        if paths.count == 1 {
            add(menu, "登记当前目录", .register, true, paths)
        }
        add(menu, "检出…", .checkout, true, [])
        return menu
    }

    private func add(
        _ menu: NSMenu,
        _ title: String,
        _ action: SvnAction,
        _ enabled: Bool,
        _ paths: [String]
    ) {
        // shift 由点击时的键盘状态决定（见 fire），这里保持 false
        guard let url = CommandURLCodec.encode(CommandInvocation(action: action, paths: paths)) else { return }
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        // 不可用时置灰而不是隐藏：菜单结构保持稳定，用户能看出「有这项、当前不可用」
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func fire(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, var invocation = CommandURLCodec.decode(url) else { return }
        // 编码时 shift=true 表示「这个命令支持 SHIFT 临时切换路径选择窗口」，
        // 这里再按实际按键决定是否翻转。不支持的命令保持 false。
        if invocation.shift {
            invocation.shift = NSEvent.modifierFlags.contains(.shift)
        }
        guard let updated = CommandURLCodec.encode(invocation) else {
            FinderSyncLog.write("菜单点击失败：URL 编码失败 \(invocation.action.rawValue)")
            return
        }
        let opened = NSWorkspace.shared.open(updated)
        FinderSyncLog.write("菜单点击 \(invocation.action.rawValue) 项数=\(invocation.paths.count) 发送=\(opened)")
    }

    private func badgeImage(text: String, color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9),
            .foregroundColor: NSColor.white
        ]
        let drawing = text as NSString
        let textSize = drawing.size(withAttributes: attributes)
        drawing.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attributes
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private func darwinCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard observer != nil else { return }
    guard let controller = liveController else { return }
    DispatchQueue.main.async { [weak controller] in
        controller?.reloadFromDisk()
    }
}


/// 扩展自己的日志：写进共享目录，便于排查「点了没反应」到底卡在哪一步。
enum FinderSyncLog {
    static func write(_ line: String) {
        let url = SupportPaths.root.appendingPathComponent("macsvn.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) [访达扩展] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}


/// 扩展侧日志：写进共享目录，用于判断「点了没反应」卡在扩展还是主程序。
enum ExtensionLog {
    static func write(_ line: String) {
        let url = SupportPaths.root.appendingPathComponent("macsvn.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) [访达扩展] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
