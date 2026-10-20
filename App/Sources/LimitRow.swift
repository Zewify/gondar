import GondarCore
import SwiftUI

/// The panel's rows: every limit in the order the source gives, then extra usage, each after a divider;
/// nothing until there are numbers.
struct LimitList: View {
    let model: UsageModel

    var body: some View {
        if let report = model.state.display.snapshot?.report {
            ForEach(report.limits) { limit in
                Divider().overlay(Theme.line)
                LimitRow(limit: limit, now: model.now)
            }
            if let extra = report.extra {
                Divider().overlay(Theme.line)
                ExtraUsageRow(extra: extra)
            }
        }
    }
}

/// One limit in the panel: its name, how much is used, and when it resets.
struct LimitRow: View {
    let limit: UsageLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LimitName(limit: limit)
                Spacer(minLength: 0)
                LimitPercent(limit: limit)
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
}

/// A limit's name, shared by the panel and the pop-out window.
struct LimitName: View {
    let limit: UsageLimit

    var body: some View {
        Text(verbatim: LimitText.name(limit))
            .font(Theme.body(13, .semibold))
            .foregroundStyle(limit.isActive ? Theme.text : Theme.softText)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A limit's percentage, shared by the panel and the pop-out window, coloured by its level whether or not it is active.
struct LimitPercent: View {
    let limit: UsageLimit

    var body: some View {
        Text(verbatim: "\(limit.percent)%")
            .font(Theme.mono(13))
            .monospacedDigit()
            .foregroundStyle(Theme.level(LimitText.level(limit)))
            .fixedSize()
    }
}

/// Spend on extra usage against its monthly limit, in the account's own currency.
struct ExtraUsageRow: View {
    let extra: ExtraUsage

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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
