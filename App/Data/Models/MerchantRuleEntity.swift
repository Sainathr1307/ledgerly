// MerchantRuleEntity.swift — SwiftData mirror of LedgerlyCore.MerchantRule (a learned merchant → category rule).

import Foundation
import SwiftData

@Model
final class MerchantRuleEntity {
    /// Output of MerchantNormalizer.normalize; the natural key of a rule.
    @Attribute(.unique) var normalizedMerchant: String = ""
    var categoryID: UUID = UUID()

    init(normalizedMerchant: String = "", categoryID: UUID = UUID()) {
        self.normalizedMerchant = normalizedMerchant
        self.categoryID = categoryID
    }
}
