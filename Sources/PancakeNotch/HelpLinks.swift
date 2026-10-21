import AppKit

/// The website's Help topics. Each is an anchor on the Help page (`help/#<topic>`).
enum HelpTopic: String, CaseIterable {
    case firstLaunch = "first-launch"
    case notchNotShowing = "notch-not-showing"
    case musicNotDetected = "music-not-detected"
    case musicControls = "music-controls"
    case soundBars = "sound-bars"
    case fullScreen = "full-screen"
    case shortcut
    case shelf
    case updates
    case launchAtLogin = "launch-at-login"
    case privacy
    case uninstall
    case report
}

/// Links to the website and to GitHub, all from one base address so the site can move without
/// touching the app's help (ADR-0027).
enum HelpLinks {
    /// The website (GitHub Pages).
    static let website = URL(string: "https://sickpancake.github.io/PancakeNotch/")!

    static var helpPage: URL { URL(string: "help/", relativeTo: website)!.absoluteURL }

    static func url(_ topic: HelpTopic) -> URL {
        URL(string: "help/#\(topic.rawValue)", relativeTo: website)!.absoluteURL
    }

    /// A new bug report in the browser, filled in with only the app version, macOS version and Mac
    /// model. Nothing is sent unless the user submits it on GitHub.
    static var reportProblem: URL {
        var components = URLComponents(url: AppInfo.sourceCode.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: reportBody),
        ]
        return components.url!
    }

    /// The same headings as the bug report template, with the Mac's details filled in.
    static var reportBody: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        **What happened?**


        **What did you expect?**


        **Steps to reproduce**
        1.
        2.

        **Your Mac**
        - Model: \(macModel)
        - macOS version: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        - PancakeNotch version: \(AppInfo.version)
        - Music app (if Now Playing related):
        """
    }

    /// The model identifier, e.g. "Mac15,3".
    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "–" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// System Settings › Desktop & Dock (the Mission Control setting that can get in the way of drops).
    static func openDesktopAndDockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// System Settings › Privacy & Security › Automation (Music and Spotify control).
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
