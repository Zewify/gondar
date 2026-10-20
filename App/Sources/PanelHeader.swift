import GondarCore
import SwiftUI

/// Whose numbers these are and how old they are, or why there are none.
/// `compact` is the narrow floating window's: the email alone, small, plus the age and the reason when the numbers are stale.
struct PanelHeader: View {
    let model: UsageModel
    let compact: Bool

    var body: some View {
        Group {
            switch model.state.display {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: compact ? 20 : 36)
            case .unavailable(let problem):
                Text(verbatim: problem.message)
                    .font(Theme.body(compact ? 12 : 13, .medium))
                    .foregroundStyle(Theme.softText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .ready(let snapshot):
                account(snapshot, problem: nil)
            case .stale(let snapshot, let problem):
                account(snapshot, problem: problem)
            }
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 8 : 12)
    }

    private func account(_ snapshot: Snapshot, problem: Problem?) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if compact {
                    email(snapshot, font: Theme.body(12), color: Theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        email(snapshot, font: Theme.body(13, .semibold), color: Theme.text)
                        Text(verbatim: [snapshot.profile.organizationName, snapshot.plan].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                // The narrow window shows the email alone while the numbers are current, and their age once they are not.
                // Where the numbers come from sits under it; the narrow window has no room for it.
                if !compact || problem != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: UpdatedText.text(fetchedAt: snapshot.fetchedAt, now: model.now))
                        if !compact {
                            Text(verbatim: Self.sourceLine(snapshot.source))
                        }
                    }
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                }
            }
            if let problem {
                Text(verbatim: problem.message)
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func sourceLine(_ source: Source) -> String {
        switch source {
        case .claudeCode: "From Claude Code"
        case .claudeAI: "From claude.ai"
        }
    }

    private func email(_ snapshot: Snapshot, font: Font, color: Color) -> some View {
        Text(verbatim: snapshot.profile.email)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(snapshot.profile.email)
    }
}
