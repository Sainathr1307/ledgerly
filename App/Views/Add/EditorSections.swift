// EditorSections.swift — the pieces of the quick-add / edit sheet below the keypad.

import SwiftUI
import LedgerlyCore

/// Category chips in a wrapping grid, so every chip is on screen without sideways scrolling.
struct CategoryChipGrid: View {
    let categories: [CategoryRecord]
    let selectedID: UUID?
    let onPick: (UUID) -> Void

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(categories) { category in
                CategoryChip(category: category, isSelected: category.id == selectedID) {
                    onPick(category.id)
                }
            }
        }
    }
}

/// Merchant text field with past merchants offered underneath.
struct MerchantEntry: View {
    @Binding var merchant: String
    let suggestions: [String]
    let onPick: (String) -> Void
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Merchant (optional)", text: $merchant)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused(isFocused)
                .padding(12)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Merchant")
                .accessibilityIdentifier("merchantField")
            if isFocused.wrappedValue && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) {
                                onPick(name)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint("Use this merchant")
                        }
                    }
                }
                .accessibilityLabel("Past merchants")
            }
        }
    }
}

/// Payment method buttons. Cash is first (and is the default), so paying cash needs no tap at all.
struct PaymentMethodRow: View {
    let choices: [PaymentMethod]
    @Binding var selection: PaymentMethod

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { method in
                    button(for: method)
                }
            }
        }
    }

    private func button(for method: PaymentMethod) -> some View {
        let isSelected = method == selection
        return Button {
            selection = method
        } label: {
            Label(method.displayName, systemImage: PaymentMethodRow.symbol(for: method))
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(PaymentMethodRow.identifier(for: method))
    }

    static func symbol(for method: PaymentMethod) -> String {
        switch method {
        case .cash:
            return "banknote"
        case .otherCard:
            return "creditcard"
        case .walletCard:
            return "wallet.pass"
        }
    }

    static func identifier(for method: PaymentMethod) -> String {
        switch method {
        case .cash:
            return "payment_cash"
        case .otherCard:
            return "payment_other"
        case .walletCard(let name):
            return "payment_card_" + name
        }
    }
}

/// "Always categorize [merchant] as [category]?" — shown inside the sheet right after saving a category change.
struct RulePromptCard: View {
    let prompt: RulePrompt
    let onAlways: () -> Void
    let onJustOnce: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Always categorize \(prompt.merchant) as \(prompt.categoryName)?")
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("rulePromptTitle")
            Text("Future purchases at \(prompt.merchant) will go straight to \(prompt.categoryName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAlways) {
                Text("Always")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("alwaysCategorizeButton")
            Button(action: onJustOnce) {
                Text("Just this once")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("justOnceButton")
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .padding(24)
        .accessibilityAddTraits(.isModal)
    }
}
