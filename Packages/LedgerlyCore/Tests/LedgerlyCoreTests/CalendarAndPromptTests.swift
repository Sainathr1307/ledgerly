#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import XCTest
@testable import LedgerlyCore

final class LedgerCalendarTests: XCTestCase {
    private let cal = T.chicago

    func testWeekStartsOnMonday() {
        // Wednesday April 15, 2026 → Monday April 13.
        XCTAssertEqual(cal.weekStart(for: T.date(2026, 4, 15, 17, 45)), T.date(2026, 4, 13, 0))
    }
    func testMondayIsItsOwnWeekStart() {
        XCTAssertEqual(cal.weekStart(for: T.date(2026, 4, 13, 0, 0, 0)), T.date(2026, 4, 13, 0))
        XCTAssertEqual(cal.weekStart(for: T.date(2026, 4, 13, 23, 59, 59)), T.date(2026, 4, 13, 0))
    }
    func testSundayBelongsToThePreviousMonday() {
        XCTAssertEqual(cal.weekStart(for: T.date(2026, 4, 19, 23, 59, 59)), T.date(2026, 4, 13, 0))
        XCTAssertEqual(cal.weekLastDay(for: T.date(2026, 4, 15)), T.date(2026, 4, 19, 0))
    }
    func testWeekInterval() {
        let interval = cal.weekInterval(for: T.date(2026, 4, 15))
        XCTAssertEqual(interval.start, T.date(2026, 4, 13, 0))
        XCTAssertEqual(interval.end, T.date(2026, 4, 20, 0))
    }
    func testWeekAcrossYearBoundary() {
        // Thursday January 1, 2026 belongs to the week of Monday December 29, 2025.
        XCTAssertEqual(cal.weekStart(for: T.date(2026, 1, 1)), T.date(2025, 12, 29, 0))
        XCTAssertEqual(cal.monthKey(forWeekContaining: T.date(2026, 1, 1)), MonthKey(year: 2025, month: 12))
    }
    func testWeekCountsTowardTheMonthOfItsMonday() {
        // Monday March 30, 2026 – Sunday April 5: April 3 still counts toward March.
        XCTAssertEqual(cal.monthKey(forWeekContaining: T.date(2026, 4, 3)), MonthKey(year: 2026, month: 3))
        XCTAssertEqual(cal.monthKey(forWeekContaining: T.date(2026, 4, 6)), MonthKey(year: 2026, month: 4))
    }
    func testLastCompletedWeekStart() {
        XCTAssertEqual(cal.lastCompletedWeekStart(now: T.date(2026, 4, 15)), T.date(2026, 4, 6, 0))
        // On a Monday morning the week that just ended is the previous Monday's.
        XCTAssertEqual(cal.lastCompletedWeekStart(now: T.date(2026, 4, 13, 8)), T.date(2026, 4, 6, 0))
        // On a Sunday night the current week has not ended yet.
        XCTAssertEqual(cal.lastCompletedWeekStart(now: T.date(2026, 4, 12, 23, 59)), T.date(2026, 3, 30, 0))
    }
    func testFourMondayMonth() {
        let mondays = cal.mondays(in: MonthKey(year: 2026, month: 4))
        XCTAssertEqual(mondays, [6, 13, 20, 27].map { T.date(2026, 4, $0, 0) })
    }
    func testFiveMondayMonths() {
        XCTAssertEqual(cal.mondays(in: MonthKey(year: 2026, month: 3)), [2, 9, 16, 23, 30].map { T.date(2026, 3, $0, 0) })
        XCTAssertEqual(cal.mondays(in: MonthKey(year: 2026, month: 11)), [2, 9, 16, 23, 30].map { T.date(2026, 11, $0, 0) })
    }
    func testMonthStartingOnMondayHasFive() {
        XCTAssertEqual(cal.mondays(in: MonthKey(year: 2026, month: 6)), [1, 8, 15, 22, 29].map { T.date(2026, 6, $0, 0) })
    }
    func testFebruaryMondays() {
        XCTAssertEqual(cal.mondays(in: MonthKey(year: 2026, month: 2)).count, 4)
        XCTAssertEqual(cal.mondays(in: MonthKey(year: 2024, month: 2)), [5, 12, 19, 26].map { T.date(2024, 2, $0, 0) })
    }
    func testEveryMonthHasFourOrFiveMondays() {
        var month = MonthKey(year: 2024, month: 1)
        for _ in 0..<48 {
            let mondays = cal.mondays(in: month)
            XCTAssertTrue(mondays.count == 4 || mondays.count == 5, month.stringValue)
            for monday in mondays {
                XCTAssertEqual(cal.weekday(monday), 2)
                XCTAssertTrue(cal.contains(monday, in: month))
            }
            month = month.next
        }
    }
    func testDaysInMonth() {
        XCTAssertEqual(cal.daysInMonth(MonthKey(year: 2026, month: 2)), 28)
        XCTAssertEqual(cal.daysInMonth(MonthKey(year: 2024, month: 2)), 29)
        XCTAssertEqual(cal.daysInMonth(MonthKey(year: 2026, month: 4)), 30)
        XCTAssertEqual(cal.daysInMonth(MonthKey(year: 2026, month: 12)), 31)
    }
    func testMonthIntervalAndContains() {
        let april = MonthKey(year: 2026, month: 4)
        let interval = cal.monthInterval(april)
        XCTAssertEqual(interval.start, T.date(2026, 4, 1, 0))
        XCTAssertEqual(interval.end, T.date(2026, 5, 1, 0))
        XCTAssertTrue(cal.contains(T.date(2026, 4, 1, 0, 0, 0), in: april))
        XCTAssertTrue(cal.contains(T.date(2026, 4, 30, 23, 59, 59), in: april))
        XCTAssertFalse(cal.contains(T.date(2026, 5, 1, 0, 0, 0), in: april))
        XCTAssertFalse(cal.contains(T.date(2026, 3, 31, 23, 59, 59), in: april))
    }
    func testYearRollover() {
        let december = MonthKey(year: 2025, month: 12)
        XCTAssertEqual(cal.monthInterval(december).end, T.date(2026, 1, 1, 0))
        XCTAssertEqual(cal.monthKey(for: T.date(2025, 12, 31, 23, 59, 59)), december)
        XCTAssertEqual(cal.monthKey(for: T.date(2026, 1, 1, 0, 0, 0)), MonthKey(year: 2026, month: 1))
    }
    func testFirstDayOfMonth() {
        XCTAssertEqual(cal.dayOfMonth(T.date(2026, 4, 1, 0, 0, 0)), 1)
        XCTAssertEqual(cal.date(day: 1, of: MonthKey(year: 2026, month: 4)), T.date(2026, 4, 1, 0))
        XCTAssertEqual(cal.days(in: MonthKey(year: 2026, month: 4)).count, 30)
        XCTAssertEqual(cal.days(in: MonthKey(year: 2026, month: 4)).first, T.date(2026, 4, 1, 0))
    }
    func testWeekendDetection() {
        XCTAssertTrue(cal.isWeekend(T.date(2026, 4, 18)))    // Saturday
        XCTAssertTrue(cal.isWeekend(T.date(2026, 4, 19)))    // Sunday
        XCTAssertFalse(cal.isWeekend(T.date(2026, 4, 17)))   // Friday
        XCTAssertFalse(cal.isWeekend(T.date(2026, 4, 20)))   // Monday
    }
    func testImpossibleDateIsNil() {
        XCTAssertNil(cal.date(year: 2026, month: 2, day: 30))
        XCTAssertNotNil(cal.date(year: 2024, month: 2, day: 29))
    }

