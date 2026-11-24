import AppKit

final class TextWindow: NSWindowController {
    private let textView = NSTextView()

    convenience init(title: String, text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        self.init(window: window)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        scroll.documentView = textView
        window.contentView = scroll
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        window.center()
    }
}

final class DiffWindow: NSWindowController {
    convenience init(title: String, leftTitle: String, left: String, rightTitle: String, right: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        self.init(window: window)
        let split = NSSplitView()
        split.isVertical = true
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(column(title: leftTitle, text: left))
        split.addArrangedSubview(column(title: rightTitle, text: right))
        window.contentView = split
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            split.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            split.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        window.center()
    }

    private func column(title: String, text: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.string = text
        scroll.documentView = view
        let stack = NSStackView(views: [label, scroll])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return stack
    }
}

final class LogWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let entries: [LogEntry]
    private let onPick: (LogEntry) -> Void
    private let table = NSTableView()

    init(entries: [LogEntry], onPick: @escaping (LogEntry) -> Void) {
        self.entries = entries
        self.onPick = onPick
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "日志"
        super.init(window: window)
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(openEntry)
        table.target = self
        for (id, title, width) in [("rev", "修订", 70), ("author", "作者", 120), ("date", "日期", 180), ("msg", "说明", 360)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = CGFloat(width)
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = scroll
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "rev": value = entry.revision
        case "author": value = entry.author
        case "date": value = entry.date
        default: value = entry.message.replacingOccurrences(of: "\n", with: " ")
        }
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    @objc private func openEntry() {
        let row = table.clickedRow
        guard row >= 0, row < entries.count else { return }
        onPick(entries[row])
    }
}

final class ChangesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let entries: [StatusEntry]
    private let onPick: (StatusEntry) -> Void
    private let table = NSTableView()

    init(entries: [StatusEntry], onPick: @escaping (StatusEntry) -> Void) {
        self.entries = entries
        self.onPick = onPick
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "检视修改"
        super.init(window: window)
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(openEntry)
        table.target = self
        for (id, title, width) in [("item", "状态", 120), ("path", "路径", 560)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = CGFloat(width)
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = scroll
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let value = tableColumn?.identifier.rawValue == "item" ? entry.item : entry.path
        return NSTextField(labelWithString: value)
    }

    @objc private func openEntry() {
        let row = table.clickedRow
        guard row >= 0 else { return }
        onPick(entries[row])
    }
}

/// 更新结果：把 svn update 的原始输出整理成「改了什么」的清单。
final class UpdateWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let entries: [UpdateEntry]
    private let table = NSTableView()

    init(summary: UpdateSummary) {
        self.entries = summary.entries
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        var title = "更新结果"
        if let revision = summary.revision { title += " · r\(revision)" }
        window.title = title
        super.init(window: window)

        table.dataSource = self
        table.delegate = self
        for (id, heading, width) in [("action", "动作", 90), ("path", "路径", 640)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = heading
            column.width = CGFloat(width)
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        var parts: [String] = []
        if let revision = summary.revision {
            parts.append(summary.upToDate ? "已是最新版本 r\(revision)" : "已更新到 r\(revision)")
        }
        if summary.hasChanges {
            let counts = Dictionary(grouping: summary.entries, by: \.label)
                .map { "\($0.key) \($0.value.count)" }
                .sorted()
            parts.append("共 \(summary.entries.count) 项：" + counts.joined(separator: "、"))
        } else {
            parts.append("没有文件被修改")
        }
        let header = NSTextField(wrappingLabelWithString: parts.joined(separator: "；"))
        header.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let root = NSStackView(views: [header] + summary.notes.map { NSTextField(wrappingLabelWithString: $0) } + [scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let value = tableColumn?.identifier.rawValue == "action" ? entry.label : entry.path
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }
}
