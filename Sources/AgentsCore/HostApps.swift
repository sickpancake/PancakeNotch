import AppKit
import Darwin

/// Finds the app an agent runs in, by walking up from its process to the first regular app: `claude`
/// → zsh → Terminal, or `claude` → T3 Code's helper → T3 Code. Called only when needed (a click, a
/// change), never on a timer.
enum HostApps {
    /// The regular app (Dock icon) `pid` runs under, if it's still running.
    static func app(containing pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 where current > 1 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parent(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
