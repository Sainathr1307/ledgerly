// CategoriesEditorView.swift — add, rename, recolor, reorder and archive categories.

import SwiftUI
import LedgerlyCore

struct CategoriesEditorView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: CategoryDraft?

    var body: some View {
        List {
            Section {
                ForEach(store.activeCategories) { category in
                    row(category)
                }
                .onMove { source, destination in
                    move(from: source, to: destination)
                }
            } header: {
                Text("Active")
            } footer: {
                Text("Tap Edit to drag categories into a new order.")
            }
            if !store.archivedCategories.isEmpty {
                Section {
                    ForEach(store.archivedCategories) { category in
                        row(category)
                    }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived categories keep their past transactions but can't be picked for new ones.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = CategoryDraft.new(sortOrder: nextSortOrder)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
                .accessibilityIdentifier("addCategoryButton")
            }
        }
        .sheet(item: $editing) { draft in
            CategoryEditSheet(draft: draft) { saved in
                Task {
                    await store.saveCategory(saved)
                }
            }
        }
    }

    private var nextSortOrder: Int {
        let highest = store.data.categories.map { $0.sortOrder }.max() ?? -1
        return highest + 1
    }

    private func row(_ category: CategoryRecord) -> some View {
        Button {
            editing = CategoryDraft(record: category, isNew: false)
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(symbolName: category.symbolName, colorHex: category.colorHex)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                if category.isArchived {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.isArchived ? "\(category.name), archived" : category.name)
        .accessibilityHint("Opens the category editor")
        .accessibilityIdentifier("category_row_" + (category.systemKey ?? category.name))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            archiveAction(for: category)
        }
    }

    @ViewBuilder
    private func archiveAction(for category: CategoryRecord) -> some View {
        if category.isArchived {
            Button {
                setArchived(false, for: category)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .tint(.green)
        } else if category.systemKey != "other" {
            Button {
                setArchived(true, for: category)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
    }

    private func setArchived(_ archived: Bool, for category: CategoryRecord) {
        var updated = category
        updated.isArchived = archived
        let result = updated
        Task {
            await store.saveCategory(result)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = store.activeCategories.map { $0.id }
        ids.move(fromOffsets: source, toOffset: destination)
        let ordered = ids
        Task {
            await store.reorderCategories(ordered)
        }
    }
}

/// A category being edited in the sheet.
struct CategoryDraft: Identifiable {
    var record: CategoryRecord
    var isNew: Bool
    var id: UUID { record.id }

    static func new(sortOrder: Int) -> CategoryDraft {
        let record = CategoryRecord(
            name: "",
            colorHex: "#1C7ED6",
            symbolName: "tag.fill",
            sortOrder: sortOrder
        )
        return CategoryDraft(record: record, isNew: true)
    }
}

/// Name, color, symbol and archive switch for one category.
struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let draft: CategoryDraft
    private let onSave: (CategoryRecord) -> Void

    @State private var name: String
    @State private var color: Color
    @State private var symbolName: String
    @State private var isArchived: Bool

    /// A small, curated set of SF Symbols that all exist on iOS 18.
    static let symbolChoices: [String] = [
        "fork.knife", "cart.fill", "fuelpump.fill", "bag.fill", "gamecontroller.fill",
        "bolt.fill", "car.fill", "cross.case.fill", "repeat", "ellipsis.circle.fill",
        "tag.fill", "house.fill", "airplane", "gift.fill", "pawprint.fill",
        "book.fill", "graduationcap.fill", "figure.run", "tshirt.fill", "wrench.and.screwdriver.fill",
        "cup.and.saucer.fill", "film.fill", "music.note", "heart.fill", "phone.fill",
        "wifi", "creditcard.fill", "banknote.fill", "bus.fill", "leaf.fill"
    ]

    init(draft: CategoryDraft, onSave: @escaping (CategoryRecord) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.record.name)
        _color = State(initialValue: Color(hex: draft.record.colorHex))
        _symbolName = State(initialValue: draft.record.symbolName)
        _isArchived = State(initialValue: draft.record.isArchived)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("categoryNameField")
                }
                Section("Color") {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                        .accessibilityIdentifier("categoryColorPicker")
                    HStack(spacing: 12) {
                        CategoryIcon(symbolName: symbolName, colorHex: color.hexString, isLarge: true)
                        Text(trimmedName.isEmpty ? "Preview" : trimmedName)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview")
                }
                Section("Symbol") {
                    symbolGrid
                }
                if canArchive {
                    Section {
                        Toggle("Archived", isOn: $isArchived)
                            .accessibilityIdentifier("categoryArchivedToggle")
                    } footer: {
                        Text("Archived categories keep their history but are hidden when adding transactions.")
                    }
                }
            }
            .navigationTitle(draft.isNew ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("saveCategoryButton")
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Other" is the fallback for everything uncategorized, so it can't be archived.
    private var canArchive: Bool {
        !draft.isNew && draft.record.systemKey != "other"
    }

    private var symbolGrid: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 48), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CategoryEditSheet.symbolChoices, id: \.self) { symbol in
                symbolButton(symbol)
            }
        }
        .padding(.vertical, 4)
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = symbol == symbolName
        return Button {
            symbolName = symbol
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    isSelected ? color : Color(uiColor: .secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        var record = draft.record
        record.name = trimmedName
        record.colorHex = color.hexString
        record.symbolName = symbolName
        record.isArchived = isArchived
        onSave(record)
        dismiss()
    }
}
