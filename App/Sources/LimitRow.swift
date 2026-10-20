import GondarCore
import SwiftUI

/// Every limit in the order the source gives, then extra usage, each after a divider; nothing until there are numbers.
/// Shared by the panel and the floating window.
struct LimitList: View {
    let model: UsageModel
    let compact: Bool

    var body: some View {
        if let report = model.state.display.snapshot?.report {
            ForEach(report.limits) { limit in
                Divider().overlay(Theme.line)
                LimitRow(limit: limit, now: model.now, compact: compact)
            }
            if let extra = report.extra {
                Divider().overlay(Theme.line)
                ExtraUsageRow(extra: extra, compact: compact)
            }
        }
    }
}

/// One limit: its name, how much is used, and when it resets.
/// `compact` is the narrow floating window's: name, countdown and percentage on one line.
struct LimitRow: View {
    let limit: UsageLimit
    let now: Date
    let compact: Bool

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                name
                Spacer(minLength: 0)
                percent
            }
            UsageBar(fraction: LimitText.barFraction(limit), fill: limit.isActive ? Theme.amber : Theme.muted)
                .padding(.top, 8)
            Text(verbatim: ResetText.full(resetsAt: limit.resetsAt, now: now, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent))
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .padding(.top, 7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var compactBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            name
            Spacer(minLength: 0)
            Text(verbatim: ResetText.short(resetsAt: limit.resetsAt, now: now))
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .fixedSize()
            percent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var name: some View {
        Text(verbatim: LimitText.name(limit))
            .font(Theme.body(13, .semibold))
            .foregroundStyle(limit.isActive ? Theme.text : Theme.softText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var percent: some View {
        Text(verbatim: "\(limit.percent)%")
            .font(Theme.mono(13))
            .monospacedDigit()
            .foregroundStyle(!limit.isActive ? Theme.muted : LimitText.isWarning(limit) ? Theme.amber : Theme.text)
            .fixedSize()
    }
}

/// Spend on extra usage against its monthly limit, in the account's own currency.
struct ExtraUsageRow: View {
    let extra: ExtraUsage
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Extra usage")
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            // The amounts in the numbers' face, the words around them in the body's.
            Group {
                switch MoneyText.extraUsage(extra, locale: .autoupdatingCurrent) {
                case .spendOfLimit(let used, let limit): amount(used) + word(" of ") + amount(limit)
                case .spent(let used): amount(used) + word(" used")
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 6 : 12)
    }

    private func amount(_ text: String) -> Text {
        Text(verbatim: text).font(Theme.mono(13)).monospacedDigit().foregroundStyle(Theme.text)
    }

    private func word(_ text: String) -> Text {
        Text(verbatim: text).font(Theme.body(12)).foregroundStyle(Theme.muted)
    }
}

/// A 6-point rounded bar on the line-coloured track.
struct UsageBar: View {
    let fraction: Double
    let fill: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                if fraction > 0 {
                    // Never narrower than it is tall, so a small share still reads as a rounded bar.
                    Capsule().fill(fill).frame(width: max(geometry.size.width * fraction, geometry.size.height))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
