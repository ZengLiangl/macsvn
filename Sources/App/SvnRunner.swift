import Darwin
import Foundation

struct SvnResult {
    var code: Int32
    var stdout: Data
    var stderr: Data
    var display: String
    var cancelled: Bool

    var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    var combinedText: String { stdoutText + stderrText }
}

final class SvnTask {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        process?.terminate()
        lock.unlock()
    }

    func run(exe: String, args: [String], cwd: URL?, onChunk: @escaping (String) -> Void) -> SvnResult {
        runPipes(exe: exe, args: args, cwd: cwd, onChunk: onChunk)
    }

    func runPty(exe: String, args: [String], cwd: URL?, username: String, password: String, onChunk: @escaping (String) -> Void) -> SvnResult {
        let display = Self.display(exe: exe, args: args)
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            return SvnResult(code: 127, stdout: Data(), stderr: Data("无法打开终端来输入密码。请先在终端执行一次 svn info。".utf8), display: display, cancelled: false)
        }
        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        proc.environment = Self.childEnvironment()
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle
        lock.lock()
        if cancelled {
            lock.unlock()
            close(master)
            close(slave)
            return SvnResult(code: -1, stdout: Data(), stderr: Data(), display: display, cancelled: true)
        }
        process = proc
        lock.unlock()
        do {
            try proc.run()
        } catch {
            close(master)
            close(slave)
            return SvnResult(code: 127, stdout: Data(), stderr: Data(error.localizedDescription.utf8), display: display, cancelled: false)
        }
        close(slave)
        var data = Data()
        var sentUser = username.isEmpty
        var sentPass = false
        while true {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                let chunk = Data(buffer.prefix(count))
                data.append(chunk)
                let piece = String(data: chunk, encoding: .utf8) ?? ""
                DispatchQueue.main.async { onChunk(piece) }
                let text = String(data: data, encoding: .utf8) ?? ""
                if !sentUser, text.contains("Username:") {
                    write(master, (username + "\n"), &sentUser)
                }
                if !sentPass, text.contains("Password") {
                    _ = writeLine(master, password)
                    sentPass = true
                }
                if text.contains("(R)eject") || text.contains("(p)ermanently") {
                    _ = writeLine(master, "t")
                }
            } else if count == 0 {
                break
            } else if errno != EAGAIN {
                break
            }
            if !proc.isRunning {
                if count <= 0 { break }
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        proc.waitUntilExit()
        close(master)
        let cancelled = proc.terminationReason == .uncaughtSignal
        return SvnResult(code: proc.terminationStatus, stdout: data, stderr: Data(), display: display, cancelled: cancelled)
    }

    private func write(_ fd: Int32, _ text: String, _ flag: inout Bool) {
        if writeLine(fd, text.replacingOccurrences(of: "\n", with: "")) {
            flag = true
        }
    }

    private func writeLine(_ fd: Int32, _ text: String) -> Bool {
        let line = text + "\n"
        return line.withCString { pointer in
            Darwin.write(fd, pointer, strlen(pointer)) > 0
        }
    }

    private func runPipes(exe: String, args: [String], cwd: URL?, onChunk: @escaping (String) -> Void) -> SvnResult {
        let display = Self.display(exe: exe, args: args)
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            return SvnResult(code: 127, stdout: Data(), stderr: Data("找不到 svn：\(exe)".utf8), display: display, cancelled: false)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        proc.environment = Self.childEnvironment()
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled {
            lock.unlock()
            return SvnResult(code: -1, stdout: Data(), stderr: Data(), display: display, cancelled: true)
        }
        process = proc
        lock.unlock()
        do {
            try proc.run()
        } catch {
            return SvnResult(code: 127, stdout: Data(), stderr: Data("无法启动 svn：\(error.localizedDescription)".utf8), display: display, cancelled: false)
        }
        let group = DispatchGroup()
        let box = OutputBox()
        group.enter()
        DispatchQueue.global().async {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            box.stdout = data
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { onChunk(text) }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            box.stderr = data
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { onChunk(text) }
            group.leave()
        }
        group.wait()
        proc.waitUntilExit()
        return SvnResult(
            code: proc.terminationStatus,
            stdout: box.stdout,
            stderr: box.stderr,
            display: display,
            cancelled: proc.terminationReason == .uncaughtSignal
        )
    }

    /// 子进程环境。
    ///
    /// svn 需要 UTF-8 locale 才能处理非 ASCII 路径：没有 LANG/LC_ALL 时，
    /// svn 按「本地编码」把参数转成 UTF-8，中文路径会被转坏，报
    ///   E155010 找不到节点，或 E000022 Can't convert string from native encoding
    /// 从访达启动的 app 不继承 shell 的 locale，所以必须显式补上。
    /// 用 C.UTF-8 而非 zh_CN.UTF-8：错误与提示保持英文，便于匹配
    /// "Username:" / "Password" 等交互提示。
    static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C.UTF-8"
        env["LANG"] = "C.UTF-8"
        return env
    }

    static func display(exe: String, args: [String]) -> String {
        ([exe] + args).map { part in
            part.contains(" ") ? "\"\(part)\"" : part
        }.joined(separator: " ")
    }
}

private final class OutputBox {
    var stdout = Data()
    var stderr = Data()
}
