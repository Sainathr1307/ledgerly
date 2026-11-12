// Mappers.swift — conversions between SwiftData entities and LedgerlyCore value records.

import Foundation
import SwiftData
import LedgerlyCore

// MARK: - Transaction

extension TransactionEntity {
    convenience init(record: TransactionRecord) {
        self.init(id: record.id)
        apply(record)
    }

    /// Copies every field except `id` from the record onto this entity.
    func apply(_ record: TransactionRecord) {
        amount = record.amount
        currencyCode = record.currencyCode
        merchant = record.merchant
        categoryID = record.categoryID
        date = record.date
        paymentKindRaw = record.paymentMethod.kindRaw
        cardName = record.paymentMethod.cardName
        sourceRaw = record.source.rawValue
        notes = record.notes
        needsReview = record.needsReview
        isPossibleDuplicate = record.isPossibleDuplicate
        createdAt = record.createdAt
    }

    var record: TransactionRecord {
        TransactionRecord(
            id: id,
            amount: amount,
            currencyCode: currencyCode,
            merchant: merchant,
            categoryID: categoryID,
            date: date,
            paymentMethod: PaymentMethod(kindRaw: paymentKindRaw, cardName: cardName),
            source: SourceKind(rawValue: sourceRaw) ?? .manual,
            notes: notes,
            needsReview: needsReview,
            isPossibleDuplicate: isPossibleDuplicate,
            createdAt: createdAt
        )
    }
}

// MARK: - Category

extension CategoryEntity {
    convenience init(record: CategoryRecord) {
        self.init(id: record.id)
        apply(record)
    }

    /// Copies every field except `id` from the record onto this entity.
    func apply(_ record: CategoryRecord) {
        name = record.name
        colorHex = record.colorHex
        symbolName = record.symbolName
        sortOrder = record.sortOrder
        isArchived = record.isArchived
        systemKey = record.systemKey
    }

    var record: CategoryRecord {
        CategoryRecord(
            id: id,
            name: name,
            colorHex: colorHex,
            symbolName: symbolName,
            sortOrder: sortOrder,
            isArchived: isArchived,
            systemKey: systemKey
        )
    }
}

// MARK: - Merchant rule

extension MerchantRuleEntity {
    convenience init(record: MerchantRule) {
        self.init(normalizedMerchant: record.normalizedMerchant, categoryID: record.categoryID)
    }

    /// Copies the category from the record; the normalized merchant is the key and stays as is.
    func apply(_ record: MerchantRule) {
        categoryID = record.categoryID
    }

    var record: MerchantRule {
        MerchantRule(normalizedMerchant: normalizedMerchant, categoryID: categoryID)
    }
}

// MARK: - Weekly earning

extension WeeklyEarningEntity {
    convenience init(record: WeeklyEarning) {
        self.init(weekStart: record.weekStart, amount: record.amount)
    }

    /// Copies the amount from the record; the week start is the key and stays as is.
    func apply(_ record: WeeklyEarning) {
        amount = record.amount
    }

    var record: WeeklyEarning {
        WeeklyEarning(weekStart: weekStart, amount: amount)
    }
}

// MARK: - Monthly goal

extension MonthlyGoalEntity {
    convenience init(record: MonthlyGoal) {
        self.init(year: record.month.year, month: record.month.month, amount: record.amount)
    }

    /// Copies the amount from the record; the month is the key and stays as is.
    func apply(_ record: MonthlyGoal) {
        amount = record.amount
    }

    var record: MonthlyGoal {
        MonthlyGoal(month: MonthKey(year: year, month: month), amount: amount)
    }
}
