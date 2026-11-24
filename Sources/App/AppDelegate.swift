import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: AppDatabase!
    private var monitor: StatusMonitor!
    private var main: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        database = AppDatabase(root: SupportPaths.root)
        monitor = StatusMonitor(database: database)
        main = MainWindowController(database: database)
        CommandCenter.shared.configure(database: database, monitor: monitor, main: main)
        monitor.onStatus = { [weak main] text in
            main?.setStatus(text)
        }
        main.showWindow(nil)
        monitor.start()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            ExtensionDiagnostics.showIfNeeded(workingCopyCount: self.database.loadWorkingCopies().count)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { CommandCenter.shared.accept(url: $0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            main.showWindow(nil)
        }
        return true
    }
}
