// CategoryEntity.swift — SwiftData mirror of LedgerlyCore.CategoryRecord.

import Foundation
import SwiftData

@Model
final class CategoryEntity {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    /// "#RRGGBB".
    var colorHex: String = "#8E8E93"
    /// SF Symbol name.
    var symbolName: String = "tag"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    /// One of the built-in keys (food, groceries, ...) or nil for a user-made category.
    var systemKey: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String = "#8E8E93",
        symbolName: String = "tag",
        sortOrder: Int = 0,
        isArchived: Bool = false,
        systemKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.systemKey = systemKey
    }
}
