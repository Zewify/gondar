import Foundation

/// Names and warning rules for one usage limit.
public enum LimitText {
    public static func name(_ limit: UsageLimit) -> String {
        switch limit.kind {
        case .session: return "Current session"
        case .weeklyAll: return "Weekly · all models"
        case .weeklyScoped: return "Weekly · \(limit.scopeName ?? "one model")"
        case .other(let raw):
            let spaced = raw.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst()
        }
    }

    public static func isWarning(_ limit: UsageLimit) -> Bool {
        limit.severity != .normal || limit.percent >= 80
    }

    /// How near its limit a limit is, for the percentage's colour (a design decision, 2026-10-20):
    /// under 50 % low, 50 to 79 % medium, 80 % and over, or any severity but normal, high.
    /// Whether the limit is active does not matter, so the colour always means the level.
    public static func level(_ limit: UsageLimit) -> UsageLevel {
        if isWarning(limit) { return .high }
        return limit.percent >= 50 ? .medium : .low
    }

    public static func barFraction(_ limit: UsageLimit) -> Double {
        Double(min(max(limit.percent, 0), 100)) / 100
    }
}

public enum UsageLevel: Sendable, Equatable {
    case low, medium, high
}

public enum ResetText {
    /// How long until `date`, rounded down: "under 1 m", "36 m", "1 h 36 m", "5 d 3 h".
    public static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 1 { return "under 1 m" }
        if minutes < 60 { return "\(minutes) m" }
        if minutes < 24 * 60 { return "\(minutes / 60) h \(minutes % 60) m" }
        return "\(minutes / (24 * 60)) d \(minutes % (24 * 60) / 60) h"
    }

    /// The pop-out window's form: the countdown alone, or why there is none.
    public static func short(resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "No reset time" }
        guard resetsAt > now else { return "Resetting now" }
        return countdown(to: resetsAt, now: now)
    }

    public static func full(resetsAt: Date?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let resetsAt else { return "No reset time" }
        guard resetsAt > now else { return "Resetting now" }
        let time = resetsAt.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        )
        let countdown = countdown(to: resetsAt, now: now)
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            return "Resets in \(countdown) · \(time)"
        }
        let day = resetsAt.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
        )
        return "Resets in \(countdown) · \(day), \(time)"
    }
}

public enum PlanText {
    public static func label(organizationType: String?, rateLimitTier: String?) -> String? {
        let plan: String? = switch organizationType {
        case "claude_team": "Team"
        case "claude_max": "Max"
        case "claude_pro": "Pro"
        case "claude_enterprise": "Enterprise"
        default: nil
        }
        let tier: String? = switch rateLimitTier {
        case "default_claude_max_5x": "Max 5x"
        case "default_claude_max_20x": "Max 20x"
        default: nil
        }
        let parts = [plan, tier].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public enum UpdatedText {
    public static func text(fetchedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(fetchedAt)))
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(seconds / 60) min ago" }
        return "Updated \(seconds / 3600) h ago"
    }
}

public enum MoneyText {
    public static func text(_ money: Money, locale: Locale) -> String {
        let amount = Decimal(sign: money.minor < 0 ? .minus : .plus, exponent: -money.exponent, significand: Decimal(abs(money.minor)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = money.currency
        formatter.minimumFractionDigits = money.exponent
        formatter.maximumFractionDigits = money.exponent
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(money.currency)"
    }
}

/// What the extra-usage row says: spend against its cap, or spend alone when there is no cap to compare with.
public enum ExtraUsageText: Sendable, Equatable {
    /// "$12.34 of $50.00"
    case spendOfLimit(used: String, limit: String)
    /// "$0.00 used": a zero cap is no limit worth showing.
    case spent(String)
}

extension MoneyText {
    public static func extraUsage(_ extra: ExtraUsage, locale: Locale) -> ExtraUsageText {
        let used = text(extra.used, locale: locale)
        guard extra.limit.minor != 0 else { return .spent(used) }
        return .spendOfLimit(used: used, limit: text(extra.limit, locale: locale))
    }
}
