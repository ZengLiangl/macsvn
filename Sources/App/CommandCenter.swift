import AppKit

final class CommandCenter: NSObject, NSWindowDelegate {
    static let shared = CommandCenter()

    private var database: AppDatabase?
    private(set) var monitor: StatusMonitor?
    private weak var main: MainWindowController?
    private var windows: [NSWindowController] = []
    private var busy: Set<String> = []
    private var ready = false
    private var pending: [CommandInvocation] = []

    func configure(database: AppDatabase, monitor: StatusMonitor, main: MainWindowController) {
        self.database = database
        self.monitor = monitor
        self.main = main
        ready = true
        let queued = pending
        pending.removeAll()
        queued.forEach(perform)
    }

    func accept(url: URL) {
        guard let invocation = CommandURLCodec.decode(url) else { return }
        if ready {
            perform(invocation)
        } else {
            pending.append(invocation)
        }
    }

    func perform(_ invocation: CommandInvocation) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.perform(invocation) }
            return
        }
        // 命令来自访达菜单，此时访达在前台；不主动激活的话，
        // 弹出的路径选择/进度窗口会被压在后面，看起来像"点了没反应"。
        NSApp.activate(ignoringOtherApps: true)
        switch invocation.action {
        case .open:
            main?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        case .register:
            register(paths: invocation.paths)
        case .checkout:
            showCheckout()
        case .refresh:
            refresh(invocation.paths)
        case .copyURL:
            copyURL(invocation.paths)
        default:
            guard let path = invocation.paths.first, let database else { return }
            guard let copy = database.workingCopy(containing: path) else {
                Dialog.info("未登记", "这个路径不在已登记的工作副本里。")
                return
            }
            deliver(invocation, root: URL(fileURLWithPath: copy.path))
        }
    }

    func register(paths: [String]) {
        let chosen: String?
        if let first = paths.first {
            chosen = first
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "登记"
            chosen = panel.runModal() == .OK ? panel.url?.path : nil
        }
        guard let chosen else { return }
        if PathID.isCloudMirror(chosen) {
            Dialog.info("云盘目录", "访达扩展可能不会在这个目录显示菜单。主窗口里仍然可以操作。")
        }
        let cwd = URL(fileURLWithPath: chosen)
        launch(title: "登记", actionArgs: SvnCommands.info([chosen]), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            guard let self, let database = self.database else { return }
            guard result.code == 0, let info = SvnXML.parseInfo(result.stdoutText) else {
                Dialog.info("不是工作副本", result.combinedText.isEmpty ? "svn info 失败。" : result.combinedText)
                return
            }
            let root = info.wcRoot.isEmpty ? chosen : info.wcRoot
            database.upsert(WorkingCopy(path: root, url: info.url, revision: info.revision, repositoryRoot: info.repositoryRoot))
            self.monitor?.rewatch()
            self.monitor?.scan(root: root)
            self.main?.reload()
            self.main?.setStatus("已登记 \(root)")
        }
    }

    private func deliver(_ invocation: CommandInvocation, root: URL) {
        let paths = invocation.paths.map(PathID.normalize)
        switch invocation.action {
        case .update:
            withPaths(invocation, paths) { [weak self] chosen in
                self?.launch(title: "更新", actionArgs: SvnCommands.update(chosen, revision: nil), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { _ in
                    self?.monitor?.scan(root: root.path)
                }
            }
        case .updateToRevision:
            guard let revision = Dialog.ask("更新至指定版本", "填写修订版本号，或 {日期}。", value: "HEAD") else { return }
            guard revision == "HEAD" || RevisionInput.isValid(revision) else {
                Dialog.info("修订版本无效", "只接受数字或 {日期}。")
                return
            }
            let value = revision == "HEAD" ? nil : revision
            launch(title: "更新至指定版本", actionArgs: SvnCommands.update(paths, revision: value), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { [weak self] _ in
                self?.monitor?.scan(root: root.path)
            }
        case .commit:
            prepareCommit(paths: paths, cwd: root)
        case .add:
            withPaths(invocation, paths) { [weak self] chosen in
                guard let self else { return }
                let depth = self.addDepth(for: chosen)
                guard let depth else { return }
                self.launch(title: "增加", actionArgs: SvnCommands.add(chosen, depth: depth), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { _ in
                    self.monitor?.scan(root: root.path)
                }
            }
        case .undoAdd, .revert:
            withPaths(invocation, paths) { [weak self] chosen in
                let recursive = chosen.contains { self?.isDirectory($0) == true }
                self?.launch(title: "恢复", actionArgs: SvnCommands.revert(chosen, recursive: recursive), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { _ in
                    self?.monitor?.scan(root: root.path)
                }
            }
        case .deleteVersioned:
            withPaths(invocation, paths) { [weak self] chosen in
                guard Dialog.confirm("从版本库删除", "这些路径会从工作副本中删掉，并在下次提交时从版本库删除。\n\(chosen.joined(separator: "\n"))", ok: "删除") else { return }
                self?.launch(title: "删除", actionArgs: SvnCommands.delete(chosen), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { _ in
                    self?.monitor?.scan(root: root.path)
                }
            }
        case .copy, .move:
            // 文档：先记录来源，「粘贴」时才真正执行 svn copy / move
            guard let database else { return }
            var clip = database.loadClipboard()
            clip.paths = paths
            clip.isMove = invocation.action == .move
            database.saveClipboard(clip)
            let verb = invocation.action == .move ? "剪切" : "复制"
            main?.setStatus("已\(verb) \(paths.count) 项，选中目标文件夹后执行「粘贴」")
        case .paste:
            paste(paths: paths, root: root)
        case .lock:
            withPaths(invocation, paths) { [weak self] chosen in
                guard !chosen.isEmpty else { return }
                self?.launch(title: "加锁", actionArgs: SvnCommands.lock(chosen, message: nil), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { _ in
                    self?.monitor?.scan(root: root.path)
                }
            }
        case .unlock:
            launch(title: "解锁", actionArgs: SvnCommands.unlock(paths), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { [weak self] _ in
                self?.monitor?.scan(root: root.path)
            }
        case .compareLater:
            guard let database, let path = paths.first else { return }
            var clip = database.loadClipboard()
            clip.compareBase = PathID.normalize(path)
            database.saveClipboard(clip)
            main?.setStatus("已记下「\(URL(fileURLWithPath: path).lastPathComponent)」，再选另一个文件即可比较")
        case .compareWith:
            guard let database,
                  let base = database.loadClipboard().compareBase,
                  let path = paths.first else {
                Dialog.info("比较", "先用「稍后比较」记下一个文件。")
                return
            }
            showTwoDiff(base, path, cwd: root)
        case .trashUnversioned:
            for path in paths {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            }
            monitor?.scan(root: root.path)
        case .diffBase:
            showBaseDiff(paths[0], cwd: root)
        case .diffTwo:
            guard paths.count >= 2 else { return }
            showTwoDiff(paths[0], paths[1], cwd: root)
        case .info:
            launch(title: "信息", actionArgs: SvnCommands.info([paths[0]]), cwd: root, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
                guard result.code == 0, let info = SvnXML.parseInfo(result.stdoutText) else {
                    Dialog.info("信息", result.combinedText)
                    return
                }
                let text = ["URL: \(info.url)", "相对 URL: \(info.relativeURL)", "版本库: \(info.repositoryRoot)", "修订版本: \(info.revision)", "调度: \(info.schedule)", "深度: \(info.depth)", "工作副本: \(info.wcRoot)"].joined(separator: "\n")
                self?.show(TextWindow(title: "信息", text: text))
            }
        case .changes:
            showChanges(root)
        case .log:
            showLog(paths[0], cwd: root)
        case .cleanup:
            guard let options = Dialog.cleanupOptions() else { return }
            if options.unversioned || options.ignored {
                guard Dialog.confirm("删除文件", "清理会永久删除未版本化或被忽略的文件。", ok: "删除未版本化文件") else { return }
            }
            launch(title: "清理", actionArgs: SvnCommands.cleanup(root.path, unversioned: options.unversioned, ignored: options.ignored), cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { [weak self] _ in
                self?.monitor?.scan(root: root.path)
            }
        default:
            break
        }
    }

    private func prepareCommit(paths: [String], cwd: URL) {
        launch(title: "读取状态", actionArgs: SvnCommands.status(cwd.path), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            guard let self, result.code == 0 else {
                Dialog.info("无法读取状态", result.combinedText)
                return
            }
            let wanted = Set(paths)
            let entries = SvnXML.parseStatus(result.stdoutText, cwd: cwd).filter { entry in
                guard ["added", "modified", "deleted", "replaced", "conflicted"].contains(entry.item) else { return false }
                // 除了选中项本身及其子项，还要带上「选中项的祖先」：
                // 稀疏检出里用 add --parents 加进来的父目录同样是 A 状态，
                // 只提交文件本身 svn 会报 E200009（父目录不在提交里）。
                return wanted.contains { target in
                    PathID.isInside(entry.path, root: target)
                        || PathID.isInside(target, root: entry.path)
                }
            }
            guard !entries.isEmpty else {
                Dialog.info("提交", "没有可提交的改动。")
                return
            }
            let history = self.database?.loadSettings().commitMessageHistory ?? []
            let window = CommitWindow(entries: entries, history: history) { [weak self] message, chosen in
                self?.launch(title: "提交", actionArgs: SvnCommands.commit(chosen, message: message), cwd: cwd, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { result in
                    if result.code == 0 {
                        self?.database?.rememberCommitMessage(message)
                        self?.monitor?.scan(root: cwd.path)
                    }
                }
            }
            self.show(window)
        }
    }

    private func showChanges(_ root: URL) {
        launch(title: "检视修改", actionArgs: SvnCommands.status(root.path), cwd: root, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            guard result.code == 0 else {
                Dialog.info("检视修改", result.combinedText)
                return
            }
            let entries = SvnXML.parseStatus(result.stdoutText, cwd: root).filter { $0.badge != nil }
            let window = ChangesWindow(entries: entries) { [weak self] entry in
                self?.showBaseDiff(entry.path, cwd: root)
            }
            self?.show(window)
        }
    }

    private func showLog(_ path: String, cwd: URL) {
        launch(title: "日志", actionArgs: SvnCommands.log(path), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            guard result.code == 0 else {
                Dialog.info("日志", result.combinedText)
                return
            }
            let entries = SvnXML.parseLog(result.stdoutText)
            let window = LogWindow(entries: entries) { [weak self] entry in
                self?.launch(title: "r\(entry.revision)", actionArgs: SvnCommands.diffRevision(path, revision: entry.revision), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 1, quiet: true) { diff in
                    self?.show(TextWindow(title: "r\(entry.revision)", text: diff.stdoutText.isEmpty ? diff.combinedText : diff.stdoutText))
                }
            }
            self?.show(window)
        }
    }

    private func showBaseDiff(_ path: String, cwd: URL) {
        let tool = database?.loadSettings().externalDiffTool ?? ""
        launch(title: "比较", actionArgs: SvnCommands.catBase(path), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] base in
            guard let self else { return }
            if base.code != 0 {
                self.launch(title: "比较", actionArgs: SvnCommands.diff([path]), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 1, quiet: true) { diff in
                    self.show(TextWindow(title: "比较", text: diff.combinedText))
                }
                return
            }
            let local = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
            if !tool.isEmpty {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("macsvn-base-\(UUID().uuidString)")
                try? base.stdout.write(to: temp)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: tool)
                task.arguments = [temp.path, path]
                try? task.run()
                return
            }
            if base.stdout.prefix(8000).contains(0) || local.prefix(8000).contains(0) {
                self.show(TextWindow(title: "比较", text: "二进制文件不同。"))
                return
            }
            let left = String(data: base.stdout, encoding: .utf8) ?? ""
            let right = String(data: local, encoding: .utf8) ?? ""
            self.show(DiffWindow(title: "比较", leftTitle: "BASE", left: left, rightTitle: "工作副本", right: right))
        }
    }

    private func showTwoDiff(_ old: String, _ new: String, cwd: URL) {
        launch(title: "比较", actionArgs: SvnCommands.diffTwo(old: old, new: new), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            self?.show(TextWindow(title: "比较", text: result.combinedText))
        }
    }

    private func copyURL(_ paths: [String]) {
        guard let path = paths.first else { return }
        let cwd = URL(fileURLWithPath: path)
        launch(title: "复制 URL", actionArgs: SvnCommands.info([path]), cwd: cwd, write: false, password: nil, username: nil, trust: false, promptsLeft: 2, quiet: true) { [weak self] result in
            guard result.code == 0, let info = SvnXML.parseInfo(result.stdoutText), !info.url.isEmpty else {
                Dialog.info("复制 URL", result.combinedText)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info.url, forType: .string)
            self?.main?.setStatus("已复制 URL")
        }
    }

    private func refresh(_ paths: [String]) {
        guard let database else { return }
        let roots = Set(paths.compactMap { database.workingCopy(containing: $0)?.path })
        if roots.isEmpty {
            database.loadWorkingCopies().forEach { monitor?.scan(root: $0.path) }
        } else {
            roots.forEach { monitor?.scan(root: $0) }
        }
    }

    private func showCheckout() {
        let window = CheckoutWindow { [weak self] url, revision, parent, name in
            guard RevisionInput.isValid(revision) || revision.isEmpty else {
                Dialog.info("修订版本无效", "只接受数字或 {日期}。")
                return
            }
            let target = URL(fileURLWithPath: parent).appendingPathComponent(name).path
            self?.launch(title: "检出", actionArgs: SvnCommands.checkout(url: url, target: target, revision: revision.isEmpty ? nil : revision), cwd: URL(fileURLWithPath: parent), write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { result in
                guard result.code == 0 else { return }
                self?.register(paths: [target])
            }
        }
        show(window)
    }

    /// 把窗口提到所有应用之上。macOS 14+ 的 activate 常被忽略，
    /// orderFrontRegardless 不依赖激活状态，能保证用户看到反馈。
    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func withPaths(_ invocation: CommandInvocation, _ paths: [String], then: @escaping ([String]) -> Void) {
        guard let database else { return }
        let configured = database.loadSettings().asksForPaths(invocation.action)
        let ask = invocation.shift ? !configured : configured
        guard ask else {
            then(paths)
            return
        }
        let window = PathPickWindow(paths: paths) { chosen in
            if let chosen, !chosen.isEmpty { then(chosen) }
        }
        show(window)
    }

    private func launch(
        title: String,
        actionArgs: [String],
        cwd: URL,
        write: Bool,
        password: String?,
        username: String?,
        trust: Bool,
        promptsLeft: Int,
        quiet: Bool = false,
        finish: @escaping (SvnResult) -> Void
    ) {
        guard let database else { return }
        let exe = database.loadSettings().svnPath
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            Dialog.info("找不到 svn", exe)
            return
        }
        let root = PathID.normalize(cwd.path)
        if write {
            if busy.contains(root) {
                Dialog.info("工作副本正忙", "请等当前写入命令结束。")
                return
            }
            busy.insert(root)
        }
        let account = database.workingCopy(containing: cwd.path)?.repositoryRoot ?? ""
        let name = username ?? database.workingCopy(containing: cwd.path)?.username
        let args = SvnCommands.globals(interactive: password != nil, username: name, trust: trust) + actionArgs
        // quiet：只读的取数命令（日志/状态/信息/比较）不弹进度窗口。
        // 这类输出是给程序解析的，原样显示出来只是一屏 XML；它们的失败
        // 已经由各自的 finish 用对话框或文本窗口呈现，不需要第二个框。
        // 成功时不弹命令窗口：默认只在失败时把窗口叫出来给出错信息，
        // 免得每次提交/更新都弹一屏 svn 原始输出。
        let deferWindow = !quiet && database.loadSettings().hideProgressOnSuccess
        let progress = ProgressWindow()
        var presented = false
        if !quiet, !deferWindow {
            keep(progress)
            progress.present(title: title, command: SvnTask.display(exe: exe, args: args))
            presented = true
        }
        let task = SvnTask()
        progress.onStop = { task.cancel() }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: SvnResult
            if let password {
                result = task.runPty(exe: exe, args: args, cwd: cwd, username: name ?? "", password: password) { chunk in
                    if presented { progress.append(chunk) }
                }
            } else {
                result = task.run(exe: exe, args: args, cwd: cwd) { chunk in
                    if presented { progress.append(chunk) }
                }
            }
            DispatchQueue.main.async {
                if write { self.busy.remove(root) }
                if !quiet {
                    if presented {
                        progress.finish(result)
                    } else if result.code != 0 {
                        // 失败才把窗口叫出来，让用户看到 svn 的错误输出
                        self.keep(progress)
                        progress.present(title: title, command: SvnTask.display(exe: exe, args: args))
                        progress.append(result.combinedText)
                        progress.finish(result)
                    }
                }
                AppLog.write("\(result.display) -> \(result.code)")
                if result.code != 0, promptsLeft > 0, SvnFailure.isCertificate(result), !trust,
                   Dialog.confirm("证书不受信任", "是否只对下一次尝试临时信任服务器证书？", ok: "临时信任") {
                    self.launch(title: title, actionArgs: actionArgs, cwd: cwd, write: write, password: password, username: name, trust: true, promptsLeft: promptsLeft - 1, finish: finish)
                    return
                }
                if result.code != 0, promptsLeft > 0, SvnFailure.isAuth(result) {
                    if password == nil, let saved = KeychainPassword.load(account: account), !saved.isEmpty {
                        self.launch(title: title, actionArgs: actionArgs, cwd: cwd, write: write, password: saved, username: name, trust: trust, promptsLeft: promptsLeft - 1, finish: finish)
                        return
                    }
                    if let entered = Dialog.credentials(host: account.isEmpty ? cwd.path : account, username: name ?? "") {
                        if entered.save { KeychainPassword.save(account: account.isEmpty ? cwd.path : account, password: entered.password) }
                        if var copy = database.workingCopy(containing: cwd.path) {
                            copy.username = entered.user
                            database.upsert(copy)
                        }
                        self.launch(title: title, actionArgs: actionArgs, cwd: cwd, write: write, password: entered.password, username: entered.user, trust: trust, promptsLeft: promptsLeft - 1, finish: finish)
                        return
                    }
                }
                if result.code == 0 { self.main?.setStatus("\(title) 完成") }
                finish(result)
            }
        }
    }

    /// 文档的「粘贴」：把先前 复制/剪切 记下的来源落到现在选中的目标文件夹。
    private func paste(paths: [String], root: URL) {
        guard let database else { return }
        let clip = database.loadClipboard()
        guard !clip.paths.isEmpty else {
            Dialog.info("粘贴", "先用「复制/移动」里的「复制到剪贴板」或「剪切到剪贴板」。")
            return
        }
        guard let target = paths.first else { return }
        let isDir = isDirectory(target)
        guard isDir else {
            Dialog.info("粘贴", "请选中一个文件夹作为目标。")
            return
        }
        let sources = clip.paths.filter { PathID.normalize($0) != PathID.normalize(target) }
        guard !sources.isEmpty else {
            Dialog.info("粘贴", "来源和目标相同，无法粘贴。")
            return
        }
        let args = clip.isMove
            ? SvnCommands.move(sources, to: target)
            : SvnCommands.copy(sources, to: target)
        let title = clip.isMove ? "移动" : "复制"
        launch(title: title, actionArgs: args, cwd: root, write: true, password: nil, username: nil, trust: false, promptsLeft: 2) { [weak self] result in
            guard result.code == 0 else { return }
            var cleared = database.loadClipboard()
            cleared.paths = []
            database.saveClipboard(cleared)
            self?.monitor?.scan(root: root.path)
        }
    }

    private func addDepth(for paths: [String]) -> String? {
        guard paths.contains(where: { isDirectory($0) }) else { return "empty" }
        let alert = NSAlert()
        alert.messageText = "增加"
        alert.informativeText = "目录是否包含其中的文件？"
        alert.addButton(withTitle: "包含子项")
        alert.addButton(withTitle: "仅这一层")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return "infinity"
        case .alertSecondButtonReturn: return "empty"
        default: return nil
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func show(_ controller: NSWindowController) {
        keep(controller)
        controller.showWindow(nil)
        // macOS 14+ 不再允许后台应用抢焦点，单靠 activate 窗口仍可能被访达盖住。
        // orderFrontRegardless 能把窗口提到最前，用户才看得到"点了有反应"。
        controller.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func keep(_ controller: NSWindowController) {
        windows.append(controller)
        controller.window?.delegate = self
        controller.window?.isReleasedWhenClosed = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0.window == window }
    }
}
