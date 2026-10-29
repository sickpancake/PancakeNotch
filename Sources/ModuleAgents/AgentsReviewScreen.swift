import AgentsCore
import SwiftUI

/// A request to change a file, whole, in the taller notch (ADR-0037, 2026-10-28 amendment): where the file
/// really is, a warning for one outside the project or one that can run code, every line of the change,
/// then Open / Deny / Allow. Allow shows only while all of it fits; if it ever doesn't, Open and Deny stay.
struct AgentsReviewScreen: View {
    let module: AgentsModule
    let thread: AgentThread
    let change: AgentReview.FileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ViewThatFits(in: .vertical) {
                whole
                tooBig
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Review the change"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            BackButton { module.closeReview() }
            Image(systemName: thread.tool.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(thread.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private var whole: some View {
        VStack(alignment: .leading, spacing: 8) {
            place
            if !change.lines.isEmpty { lines }
            HStack {
                Spacer(minLength: 0)
                AnswerButtons(module: module, thread: thread, inReview: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What it wants to do and to which file, plus anything to watch out for.
    private var place: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AgentsText.action(change))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
            RequestLines(lines: change.path)
            if let warning = change.warning {
                Label(AgentsText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
            }
            if change.everyMatch {
                Text("Every match in the file changes, not just the first.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenPlace))
    }

    private var spokenPlace: String {
        [AgentsText.action(change), change.path.joined(), change.warning.map(AgentsText.warning) ?? "",
         change.everyMatch ? String(localized: "Every match in the file changes, not just the first.") : ""]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Every line of the change: removed ones struck through and dimmed, added ones bright, with − and +
    /// so it reads without color (ADR-0029: monochrome).
    private var lines: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in
                ChangeLine(line: line)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
    }

    /// The change doesn't fit this screen after all: no Allow, answer it in the tool.
    private var tooBig: some View {
        VStack(alignment: .leading, spacing: 8) {
            place
            Text("This change is too big to show here. Open it to see all of it.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))
            HStack {
                Spacer(minLength: 0)
                AnswerButtons(module: module, thread: thread, inReview: true, allowsAllow: false)
            }
        }
    }
}

private struct ChangeLine: View {
    let line: AgentReview.FileChange.Line

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: mark)
                .foregroundStyle(.white.opacity(0.6))
            Text(verbatim: line.kind == .gap ? "⋯" : line.text)
                .foregroundStyle(.white.opacity(line.kind == .added ? 1 : line.kind == .removed ? 0.55 : 0.7))
                .strikethrough(line.kind == .removed, color: .white.opacity(0.45))
        }
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AgentsText.spoken(line)))
    }

    private var mark: String {
        switch line.kind {
        case .removed: "−"
        case .added: "+"
        case .context, .gap: " "
        }
    }
}

private struct BackButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9.5, weight: .bold))
                Text("Back")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.7))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(isHovered ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Back to the list"))
        .accessibilityLabel(Text("Back"))
        .accessibilityHint(Text("Goes back to the list. The request keeps waiting."))
    }
}