    // Daylight saving, America/Chicago: spring forward March 8, 2026; fall back November 1, 2026.

    func testSpringForwardDayIs23Hours() {
        let start = cal.startOfDay(T.date(2026, 3, 8, 12))
        let next = cal.startOfDay(start, addingDays: 1)
        XCTAssertEqual(next.timeIntervalSince(start), 23 * 3600)
        XCTAssertEqual(next, T.date(2026, 3, 9, 0))
    }
    func testFallBackDayIs25Hours() {
        let start = cal.startOfDay(T.date(2026, 11, 1, 12))
        let next = cal.startOfDay(start, addingDays: 1)
        XCTAssertEqual(next.timeIntervalSince(start), 25 * 3600)
        XCTAssertEqual(next, T.date(2026, 11, 2, 0))
    }
    func testWeekContainingSpringForwardIs167Hours() {
        // Monday March 2 – Sunday March 8, 2026.
        let interval = cal.weekInterval(for: T.date(2026, 3, 8, 20))
        XCTAssertEqual(interval.start, T.date(2026, 3, 2, 0))
        XCTAssertEqual(interval.end, T.date(2026, 3, 9, 0))
        XCTAssertEqual(interval.duration, 167 * 3600)
    }
    func testWeekContainingFallBackIs169Hours() {
        // Monday October 26 – Sunday November 1, 2026.
        let interval = cal.weekInterval(for: T.date(2026, 11, 1, 20))
        XCTAssertEqual(interval.start, T.date(2026, 10, 26, 0))
        XCTAssertEqual(interval.duration, 169 * 3600)
    }
    func testWeekStartsStayAtMidnightAcrossDST() {
        var monday = T.date(2026, 2, 23, 0)
        for _ in 0..<6 {
            let parts = cal.calendar.dateComponents([.hour, .minute, .weekday], from: monday)
            XCTAssertEqual(parts.hour, 0)
            XCTAssertEqual(parts.minute, 0)
            XCTAssertEqual(parts.weekday, 2)
            monday = cal.nextWeekStart(after: monday)
        }
        XCTAssertEqual(monday, T.date(2026, 4, 6, 0))
    }
    func testMarchAndNovemberLengthsWithDST() {
        let march = cal.monthInterval(MonthKey(year: 2026, month: 3))
        XCTAssertEqual(march.duration, TimeInterval(31 * 24 - 1) * 3600)
        let november = cal.monthInterval(MonthKey(year: 2026, month: 11))
        XCTAssertEqual(november.duration, TimeInterval(30 * 24 + 1) * 3600)
        XCTAssertEqual(cal.daysInMonth(MonthKey(year: 2026, month: 3)), 31)
        XCTAssertEqual(cal.days(in: MonthKey(year: 2026, month: 11)).count, 30)
    }
    func testLateEveningOnFallBackDayStaysInThatDay() {
        // 23:30 on the 25-hour day is more than 24 h after midnight but still November 1.
        let late = T.date(2026, 11, 1, 23, 30)
        XCTAssertEqual(cal.dayOfMonth(late), 1)
        XCTAssertEqual(cal.startOfDay(late), T.date(2026, 11, 1, 0))
        XCTAssertGreaterThan(late.timeIntervalSince(cal.startOfDay(late)), 24 * 3600)
    }
    func testSameInstantDifferentTimeZonesDifferentWeek() {
        // Monday 03:00 UTC is still Sunday evening in Chicago.
        let instant = T.date(2026, 4, 13, 3, 0, calendar: T.utc)
        XCTAssertEqual(T.utc.weekStart(for: instant), T.date(2026, 4, 13, 0, calendar: T.utc))
        XCTAssertEqual(cal.weekStart(for: instant), T.date(2026, 4, 6, 0))
    }
    func testInitFromCalendarKeepsTimeZoneAndForcesMondayWeeks() {
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.timeZone = TimeZone(identifier: "America/Chicago")!
        sundayFirst.firstWeekday = 1
        let ledger = LedgerCalendar(calendar: sundayFirst)
        XCTAssertEqual(ledger.calendar.firstWeekday, 2)
        XCTAssertEqual(ledger.timeZone.identifier, "America/Chicago")
        XCTAssertEqual(ledger.weekStart(for: T.date(2026, 4, 19)), T.date(2026, 4, 13, 0))
    }
}

