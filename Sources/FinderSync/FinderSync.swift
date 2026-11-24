import AppKit
import FinderSync

@objc(FinderSync)
final class FinderSyncController: FIFinderSync {
    private let database = AppDatabase(root: SupportPaths.root)
    private var cache = StatusFile()
    private var known: Set<URL> = []

    override init() {
        super.init()
        cache = database.loadStatus()
        applyRoots()
        installBadges()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            darwinCallback,
            SupportPaths.statusNotification as CFString,
            nil,
            .deliverImmediately
        )
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

    private func contextMenu(paths: [String]) -> NSMenu {
        let flags = MenuPolicy.flags(paths: paths, status: cache)
        if !flags.inWorkingCopy {
            return outsideMenu(paths: paths)
        }
        let settings = database.loadSettings()
        let menu = NSMenu()
        menu.autoenablesItems = false
        if settings.promoteCommitAndUpdate {
            add(menu, "提交…", .commit, flags.commit, paths)
            add(menu, "更新", .update, flags.update, paths)
        }
        let sub = NSMenu()
        sub.autoenablesItems = false
        if !settings.promoteCommitAndUpdate {
            add(sub, "提交…", .commit, flags.commit, paths)
            add(sub, "更新", .update, flags.update, paths)
        }
        add(sub, "更新至指定版本…", .updateToRevision, flags.updateToRevision, paths)
        add(sub, "增加…", .add, flags.add, paths)
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
        let diff = NSMenu()
        diff.autoenablesItems = false
        add(diff, "与 BASE 比较", .diffBase, flags.diffBase, paths)
        add(diff, "比较这两项", .diffTwo, flags.diffTwo, paths)
        if diff.items.count > 0 {
            let item = NSMenuItem(title: "比较", action: nil, keyEquivalent: "")
            item.submenu = diff
            sub.addItem(item)
        }
        add(sub, "显示信息", .info, flags.info, paths)
        add(sub, "检视修改", .changes, flags.changes, paths)
        add(sub, "显示日志…", .log, flags.log, paths)
        add(sub, "清理…", .cleanup, flags.cleanup, paths)
        add(sub, "刷新图标", .refresh, flags.refresh, paths)
        add(sub, "复制 URL", .copyURL, flags.copyURL, paths)
        let parent = NSMenuItem(title: "macsvn", action: nil, keyEquivalent: "")
        parent.submenu = sub
        menu.addItem(parent)
        return menu
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

    private func add(_ menu: NSMenu, _ title: String, _ action: SvnAction, _ enabled: Bool, _ paths: [String]) {
        guard enabled else { return }
        guard let url = CommandURLCodec.encode(CommandInvocation(action: action, paths: paths)) else { return }
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        menu.addItem(item)
    }

    @objc private func fire(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, var invocation = CommandURLCodec.decode(url) else { return }
        invocation.shift = NSEvent.modifierFlags.contains(.shift)
        guard let updated = CommandURLCodec.encode(invocation) else { return }
        NSWorkspace.shared.open(updated)
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
    guard let observer else { return }
    let controller = Unmanaged<FinderSyncController>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.reloadFromDisk()
    }
}
