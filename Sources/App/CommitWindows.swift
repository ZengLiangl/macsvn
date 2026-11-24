import AppKit

/// 勾选框知道自己是哪个节点，避免用行号导致排序/展开后错位
final class CommitCheckbox: NSButton {
    var nodePath: String = ""
}

final class CommitWindow: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextViewDelegate {
    private let roots: [CommitNode]
    private var selected: Set<String> = []
    private let history: [String]
    private let onCommit: (String, [String], [String]) -> Void
    private let outline = NSOutlineView()
    private let message = NSTextView()
    private let button = NSButton(title: "提交", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")

    init(roots: [CommitNode], history: [String], onCommit: @escaping (String, [String], [String]) -> Void) {
        self.roots = roots
        self.history = history
        self.onCommit = onCommit
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "提交"
        super.init(window: window)

        // 默认勾上所有「已有改动」，未加入的留给用户自己挑
        func preselect(_ nodes: [CommitNode]) {
            for node in nodes {
                if node.isUnversioned {
                    preselect(node.children)
                } else {
                    if !node.isDirectory { selected.insert(node.path) }
                    preselect(node.children)
                }
            }
        }
        preselect(roots)

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
        messageScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let allButton = NSButton(title: "全选", target: self, action: #selector(selectAllNodes))
        let noneButton = NSButton(title: "全不选", target: self, action: #selector(clearAllNodes))
        let expandButton = NSButton(title: "展开全部", target: self, action: #selector(expandAll))
        let collapseButton = NSButton(title: "收起全部", target: self, action: #selector(collapseAll))
        let tools = NSStackView(views: [allButton, noneButton, expandButton, collapseButton])

        let outline = self.outline
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = false
        for (id, title, width) in [("check", "", 30), ("state", "状态", 110), ("name", "名称", 560)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = CGFloat(width)
            outline.addTableColumn(column)
            if id == "check" { outline.outlineTableColumn = column }
        }
        outline.autoresizesOutlineColumn = false
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true

        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [popup, messageScroll, tools, scroll, summaryLabel, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        refresh()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Outline 数据源

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? CommitNode else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? CommitNode else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? CommitNode)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? CommitNode else { return nil }
        switch tableColumn?.identifier.rawValue {
        case "check":
            let box = CommitCheckbox(checkboxWithTitle: "", target: self, action: #selector(toggleNode(_:)))
            box.nodePath = node.path
            box.state = state(for: node)
            return box
        case "state":
            let field = NSTextField(labelWithString: node.label)
            field.textColor = node.isUnversioned ? .secondaryLabelColor : .labelColor
            return field
        default:
            return NSTextField(labelWithString: node.name)
        }
    }

    // MARK: - 勾选逻辑

    private func state(for node: CommitNode) -> NSControl.StateValue {
        if selected.contains(node.path) { return .on }
        // 有子项被选中时显示混合态
        func anySelected(_ n: CommitNode) -> Bool {
            if selected.contains(n.path) { return true }
            return n.children.contains(where: anySelected)
        }
        return node.children.contains(where: anySelected) ? .mixed : .off
    }

    private func descendants(_ node: CommitNode) -> [String] {
        var result = [node.path]
        node.children.forEach { result.append(contentsOf: descendants($0)) }
        return result
    }

    @objc private func toggleNode(_ sender: CommitCheckbox) {
        guard let node = node(at: sender.nodePath) else { return }
        let turnOn = sender.state != .on ? true : false
        let paths = descendants(node)
        if turnOn {
            // 目录勾上时，未加入的子项交给上级统一 add，不单独勾
            if node.isUnversioned && node.isDirectory {
                selected.insert(node.path)
                for path in paths.dropFirst() { selected.remove(path) }
            } else {
                selected.formUnion(paths)
            }
        } else {
            paths.forEach { selected.remove($0) }
        }
        outline.reloadData()
        refresh()
    }

    private func node(at path: String) -> CommitNode? {
        func find(_ nodes: [CommitNode]) -> CommitNode? {
            for node in nodes {
                if node.path == path { return node }
                if let hit = find(node.children) { return hit }
            }
            return nil
        }
        return find(roots)
    }

    @objc private func selectAllNodes() {
        func all(_ nodes: [CommitNode]) {
            for node in nodes {
                if node.isUnversioned && node.isDirectory {
                    selected.insert(node.path)
                    continue
                }
                selected.insert(node.path)
                all(node.children)
            }
        }
        all(roots)
        outline.reloadData()
        refresh()
    }

    @objc private func clearAllNodes() {
        selected.removeAll()
        outline.reloadData()
        refresh()
    }

    @objc private func expandAll() { outline.expandItem(nil, expandChildren: true) }
    @objc private func collapseAll() { outline.collapseItem(nil, collapseChildren: true) }

    func textDidChange(_ notification: Notification) { refresh() }

    @objc private func useHistory(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        guard index >= 0, index < history.count else { return }
        message.string = history[index]
        refresh()
    }

    @objc private func commit() {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked = CommitTree.collect(selected: selected, roots: roots)
        guard !text.isEmpty, !picked.versioned.isEmpty || !picked.unversioned.isEmpty else { return }
        onCommit(text, picked.versioned, picked.unversioned)
        close()
    }

    private func refresh() {
        let picked = CommitTree.collect(selected: selected, roots: roots)
        var parts: [String] = []
        if !picked.versioned.isEmpty { parts.append("提交 \(picked.versioned.count) 项改动") }
        if !picked.unversioned.isEmpty { parts.append("先加入 \(picked.unversioned.count) 项") }
        summaryLabel.stringValue = parts.isEmpty ? "先勾选要提交的内容" : parts.joined(separator: "，")
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        button.isEnabled = !text.isEmpty && !(picked.versioned.isEmpty && picked.unversioned.isEmpty)
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
