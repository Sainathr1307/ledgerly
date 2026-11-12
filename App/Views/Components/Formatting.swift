// Formatting.swift — money and date strings for the UI. Money always goes through Core's MoneyFormat.

import Foundation
import LedgerlyCore

/// Money strings in the user's currency.
@MainActor
enum Money {
    static var code: String { AppSettings.shared.currencyCode }

    /// "$12.40"
    static func string(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: code)
    }

    /// "$310"
    static func whole(_ amount: Decimal) -> String {
        MoneyFormat.whole(amount, currencyCode: code)
    }

    /// "$45" or "$44.37"
    static func compact(_ amount: Decimal) -> String {
        MoneyFormat.compact(amount, currencyCode: code)
    }

    static var symbol: String {
        MoneyFormat.currencySymbol(currencyCode: code)
    }

    /// Text for an editable amount field: "200" for whole numbers, otherwise "12.50".
    static func fieldText(_ amount: Decimal) -> String {
        let text = MoneyFormat.plain(amount)
        if text.hasSuffix(".00") {
            return String(text.dropLast(3))
        }
        return text
    }
}

/// Date strings in the user's locale.
enum DateText {
    /// "Thursday, November 12"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Nov 12"
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "3:42 PM"
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Nov 12, 3:42 PM"
    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// "November 2026"
    static func monthTitle(_ month: MonthKey, calendar: LedgerCalendar) -> String {
        calendar.monthStart(month).formatted(.dateTime.month(.wide).year())
    }

    /// "Nov"
    static func monthShort(_ month: MonthKey, calendar: LedgerCalendar) -> String {
        calendar.monthStart(month).formatted(.dateTime.month(.abbreviated))
    }

    /// "Nov 2 – Nov 8" for the Monday–Sunday week that starts at `weekStart`.
    static func weekRange(weekStart: Date, calendar: LedgerCalendar) -> String {
        let lastDay = calendar.weekLastDay(for: weekStart)
        return shortDay(weekStart) + " – " + shortDay(lastDay)
    }
}
