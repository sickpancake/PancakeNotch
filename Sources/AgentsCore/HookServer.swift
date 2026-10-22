import Darwin
import Foundation
import os

/// One event from the hook helper, with the few fields PancakeNotch uses (never prompts or file
/// contents).
struct HookEvent: Sendable {
    let tool: AgentTool
    /// The tool's event name ("PermissionRequest", "Stop", "beforeSubmitPrompt"…).
    let name: String
    /// The helper's parent: the agent's own process (or its shell), to find the app it runs in.
    let parentPID: pid_t
    /// Set while the helper waits for Allow / Deny.
    var requestID: Int?
    /// Claude and Codex: `session_id`; Cursor: `conversation_id`.
    var sessionID: String?
    /// Codex's current turn, used to confirm who reviews its permission requests.
    var turnID: String?
    var permissionMode: String?
    var cwd: String?
    var transcriptPath: String?
    var title: String?
    /// "Wants to run: npm test" (permission requests) or "Running npm test" (Cursor's steps).
    var summary: String?
    var notificationType: String?
    /// A notification's text, or an error's.
    var message: String?
    /// Cursor's stop status ("completed", "aborted", "error").
    var status: String?
    /// Codex: the session's model ("codex-auto-review" for its automatic reviewer).
    var model: String?

    init(tool: AgentTool, name: String, parentPID: pid_t, payload: [String: Any]) {
        self.tool = tool
        self.name = name
        self.parentPID = parentPID
        sessionID = payload["session_id"] as? String ?? payload["conversation_id"] as? String
        turnID = payload["turn_id"] as? String
        permissionMode = payload["permission_mode"] as? String
        cwd = payload["cwd"] as? String ?? (payload["workspace_roots"] as? [String])?.first
        transcriptPath = payload["transcript_path"] as? String
        title = payload["session_title"] as? String
        notificationType = payload["notification_type"] as? String
        message = payload["message"] as? String ?? payload["error"] as? String
        status = payload["status"] as? String
        model = payload["model"] as? String
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        if let toolName = payload["tool_name"] as? String {
            summary = AgentSteps.request(tool: toolName, input: input)
        } else if name == "afterShellExecution" {
            summary = AgentSteps.step(tool: "Shell", input: payload)
        } else if name == "afterFileEdit" {
            summary = AgentSteps.step(tool: "edit_file", input: payload)
        }
    }
}

/// Listens on PancakeNotch's agents socket for the hook helper (ADR-0037). Each connection is one event:
/// a header line with the body's length, then the tool's JSON. Permission requests stay connected until
/// `answer(_:with:)`; if the helper goes away first (the tool gave up waiting), `onGone` says so.
/// Runs on its own queue; callbacks arrive on the main actor.
final class HookServer: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.agents.socket", qos: .userInitiated)
    private let onEvent: @MainActor @Sendable (HookEvent) -> Void
    private let onGone: @MainActor @Sendable (Int) -> Void
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "agents")

    private var listener: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var waiting: [Int: Int32] = [:]
    private var nextRequest = 1

    static let maxHeader = 1024
    static let maxBody = 4 * 1024 * 1024 + 1024

    private final class Client {
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var header: [String: Any]?
        var requestID: Int?

        init(fd: Int32) { self.fd = fd }
    }

    init(path: String, onEvent: @escaping @MainActor @Sendable (HookEvent) -> Void, onGone: @escaping @MainActor @Sendable (Int) -> Void) {
        self.path = path
        self.onEvent = onEvent
        self.onGone = onGone
    }

    /// Opens the socket (taking it over from an older copy of the app). Returns whether it listens.
    @discardableResult
    func start() -> Bool {
        queue.sync { listen() }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for client in clients.values { client.source?.cancel() }
            clients = [:]
            waiting = [:]
            unlink(path)
        }
    }

    /// Sends Allow / Deny (`output`, the tool's JSON) to a waiting helper, or with nil hands the request
    /// back to the tool's own window.
    func answer(_ requestID: Int, with output: String?) {
        queue.async { [self] in
            guard let fd = waiting.removeValue(forKey: requestID), let client = clients[fd] else { return }
            if let output {
                let line = Array((output + "\n").utf8)
                _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            }
            close(client)
        }
    }

    // MARK: Socket

    private func listen() -> Bool {
        guard listener == nil else { return true }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            logger.error("Agents socket path too long")
            return false
        }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            logger.error("Agents socket couldn't listen: \(errno)")
            Darwin.close(fd)
            return false
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { Darwin.close(fd) }
        listener = source
        source.resume()
        return true
    }

    private func acceptAll(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            // Only this user's processes may talk to PancakeNotch.
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                Darwin.close(fd)
                continue
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let client = Client(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self, weak client] in
                guard let self, let client else { return }
                self.read(client)
            }
            source.setCancelHandler { Darwin.close(fd) }
            client.source = source
            clients[fd] = client
            source.resume()
        }
    }

    private func read(_ client: Client) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = Darwin.read(client.fd, &chunk, chunk.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else {
            // The helper went away: done sending, or it stopped waiting for an answer.
            if let requestID = client.requestID, waiting.removeValue(forKey: requestID) != nil {
                let onGone = onGone
                Task { @MainActor in onGone(requestID) }
            }
            close(client)
            return
        }
        // A waiting helper sends nothing more; ignore anything that arrives.
        guard client.requestID == nil else { return }
        client.buffer.append(contentsOf: chunk[0..<count])
        if client.header == nil {
            guard let newline = client.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
                if client.buffer.count > Self.maxHeader { close(client) }
                return
            }
            let line = client.buffer[client.buffer.startIndex..<newline]
            guard let header = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  (header["length"] as? Int).map({ (0...Self.maxBody).contains($0) }) == true else {
                close(client)
                return
            }
            client.header = header
            client.buffer = Data(client.buffer[client.buffer.index(after: newline)...])
        }
        guard let header = client.header, let length = header["length"] as? Int, client.buffer.count >= length else { return }
        deliver(header: header, body: client.buffer.prefix(length), from: client)
    }

    private func deliver(header: [String: Any], body: Data, from client: Client) {
        let payload = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        guard let tool = (header["tool"] as? String).flatMap(AgentTool.init(rawValue:)), let name = header["event"] as? String else {
            close(client)
            return
        }
        var event = HookEvent(tool: tool, name: name, parentPID: pid_t(clamping: header["ppid"] as? Int ?? 0), payload: payload)
        client.buffer = Data()
        // Codex runs this hook BEFORE automatic review or a user prompt. Only intercept a confirmed
        // user-reviewed turn; closing with no decision lets Codex follow its own approval path.
        if tool == .codex, name == "PermissionRequest", !CodexApprovalRouting.needsUser(event) {
            close(client)
            return
        }
        if header["waits"] as? Bool == true {
            let requestID = nextRequest
            nextRequest += 1
            client.requestID = requestID
            waiting[requestID] = client.fd
            event.requestID = requestID
        } else {
            close(client)
        }
        let onEvent = onEvent
        let delivered = event
        Task { @MainActor in onEvent(delivered) }
    }

    private func close(_ client: Client) {
        clients[client.fd] = nil
        client.source?.cancel()
        client.source = nil
    }
}
