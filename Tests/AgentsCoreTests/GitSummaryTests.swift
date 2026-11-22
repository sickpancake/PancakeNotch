import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct GitSummaryTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GitSummaryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func git(_ arguments: String..., in folder: URL) throws {
        let process = Process()
        process.executableURL = GitSummary.executable
        process.arguments = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments
        process.currentDirectoryURL = folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    private func write(_ text: String, to name: String, in folder: URL) throws {
        try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func repository() throws -> URL {
        let repo = try temporaryFolder()
        try git("init", "-q", "-b", "main", in: repo)
        try write("one\ntwo\nthree\n", to: "README.md", in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "First", in: repo)
        return repo
    }

    @Test func shortstatReadsEveryCount() {
        #expect(GitSummary.parseShortstat(" 3 files changed, 42 insertions(+), 7 deletions(-)\n")
            == DoneSummary(filesChanged: 3, insertions: 42, deletions: 7))
        #expect(GitSummary.parseShortstat(" 1 file changed, 1 insertion(+)\n") == DoneSummary(filesChanged: 1, insertions: 1, deletions: 0))
        #expect(GitSummary.parseShortstat(" 2 files changed, 5 deletions(-)\n") == DoneSummary(filesChanged: 2, insertions: 0, deletions: 5))
        #expect(GitSummary.parseShortstat("") == DoneSummary(filesChanged: 0, insertions: 0, deletions: 0))
        #expect(!GitSummary.parseShortstat("").hasChanges)
    }

    @Test func aFolderOutsideGitHasNoSummary() async throws {
        guard GitSummary.executable != nil else { return }
        let folder = try temporaryFolder()
        #expect(await GitSummary.head(cwd: folder.path) == nil)
        #expect(await GitSummary.summary(cwd: folder.path, since: nil, branch: nil) == nil)
        #expect(await GitSummary.summary(cwd: folder.appending(path: "gone").path, since: nil, branch: nil) == nil)
    }

    @Test func commitsAndUncommittedChangesSinceTheStartCount() async throws {
        guard GitSummary.executable != nil else { return }
        let repo = try repository()
        let start = try #require(await GitSummary.head(cwd: repo.path))
        try write("one\n2\nthree\nfour\n", to: "README.md", in: repo)
        try git("commit", "-q", "-am", "Number the lines", in: repo)
        try write("let x = 1\n", to: "New.swift", in: repo)

        let summary = try #require(await GitSummary.summary(cwd: repo.path, since: start, branch: "main"))
        #expect(summary == DoneSummary(branch: "main", filesChanged: 2, insertions: 2, deletions: 1, lastCommit: "Number the lines"))
    }

    @Test func withoutCommitsThereIsNoLastCommit() async throws {
        guard GitSummary.executable != nil else { return }
        let repo = try repository()
        let start = await GitSummary.head(cwd: repo.path)
        #expect(await GitSummary.summary(cwd: repo.path, since: start, branch: nil)
            == DoneSummary(filesChanged: 0, insertions: 0, deletions: 0))
        // Not knowing where it started, the uncommitted changes still count.
        try write("one\n", to: "README.md", in: repo)
        #expect(await GitSummary.summary(cwd: repo.path, since: nil, branch: nil)
            == DoneSummary(filesChanged: 1, insertions: 0, deletions: 2))
    }

    @Test func aFinishedThreadGetsItsSummaryAndPeeksWithIt() async throws {
        guard GitSummary.executable != nil else { return }
        let repo = try repository()
        let center = AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "GitSummaryTests.\(UUID().uuidString)")!))
        var alerts: [AgentAlert] = []
        center.onAlert = { alerts.append($0) }
        let started = Date().addingTimeInterval(-120)
        center.apply(.init(id: "claude:a", tool: .claude, at: started, cwd: repo.path, status: .working))
        for _ in 0..<200 where center.startCommits["claude:a"] == nil { try await Task.sleep(for: .milliseconds(10)) }
        try #require(center.startCommits["claude:a"] != nil)

        try write("one\ntwo\nthree\nfour\n", to: "README.md", in: repo)
        try git("commit", "-q", "-am", "Add a line", in: repo)
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .done))
        #expect(alerts.isEmpty)
        for _ in 0..<200 where center.threads.first?.doneSummary == nil { try await Task.sleep(for: .milliseconds(10)) }

        let expected = DoneSummary(branch: "main", filesChanged: 1, insertions: 1, deletions: 0, lastCommit: "Add a line")
        #expect(center.threads.first?.doneSummary == expected)
        #expect(alerts.map(\.kind) == [.finished])
        #expect(alerts.first?.thread.doneSummary == expected)

        // Working again clears it.
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .working))
        #expect(center.threads.first?.doneSummary == nil)
    }

    @Test func aDeferredFinishWaitsForItsSummaryToo() async throws {
        guard GitSummary.executable != nil else { return }
        let repo = try repository()
        let center = AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "GitSummaryTests.\(UUID().uuidString)")!))
        var alerts: [AgentAlert] = []
        center.onAlert = { alerts.append($0) }
        center.apply(.init(id: "claude:a", tool: .claude, at: Date().addingTimeInterval(-120), cwd: repo.path, status: .working))
        for _ in 0..<200 where center.startCommits["claude:a"] == nil { try await Task.sleep(for: .milliseconds(10)) }

        try write("one\n", to: "README.md", in: repo)
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .done), deferFinishAlert: true)
        // The file sources finish looking before git answers: the peek still waits for the summary.
        center.finishDiscovery()
        #expect(alerts.isEmpty)
        for _ in 0..<200 where alerts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        #expect(alerts.map(\.kind) == [.finished])
        #expect(alerts.first?.thread.doneSummary == DoneSummary(branch: "main", filesChanged: 1, insertions: 0, deletions: 2))
    }
}
