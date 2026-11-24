import AppKit

final class CommitWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let entries: [StatusEntry]
    private var checks: [Bool]
    private let history: [String]
    private let onCommit: (String, [String]) -> Void
    private let table = NSTableView()
    private let message = NSTextView()
    private let button = NSButton(title: "提交", target: nil, action: nil)

    init(entries: [StatusEntry], history: [String], onCommit: @escaping (String, [String]) -> Void) {
        self.entries = entries
        self.history = history
        self.onCommit = onCommit
        checks = entries.map { $0.item != "conflicted" && $0.badge != .conflict }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "提交"
        super.init(window: window)
        button.target = self
        button.action = #selector(commit)
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "最近说明")
        history.forEach { popup.addItem(withTitle: $0) }
        popup.target = self
        popup.action = #selector(useHistory(_:))
        message.font = NSFont.systemFont(ofSize: 13)
        message.delegate = self
        message.isRichText = false
        let messageScroll = NSScrollView()
        messageScroll.documentView = message
        messageScroll.hasVerticalScroller = true
        messageScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        table.dataSource = self
        table.delegate = self
        let check = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        check.title = ""
        check.width = 28
        let item = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        item.title = "状态"
        item.width = 90
        let path = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        path.title = "路径"
        path.width = 480
        table.addTableColumn(check)
        table.addTableColumn(item)
        table.addTableColumn(path)
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        let hint = NSTextField(wrappingLabelWithString: entries.contains(where: { $0.item == "conflicted" }) ? "有冲突的路径默认不提交。" : "说明不能为空。")
        let stack = NSStackView(views: [popup, messageScroll, hint, tableScroll, button])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        refreshButton()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier.rawValue == "check" {
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
            box.tag = row
            box.state = checks[row] ? .on : .off
            box.isEnabled = entries[row].item != "conflicted"
            return box
        }
        let value = tableColumn?.identifier.rawValue == "item" ? entries[row].item : entries[row].path
        return NSTextField(labelWithString: value)
    }

    func textDidChange(_ notification: Notification) { refreshButton() }

    @objc private func toggle(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < checks.count else { return }
        checks[sender.tag] = sender.state == .on
        refreshButton()
    }

    @objc private func useHistory(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        guard index >= 0, index < history.count else { return }
        message.string = history[index]
        refreshButton()
    }

    @objc private func commit() {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = entries.enumerated().compactMap { checks[$0.offset] ? $0.element.path : nil }
        guard !text.isEmpty, !paths.isEmpty else { return }
        onCommit(text, paths)
        close()
    }

    private func refreshButton() {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        button.isEnabled = !text.isEmpty && checks.contains(true)
    }
}

final class PathPickWindow: NSWindowController {
    private var checks: [Bool]
    private var paths: [String]
    private let onDone: ([String]?) -> Void

    init(paths: [String], onDone: @escaping ([String]?) -> Void) {
        self.paths = paths
        self.checks = Array(repeating: true, count: paths.count)
        self.onDone = onDone
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "选择路径"
        super.init(window: window)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, path) in paths.enumerated() {
            let box = NSButton(checkboxWithTitle: path, target: self, action: #selector(toggle(_:)))
            box.tag = index
            box.state = .on
            box.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview(box)
        }
        let add = NSButton(title: "添加路径…", target: self, action: #selector(addPath))
        let ok = NSButton(title: "继续", target: self, action: #selector(confirm))
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        let bar = NSStackView(views: [add, ok, cancel])
        stack.addArrangedSubview(bar)
        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func toggle(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < checks.count else { return }
        checks[sender.tag] = sender.state == .on
    }

    @objc private func addPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            paths.append(url.path)
            checks.append(true)
        }
        onDone(paths.enumerated().compactMap { checks[$0.offset] ? $0.element : nil })
        close()
    }

    @objc private func confirm() {
        onDone(paths.enumerated().compactMap { checks[$0.offset] ? $0.element : nil })
        close()
    }

    @objc private func cancel() {
        onDone(nil)
        close()
    }
}

final class CheckoutWindow: NSWindowController {
    private let urlField = NSTextField()
    private let revisionField = NSTextField()
    private let parentField = NSTextField()
    private let nameField = NSTextField()
    private let onCheckout: (String, String, String, String) -> Void

    init(onCheckout: @escaping (String, String, String, String) -> Void) {
        self.onCheckout = onCheckout
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "检出"
        super.init(window: window)
        revisionField.placeholderString = "HEAD 留空"
        parentField.stringValue = FileManager.default.homeDirectoryForCurrentUser.path
        let browse = NSButton(title: "选择…", target: self, action: #selector(browse))
        let parentRow = NSStackView(views: [parentField, browse])
        let form = NSStackView(views: [
            labeled("URL", urlField),
            labeled("修订版本", revisionField),
            labeled("父目录", parentRow),
            labeled("目录名", nameField)
        ])
        form.orientation = .vertical
        form.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        form.translatesAutoresizingMaskIntoConstraints = false
        let ok = NSButton(title: "检出", target: self, action: #selector(confirm))
        form.addArrangedSubview(ok)
        window.contentView = form
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            form.topAnchor.constraint(equalTo: window.contentView!.topAnchor)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func labeled(_ title: String, _ view: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let row = NSStackView(views: [label, view])
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return row
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            parentField.stringValue = url.path
        }
    }

    @objc private func confirm() {
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = parentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !name.isEmpty, !parent.isEmpty else {
            Dialog.info("检出", "URL、父目录和目录名都要填。")
            return
        }
        onCheckout(url, revisionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), parent, name)
        close()
    }
}
