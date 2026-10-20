import GondarCore
import SwiftUI

/// Whose numbers these are and how old they are, or why there are none.
struct PanelHeader: View {
    let model: UsageModel

    var body: some View {
        Group {
            switch model.display {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 36)
            case .unavailable(let problem):
                Text(verbatim: problem.message)
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.softText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .ready(let snapshot):
                account(snapshot, problem: nil)
            case .stale(let snapshot, let problem):
                account(snapshot, problem: problem)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func account(_ snapshot: Snapshot, problem: Problem?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    email(snapshot)
                    Text(verbatim: [snapshot.profile.organizationName, snapshot.plan].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                // Where the numbers come from sits under their age.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: UpdatedText.text(fetchedAt: snapshot.fetchedAt, now: model.now))
                    Text(verbatim: SourceText.line(snapshot))
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .fixedSize()
            }
            if let problem {
                Text(verbatim: problem.message)
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func email(_ snapshot: Snapshot) -> some View {
        Text(verbatim: snapshot.profile.email)
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(snapshot.profile.email)
    }
}
