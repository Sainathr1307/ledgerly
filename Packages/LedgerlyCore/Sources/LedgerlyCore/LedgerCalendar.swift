#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// The one place that knows about weeks, months, time zones and daylight saving.
///
/// Weeks run Monday–Sunday. Everything is done with `Calendar` arithmetic (never by adding
/// multiples of 86 400 seconds), so 23- and 25-hour DST days behave.
/// The calendar is always Gregorian, because `MonthKey` is a Gregorian year/month.
public struct LedgerCalendar: Hashable, Sendable {
    /// Gregorian calendar with `firstWeekday = 2` (Monday) in the chosen time zone.
    public let calendar: Calendar

    public var timeZone: TimeZone { calendar.timeZone }

    /// A ledger calendar in the given time zone (default: the device's current zone).
    public init(timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        self.calendar = cal
    }

    /// Uses the time zone of `calendar`. The calendar system itself is replaced by Gregorian with Monday weeks.
    public init(calendar: Calendar) {
        self.init(timeZone: calendar.timeZone)
    }

    /// Convenience for tests and previews. Returns nil for an unknown identifier.
    public init?(timeZoneIdentifier: String) {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        self.init(timeZone: zone)
    }

    /// The device's current time zone.
    public static var current: LedgerCalendar { LedgerCalendar(timeZone: .current) }

    // MARK: Days

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Start of the day `days` calendar days after the day containing `date` (negative = before).
    public func startOfDay(_ date: Date, addingDays days: Int) -> Date {
        let start = startOfDay(date)
        guard days != 0 else { return start }
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return calendar.startOfDay(for: moved)
    }

    /// Adds calendar days keeping the wall-clock time where possible.
    public func date(byAddingDays days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool {
        startOfDay(a) == startOfDay(b)
    }

    /// 1 = Sunday, 2 = Monday … 7 = Saturday.
    public func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Saturday or Sunday.
    public func isWeekend(_ date: Date) -> Bool {
        let day = weekday(date)
        return day == 1 || day == 7
    }

    /// Day of the month, 1-based.
    public func dayOfMonth(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    /// Builds a date from wall-clock parts in this calendar's time zone. Returns nil for impossible dates.
    public func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        guard let date = calendar.date(from: parts) else { return nil }
        // Reject roll-overs such as February 31.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    // MARK: Weeks

    /// Monday 00:00 of the week containing `date`.
    public func weekStart(for date: Date) -> Date {
        let offset = (weekday(date) + 5) % 7     // Monday → 0 … Sunday → 6
        return startOfDay(date, addingDays: -offset)
    }

    /// Monday 00:00 of the following week.
    public func nextWeekStart(after date: Date) -> Date {
        startOfDay(weekStart(for: date), addingDays: 7)
    }

    /// Monday 00:00 up to (not including) the next Monday 00:00.
    public func weekInterval(for date: Date) -> DateInterval {
        let start = weekStart(for: date)
        return DateInterval(start: start, end: startOfDay(start, addingDays: 7))
    }

    /// Start of the Sunday that ends the week containing `date`.
    public func weekLastDay(for date: Date) -> Date {
        startOfDay(weekStart(for: date), addingDays: 6)
    }

    /// Monday 00:00 of the most recent week that has fully ended (the week before the one containing `now`).
    public func lastCompletedWeekStart(now: Date) -> Date {
        startOfDay(weekStart(for: now), addingDays: -7)
    }

    /// The month a week counts toward: the month its Monday falls in.
    public func monthKey(forWeekContaining date: Date) -> MonthKey {
        MonthKey(date: weekStart(for: date), calendar: self)
    }

    // MARK: Months

    public func monthKey(for date: Date) -> MonthKey {
        MonthKey(date: date, calendar: self)
    }

    /// First instant of the month.
    public func monthStart(_ month: MonthKey) -> Date {
        var parts = DateComponents()
        parts.year = month.year
        parts.month = month.month
        parts.day = 1
        let date = calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
        return calendar.startOfDay(for: date)
    }

    /// First instant of the month up to the first instant of the next month.
    /// Treat the end as exclusive (use `contains(_:in:)`), because `DateInterval.contains` includes it.
    public func monthInterval(_ month: MonthKey) -> DateInterval {
        DateInterval(start: monthStart(month), end: monthStart(month.next))
    }

    /// True when `date` falls inside the month (end exclusive).
    public func contains(_ date: Date, in month: MonthKey) -> Bool {
        date >= monthStart(month) && date < monthStart(month.next)
    }

    public func daysInMonth(_ month: MonthKey) -> Int {
        calendar.range(of: .day, in: .month, for: monthStart(month))?.count ?? 30
    }

    /// Start of the given day of the month. `day` is clamped to 1...daysInMonth.
    public func date(day: Int, of month: MonthKey) -> Date {
        let clamped = min(max(day, 1), daysInMonth(month))
        return startOfDay(monthStart(month), addingDays: clamped - 1)
    }

    /// Start of every day in the month, in order.
    public func days(in month: MonthKey) -> [Date] {
        let count = daysInMonth(month)
        let start = monthStart(month)
        return (0..<count).map { startOfDay(start, addingDays: $0) }
    }

    /// Every Monday (00:00) that falls in the month — four or five of them.
    public func mondays(in month: MonthKey) -> [Date] {
        let start = monthStart(month)
        let end = monthStart(month.next)
        var monday = weekStart(for: start)
        if monday < start { monday = startOfDay(monday, addingDays: 7) }
        var result: [Date] = []
        while monday < end {
            result.append(monday)
            monday = startOfDay(monday, addingDays: 7)
        }
        return result
    }
}
