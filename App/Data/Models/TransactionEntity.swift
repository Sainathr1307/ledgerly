// TransactionEntity.swift — SwiftData mirror of LedgerlyCore.TransactionRecord.

import Foundation
import SwiftData

@Model
final class TransactionEntity {
    @Attribute(.unique) var id: UUID = UUID()
    /// Greater than zero for an expense, less than zero for a refund.
    var amount: Decimal = Decimal(0)
    var currencyCode: String = "USD"
    var merchant: String = ""
    /// Plain UUID, not a relationship, so archiving or deleting a category never cascades.
    var categoryID: UUID?
    var date: Date = Date()
    /// "cash" | "otherCard" | "walletCard" (PaymentMethod.kindRaw).
    var paymentKindRaw: String = "cash"
    var cardName: String?
    /// SourceKind.rawValue.
    var sourceRaw: String = "manual"
    var notes: String = ""
    var needsReview: Bool = false
    var isPossibleDuplicate: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        amount: Decimal = Decimal(0),
        currencyCode: String = "USD",
        merchant: String = "",
        categoryID: UUID? = nil,
        date: Date = Date(),
        paymentKindRaw: String = "cash",
        cardName: String? = nil,
        sourceRaw: String = "manual",
        notes: String = "",
        needsReview: Bool = false,
        isPossibleDuplicate: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.merchant = merchant
        self.categoryID = categoryID
        self.date = date
        self.paymentKindRaw = paymentKindRaw
        self.cardName = cardName
        self.sourceRaw = sourceRaw
        self.notes = notes
        self.needsReview = needsReview
        self.isPossibleDuplicate = isPossibleDuplicate
        self.createdAt = createdAt
    }
}
