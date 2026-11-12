// CategoryViews.swift — the round category icon and the selectable category chip.

import SwiftUI
import LedgerlyCore

/// A category's SF Symbol on its color. The symbol is white so it stays readable in Light and Dark Mode.
struct CategoryIcon: View {
    let symbolName: String
    let colorHex: String
    var isLarge: Bool = false

    var body: some View {
        Image(systemName: symbolName)
            .font(isLarge ? .title3 : .footnote)
            .foregroundStyle(.white)
            .padding(isLarge ? 10 : 7)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A tappable chip for picking a category.
struct CategoryChip: View {
    let category: CategoryRecord
    let isSelected: Bool
    let action: () -> Void

    /// "category_chip_food" for built-in categories, "category_chip_<name>" for the user's own.
    static func identifier(for category: CategoryRecord) -> String {
        "category_chip_" + (category.systemKey ?? category.name)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .foregroundStyle(isSelected ? Color.white : Color(hex: category.colorHex))
                    .accessibilityHidden(true)
                Text(category.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chipBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(CategoryChip.identifier(for: category))
    }

    private var chipBackground: Color {
        isSelected ? Color(hex: category.colorHex) : Color(.secondarySystemFill)
    }
}