final class GoalPromptTests: XCTestCase {
    private let cal = T.chicago

    func testFirstLaunchPrompts() {
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: nil, now: T.date(2026, 4, 15), calendar: cal))
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: "", now: T.date(2026, 4, 15), calendar: cal))
    }
    func testSameMonthDoesNotPromptAgain() {
        XCTAssertFalse(GoalPrompt.shouldPrompt(lastPromptMonth: "2026-04", now: T.date(2026, 4, 1, 0, 0, 0), calendar: cal))
        XCTAssertFalse(GoalPrompt.shouldPrompt(lastPromptMonth: "2026-04", now: T.date(2026, 4, 30, 23, 59, 59), calendar: cal))
    }
    func testNewMonthPrompts() {
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: "2026-04", now: T.date(2026, 5, 1, 0, 0, 0), calendar: cal))
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: "2025-12", now: T.date(2026, 1, 1, 9), calendar: cal))
    }
    func testGarbledValuePrompts() {
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: "April", now: T.date(2026, 4, 15), calendar: cal))
    }
    func testMonthBoundaryUsesLocalTime() {
        // 03:00 UTC on May 1 is still April 30 in Chicago.
        let instant = T.date(2026, 5, 1, 3, 0, calendar: T.utc)
        XCTAssertFalse(GoalPrompt.shouldPrompt(lastPromptMonth: "2026-04", now: instant, calendar: cal))
        XCTAssertTrue(GoalPrompt.shouldPrompt(lastPromptMonth: "2026-04", now: instant, calendar: T.utc))
    }
    func testMonthString() {
        XCTAssertEqual(GoalPrompt.monthString(now: T.date(2026, 4, 15), calendar: cal), "2026-04")
    }
    func testPrefill() {
        XCTAssertEqual(GoalPrompt.prefillAmount(previousGoal: nil), T.d("200"))
        XCTAssertEqual(GoalPrompt.prefillAmount(previousGoal: T.d("350")), T.d("350"))
        XCTAssertEqual(GoalPrompt.prefillAmount(previousGoal: T.d("0")), T.d("0"))
        XCTAssertEqual(GoalPrompt.defaultGoal, T.d("200"))
    }
}

