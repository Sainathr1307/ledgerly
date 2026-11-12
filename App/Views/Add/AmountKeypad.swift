// AmountKeypad.swift — the big number pad at the top of quick add.

import SwiftUI

struct AmountKeypad: View {
    let onDigit: (Int) -> Void
    let onDot: () -> Void
    let onDelete: () -> Void

    private let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { digit in
                        digitKey(digit)
                    }
                }
            }
            HStack(spacing: 8) {
                KeypadKey(identifier: "keypad_dot", spokenLabel: "Decimal point", action: onDot) {
                    Text(".")
                }
                digitKey(0)
                KeypadKey(identifier: "keypad_delete", spokenLabel: "Delete last digit", action: onDelete) {
                    Image(systemName: "delete.left")
                }
            }
        }
    }

    private func digitKey(_ digit: Int) -> some View {
        KeypadKey(identifier: "keypad_\(digit)", spokenLabel: "\(digit)", action: { onDigit(digit) }) {
            Text("\(digit)")
        }
    }
}

private struct KeypadKey<Content: View>: View {
    let identifier: String
    let spokenLabel: String
    let action: () -> Void
    @ViewBuilder let label: () -> Content

    var body: some View {
        Button(action: action) {
            label()
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier(identifier)
    }
}
