import AppKit

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let database: AppDatabase
    private let pathField = NSTextField()
    private let promote = NSButton(checkboxWithTitle: "把提交和更新放到访达主菜单", target: nil, action: nil)
    private let toolbarSelection = NSButton(checkboxWithTitle: "工具栏按钮使用当前选中项", target: nil, action: nil)
    private let diffTool = NSTextField()
    private let table = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var copies: [WorkingCopy] = []

    init(database: AppDatabase) {
        self.database = database
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "macsvn"
        super.init(window: window)
        copies = database.loadWorkingCopies()
        let settings = database.loadSettings()
        pathField.stringValue = settings.svnPath
        promote.state = settings.promoteCommitAndUpdate ? .on : .off
        toolbarSelection.state = settings.toolbarUsesSelection ? .on : .off
        diffTool.stringValue = settings.externalDiffTool
        promote.target = self
        promote.action = #selector(saveSettings)
        toolbarSelection.target = self
        toolbarSelection.action = #selector(saveSettings)
        let detect = NSButton(title: "探测", target: self, action: #selector(detectSvn))
        let save = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        let pathRow = NSStackView(views: [NSTextField(labelWithString: "svn"), pathField, detect, save])
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "工作副本"
        column.width = 420
        let url = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        url.title = "URL"
        url.width = 280
        table.addTableColumn(column)
        table.addTableColumn(url)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        let manage = buttonRow([
            ("登记…", #selector(register)),
            ("检出…", #selector(checkout)),
            ("移除", #selector(remove)),
            ("在访达中显示", #selector(reveal))
        ])
        let commands = buttonRow([
            ("更新", #selector(update)),
            ("提交…", #selector(commit)),
            ("日志…", #selector(showLog)),
            ("检视修改", #selector(changes)),
            ("清理…", #selector(cleanup)),
            ("刷新图标", #selector(refresh))
        ])
        let extensionButton = NSButton(title: "打开访达扩展设置", target: self, action: #selector(openExtensions))
        let help = NSTextField(wrappingLabelWithString: "访达里要先在系统设置中启用 macsvn 的 Finder 扩展，并把工作副本登记到上面的列表。iCloud 云盘和网盘目录里不会出现右键菜单，主窗口仍然可以操作。")
        help.maximumNumberOfLines = 3
        diffTool.placeholderString = "外部比较工具，可留空"
        let root = NSStackView(views: [pathRow, promote, toolbarSelection, diffTool, scroll, manage, commands, extensionButton, help, statusLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload() {
        copies = database.loadWorkingCopies()
        table.reloadData()
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func numberOfRows(in tableView: NSTableView) -> Int { copies.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let copy = copies[row]
        let value = tableColumn?.identifier.rawValue == "url" ? copy.url : copy.path
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    func selectedPaths() -> [String] {
        table.selectedRowIndexes.compactMap { index in
            copies.indices.contains(index) ? copies[index].path : nil
        }
    }

    private func buttonRow(_ items: [(String, Selector)]) -> NSStackView {
        let buttons = items.map { title, action in
            NSButton(title: title, target: self, action: action)
        }
        return NSStackView(views: buttons)
    }

    @objc private func detectSvn() {
        pathField.stringValue = AppSettings.detectSvn()
        saveSettings()
    }

    @objc private func saveSettings() {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileManager.default.isExecutableFile(atPath: path) else {
            Dialog.info("svn 不可用", "这个路径不能执行：\(path)")
            return
        }
        var settings = database.loadSettings()
        settings.svnPath = path
        settings.promoteCommitAndUpdate = promote.state == .on
        settings.toolbarUsesSelection = toolbarSelection.state == .on
        settings.externalDiffTool = diffTool.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        database.saveSettings(settings)
        setStatus("已保存设置")
    }

    @objc private func register() { CommandCenter.shared.register(paths: []) }
    @objc private func checkout() { CommandCenter.shared.perform(CommandInvocation(action: .checkout, paths: [])) }
    @objc private func remove() {
        for path in selectedPaths() {
            database.removeWorkingCopy(path: path)
        }
        reload()
        CommandCenter.shared.monitor?.rewatch()
    }
    @objc private func reveal() {
        selectedPaths().map { URL(fileURLWithPath: $0) }.forEach { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    }
    @objc private func update() { run(.update) }
    @objc private func commit() { run(.commit) }
    @objc private func showLog() { run(.log) }
    @objc private func changes() { run(.changes) }
    @objc private func cleanup() { run(.cleanup) }
    @objc private func refresh() { run(.refresh) }

    private func run(_ action: SvnAction) {
        let paths = selectedPaths()
        guard !paths.isEmpty else {
            Dialog.info("未选择工作副本", "先在列表里选一个工作副本。")
            return
        }
        CommandCenter.shared.perform(CommandInvocation(action: action, paths: paths))
    }

    @objc private func openExtensions() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for item in candidates {
            if let url = URL(string: item), NSWorkspace.shared.open(url) {
                return
            }
        }
        Dialog.info("扩展设置", "请打开系统设置，在「隐私与安全性 → 扩展」或「登录项与扩展」里启用 macsvn。")
    }
}
