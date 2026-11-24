import AppKit

final class ProgressWindow: NSWindowController, NSWindowDelegate {
    private let output = NSTextView()
    private let commandField = NSTextField(labelWithString: "")
    var onStop: (() -> Void)?
    private var command = ""

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "正在执行"
        self.init(window: window)
        window.delegate = self
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        output.isEditable = false
        output.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        output.autoresizingMask = [.width, .height]
        scroll.documentView = output
        commandField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.lineBreakMode = .byTruncatingMiddle
        let stop = NSButton(title: "停止", target: self, action: #selector(stop))
        let copy = NSButton(title: "复制命令", target: self, action: #selector(copyCommand))
        let bar = NSStackView(views: [commandField, stop, copy])
        bar.orientation = .horizontal
        commandField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let root = NSStackView(views: [bar, scroll])
        root.orientation = .vertical
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }

    func present(title: String, command: String) {
        self.command = command
        window?.title = title
        commandField.stringValue = command
        output.string = ""
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func append(_ text: String) {
        output.string += text
        output.scrollToEndOfDocument(nil)
    }

    func finish(_ result: SvnResult) {
        window?.title = result.cancelled ? "已停止" : (result.code == 0 ? "完成" : "失败 \(result.code)")
        if output.string.isEmpty {
            append(result.combinedText)
        }
    }

    @objc private func stop() { onStop?() }

    @objc private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

enum Dialog {
    @discardableResult
    static func info(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
        return true
    }

    static func confirm(_ title: String, _ message: String, ok: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func ask(_ title: String, _ message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func credentials(host: String, username: String) -> (user: String, password: String, save: Bool)? {
        let alert = NSAlert()
        alert.messageText = "需要登录版本库"
        alert.informativeText = host
        let user = NSTextField(frame: NSRect(x: 0, y: 56, width: 260, height: 24))
        user.stringValue = username
        user.placeholderString = "用户名"
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 24))
        password.placeholderString = "密码"
        let save = NSButton(checkboxWithTitle: "记入钥匙串", target: nil, action: nil)
        save.state = .on
        save.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 84))
        box.addSubview(user)
        box.addSubview(password)
        box.addSubview(save)
        alert.accessoryView = box
        alert.addButton(withTitle: "登录")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (user.stringValue, password.stringValue, save.state == .on)
    }

    static func cleanupOptions() -> (unversioned: Bool, ignored: Bool)? {
        let alert = NSAlert()
        alert.messageText = "清理工作副本"
        alert.informativeText = "默认只解除锁。下面两项会删除文件。"
        let unversioned = NSButton(checkboxWithTitle: "删除未版本化文件", target: nil, action: nil)
        let ignored = NSButton(checkboxWithTitle: "删除被忽略的文件", target: nil, action: nil)
        unversioned.frame = NSRect(x: 0, y: 24, width: 260, height: 22)
        ignored.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 48))
        box.addSubview(unversioned)
        box.addSubview(ignored)
        alert.accessoryView = box
        alert.addButton(withTitle: "清理")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (unversioned.state == .on, ignored.state == .on)
    }
}
