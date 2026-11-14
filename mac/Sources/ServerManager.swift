import Foundation
import Darwin

/// Runs the local Python server (server/server.py) from the cloned project folder.
/// If a server already answers on the port (e.g. started with scripts/run.sh), the app uses it and leaves it alone.
final class ServerManager {
    /// Written into Info.plist by build.sh. Override: defaults write <bundle id> projectPath /path/to/gqai-live
    static var projectURL: URL {
        if let p = UserDefaults.standard.string(forKey: "projectPath"), !p.isEmpty { return URL(fileURLWithPath: p) }
        let p = Bundle.main.object(forInfoDictionaryKey: "GQAIProjectPath") as? String ?? ""
        return URL(fileURLWithPath: p)
    }
    static var port: Int {
        let p = UserDefaults.standard.integer(forKey: "port")
        return p > 0 ? p : (Int(Bundle.main.object(forInfoDictionaryKey: "GQAIPort") as? String ?? "") ?? 7860)
    }
    static var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    static var logURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/GQAILive")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-server.log")
    }

    private var process: Process?
    private var stopping = false
    var onUnexpectedExit: (() -> Void)?

    func isAlive(timeout: TimeInterval = 1) -> Bool {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent("api/status"))
        req.timeoutInterval = timeout
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, res, _ in
            ok = (res as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 0.5)
        return ok
    }

    /// Starts (or attaches to) the server and waits until it answers. Throws a readable message on failure.
    func start(wait: TimeInterval = 30) throws {
        if isAlive() { return }
        let root = Self.projectURL
        let python = root.appendingPathComponent(".venv/bin/python")
        let script = root.appendingPathComponent("server/server.py")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: script.path) else {
            throw NSError(domain: "GQAILive", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "프로젝트 폴더를 찾을 수 없습니다: \(root.path)\nscripts/setup-mac.sh를 먼저 실행하고 mac/build.sh로 다시 빌드하세요."])
        }
        let fd = Darwin.open(Self.logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo:
                [NSLocalizedDescriptionKey: "서버 로그를 열지 못했습니다: \(Self.logURL.path)"])
        }
        let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let p = Process()
        p.executableURL = python
        p.arguments = [script.path]
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["GQAI_PORT"] = String(Self.port)
        // Apps launched from Finder get a minimal PATH.
        env["PATH"] = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        env["HOME"] = NSHomeDirectory()
        p.environment = env
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] _ in
            guard let self, !self.stopping else { return }
            DispatchQueue.main.async { self.process = nil; self.onUnexpectedExit?() }
        }
        try p.run()
        process = p
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if !p.isRunning { break }
            if isAlive() { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        stop()
        throw NSError(domain: "GQAILive", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "로컬 서버를 시작하지 못했습니다. 로그를 확인하세요:\n\(Self.logURL.path)"])
    }

    /// Stops the server only if this app started it (SIGTERM lets it also stop whisper-server).
    func stop() {
        guard let p = process else { return }
        stopping = true
        if p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(5)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
        stopping = false
    }
}
