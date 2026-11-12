// LedgerSchema.swift — the one list of SwiftData model types that make up the Ledgerly store.

import Foundation
import SwiftData

enum LedgerSchema {
    /// Every @Model type in the store. Add new entities here and nowhere else.
    static var models: [any PersistentModel.Type] {
        [
            TransactionEntity.self,
            CategoryEntity.self,
            MerchantRuleEntity.self,
            WeeklyEarningEntity.self,
            MonthlyGoalEntity.self
        ]
    }

    static var schema: Schema {
        Schema(models)
    }
}
