import Foundation
import CoreServices

final class StatusMonitor {
    private let database: AppDatabase
    private let queue = DispatchQueue(label: "local.macsvn.status")
    private var streams: [String: FSEventStreamRef] = [:]
    private var boxes: [String: WatchBox] = [:]
    private var tasks: [String: SvnTask] = [:]
    private var generations: [String: Int] = [:]
    private var pending: [String: DispatchWorkItem] = [:]
    var onStatus: ((String) -> Void)?

    init(database: AppDatabase) {
        self.database = database
    }

    func start() {
        rewatch()
        for copy in database.loadWorkingCopies() {
            scan(root: copy.path)
        }
    }

    func rewatch() {
        let roots = Set(database.loadWorkingCopies().map { PathID.normalize($0.path) })
        for root in streams.keys where !roots.contains(root) {
            stop(root)
        }
        for root in roots where streams[root] == nil {
            watch(root)
        }
    }

    func schedule(root: String) {
        let root = PathID.normalize(root)
        pending[root]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.scan(root: root)
        }
        pending[root] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func scan(root: String) {
        let root = PathID.normalize(root)
        tasks[root]?.cancel()
        let generation = (generations[root] ?? 0) + 1
        generations[root] = generation
        let task = SvnTask()
        tasks[root] = task
        let exe = database.loadSettings().svnPath
        let args = SvnCommands.globals(interactive: false, username: nil, trust: false) + SvnCommands.status(root)
        let lockArgs = SvnCommands.globals(interactive: false, username: nil, trust: false) + SvnCommands.needsLock(root)
        DispatchQueue.global(qos: .utility).async {
            // needs-lock 决定「加锁」菜单是否可用，和状态一起刷
            let lockResult = task.run(exe: exe, args: lockArgs, cwd: URL(fileURLWithPath: root)) { _ in }
            let needsLock = lockResult.code == 0 ? SvnXML.parseNeedsLock(lockResult.stdoutText, cwd: URL(fileURLWithPath: root)) : []
            let result = task.run(exe: exe, args: args, cwd: URL(fileURLWithPath: root)) { _ in }
            DispatchQueue.main.async {
                guard self.generations[root] == generation, !result.cancelled else { return }
                guard result.code == 0 else {
                    self.onStatus?("状态扫描失败：\(URL(fileURLWithPath: root).lastPathComponent)")
                    AppLog.write("\(result.display) -> \(result.code)")
                    return
                }
                let entries = SvnXML.parseStatus(result.stdoutText, cwd: URL(fileURLWithPath: root))
                let badges = BadgeMap.make(entries: entries, root: root)
                self.database.replaceStatus(root: root, badges: badges, scanned: true, needsLock: needsLock)
                self.onStatus?("已刷新 \(URL(fileURLWithPath: root).lastPathComponent)")
            }
        }
    }

    private func watch(_ root: String) {
        let box = WatchBox(monitor: self, root: root)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            nil,
            statusEventCallback,
            &context,
            [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        ) else { return }
        boxes[root] = box
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            streams[root] = stream
        }
    }

    private func stop(_ root: String) {
        if let stream = streams[root] {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams[root] = nil
        boxes[root] = nil
    }
}

private final class WatchBox {
    weak var monitor: StatusMonitor?
    let root: String
    init(monitor: StatusMonitor, root: String) {
        self.monitor = monitor
        self.root = root
    }
}

private func statusEventCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let box = Unmanaged<WatchBox>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    if !paths.isEmpty, paths.allSatisfy({ $0.contains("/.svn/") }) {
        return
    }
    DispatchQueue.main.async {
        box.monitor?.schedule(root: box.root)
    }
}