final class EarningsReminderTests: XCTestCase {
    private let cal = T.chicago

    func testMissingWhenNothingEntered() {
        XCTAssertTrue(EarningsReminder.isLastWeekMissing(earnings: [], now: T.date(2026, 4, 15), calendar: cal))
    }
    func testNotMissingOnceEntered() {
        let earnings = [T.earning("600", weekOf: T.date(2026, 4, 6))]
        XCTAssertFalse(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 15), calendar: cal))
    }
    func testZeroEarningsCountAsEntered() {
        let earnings = [T.earning("0", weekOf: T.date(2026, 4, 6))]
        XCTAssertFalse(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 15), calendar: cal))
    }
    func testOlderOrCurrentWeekDoesNotCount() {
        let earnings = [T.earning("600", weekOf: T.date(2026, 3, 30)), T.earning("600", weekOf: T.date(2026, 4, 13))]
        XCTAssertTrue(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 15), calendar: cal))
    }
    func testBecomesMissingAgainOnMonday() {
        let earnings = [T.earning("600", weekOf: T.date(2026, 4, 6))]
        XCTAssertFalse(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 19, 23, 59), calendar: cal))
        XCTAssertTrue(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 20, 0, 0, 1), calendar: cal))
    }
    func testEarningStoredMidWeekStillCounts() {
        let earnings = [WeeklyEarning(weekStart: T.date(2026, 4, 8, 15), amount: T.d("600"))]
        XCTAssertFalse(EarningsReminder.isLastWeekMissing(earnings: earnings, now: T.date(2026, 4, 15), calendar: cal))
    }
    func testMissingWeekStarts() {
        let earnings = [T.earning("600", weekOf: T.date(2026, 3, 30))]
        let missing = EarningsReminder.missingWeekStarts(earnings: earnings, now: T.date(2026, 4, 15), calendar: cal, weeksBack: 3)
        XCTAssertEqual(missing, [T.date(2026, 3, 23, 0), T.date(2026, 4, 6, 0)])
    }
    func testWeeklyTriggerComponents() {
        let parts = EarningsReminder.weeklyTriggerComponents(hour: 8, minute: 0)
        XCTAssertEqual(parts.weekday, 2)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertNil(parts.day)
        let clamped = EarningsReminder.weeklyTriggerComponents(hour: 99, minute: -5)
        XCTAssertEqual(clamped.hour, 23)
        XCTAssertEqual(clamped.minute, 0)
    }
    func testNextReminderMidWeek() {
        let next = EarningsReminder.nextReminderDate(after: T.date(2026, 4, 15, 10), hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(next, T.date(2026, 4, 20, 8, 0))
    }
    func testNextReminderOnMondayBeforeTheTime() {
        let next = EarningsReminder.nextReminderDate(after: T.date(2026, 4, 13, 7, 59), hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(next, T.date(2026, 4, 13, 8, 0))
    }
    func testNextReminderOnMondayAtOrAfterTheTime() {
        XCTAssertEqual(EarningsReminder.nextReminderDate(after: T.date(2026, 4, 13, 8, 0), hour: 8, minute: 0, calendar: cal), T.date(2026, 4, 20, 8, 0))
        XCTAssertEqual(EarningsReminder.nextReminderDate(after: T.date(2026, 4, 13, 18, 0), hour: 8, minute: 0, calendar: cal), T.date(2026, 4, 20, 8, 0))
    }
    func testNextReminderOnSunday() {
        let next = EarningsReminder.nextReminderDate(after: T.date(2026, 4, 19, 23, 0), hour: 9, minute: 30, calendar: cal)
        XCTAssertEqual(next, T.date(2026, 4, 20, 9, 30))
    }
    func testNextReminderAcrossDSTIsStill8AMLocal() {
        // Saturday March 7, 2026 → Monday March 9, the day after clocks spring forward.
        let next = EarningsReminder.nextReminderDate(after: T.date(2026, 3, 7, 12), hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(next, T.date(2026, 3, 9, 8, 0))
        XCTAssertEqual(cal.calendar.component(.hour, from: next), 8)
    }
    func testNextReminderComponents() {
        let parts = EarningsReminder.nextReminderComponents(after: T.date(2026, 12, 30, 10), hour: 8, minute: 15, calendar: cal)
        XCTAssertEqual(parts.year, 2027)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 4)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 15)
        XCTAssertEqual(parts.weekday, 2)
    }
    func testReminderCopy() {
        XCTAssertEqual(EarningsReminder.notificationTitle, "New week!")
        XCTAssertEqual(EarningsReminder.notificationBody, "What did you earn last week?")
    }
}
