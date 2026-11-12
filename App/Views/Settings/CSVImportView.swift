// CSVImportView.swift — import a bank or Apple Card CSV export: pick a file, check the column mapping, review duplicates, import.

import SwiftUI
import UniformTypeIdentifiers
import LedgerlyCore

struct CSVImportView: View {
    @State private var model = CSVImportModel()
    @State private var isPickerPresented = false

    init() {}

    var body: some View {
        Group {
            switch model.phase {
            case .pickFile:
                pickFileScreen
            case .mapping:
                CSVMappingForm(model: model) {
                    isPickerPresented = true
                }
            case .finished:
                finishedScreen
            }
        }
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.openFile(url)
                }
            case .failure(let error):
                model.errorMessage = "Couldn't open the file. \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Step 1: pick a file

    private var pickFileScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("Import a CSV file", systemImage: "doc.text")
                } description: {
                    Text("Export your transactions from Apple Card (Wallet, your card, a monthly statement, Export Transactions) or from your bank's website as a CSV file, save it to Files, then choose it here. Nothing leaves this iPhone.")
                } actions: {
                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("Choose a File", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("csvChooseFileButton")
                    .accessibilityHint("Opens the file picker")
                }

                if model.isWorking {
                    ProgressView("Reading the file…")
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                        .accessibilityIdentifier("csvErrorMessage")
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Step 3: done

    private var finishedScreen: some View {
        List {
            if let summary = model.summary {
                Section {
                    Label {
                        Text(summary.imported == 1 ? "Imported 1 transaction" : "Imported \(summary.imported) transactions")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier("csvImportDoneLabel")

                    if summary.duplicatesSkipped > 0 {
                        LabeledContent("Possible duplicates skipped", value: "\(summary.duplicatesSkipped)")
                    }
                    if summary.duplicatesIncluded > 0 {
                        LabeledContent("Possible duplicates imported", value: "\(summary.duplicatesIncluded)")
                    }
                    if summary.unreadableRows > 0 {
                        LabeledContent("Rows that couldn't be read", value: "\(summary.unreadableRows)")
                    }
                    if summary.needsReview > 0 {
                        LabeledContent("Waiting in Needs Review", value: "\(summary.needsReview)")
                    }
                } footer: {
                    Text("Each transaction was put in a category automatically. You can change any of them from the Transactions tab.")
                }
            }

            Section {
                Button {
                    model.startOver()
                } label: {
                    Label("Import Another File", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("csvImportAnotherButton")
            }
        }
    }
}

// MARK: - Step 2: mapping, preview, duplicates, import

private struct CSVMappingForm: View {
    @Bindable var model: CSVImportModel
    let chooseAnotherFile: () -> Void

    @State private var showsDuplicates = false
    @State private var showsUnreadable = false

    var body: some View {
        Form {
            fileSection
            columnsSection
            formatSection
            previewSection
            if !model.duplicateRows.isEmpty {
                duplicatesSection
            }
            if !model.unreadableRows.isEmpty {
                unreadableSection
            }
            importSection
        }
        .onChange(of: model.mapping) {
            model.recompute()
        }
    }

    private var fileSection: some View {
        Section("File") {
            LabeledContent("Name", value: model.fileName)
            LabeledContent("Rows found", value: "\(model.dataRowCount)")
            Button {
                chooseAnotherFile()
            } label: {
                Label("Choose a Different File", systemImage: "folder")
            }
            .accessibilityIdentifier("csvChooseDifferentFileButton")
        }
    }

    private var columnsSection: some View {
        Section {
            Toggle("First row is a header", isOn: $model.mapping.hasHeader)
                .accessibilityIdentifier("csvHasHeaderToggle")

            columnPicker("Date", selection: $model.mapping.date, emptyTitle: "Choose a column")
            columnPicker("Amount", selection: $model.mapping.amount, emptyTitle: "Choose a column")
            columnPicker("Merchant or description", selection: $model.mapping.merchant, emptyTitle: "Choose a column")
            columnPicker("Category (optional)", selection: $model.mapping.category, emptyTitle: "Not used")
            columnPicker("Notes (optional)", selection: $model.mapping.notes, emptyTitle: "Not used")
            columnPicker("Card or account (optional)", selection: $model.mapping.card, emptyTitle: "Not used")
        } header: {
            Text("Columns")
        } footer: {
            if model.mapping.isComplete {
                Text("Ledgerly guessed these from the file. Check them against the preview below and change any that are wrong.")
            } else {
                Text("Pick the Date, Amount and Merchant columns to continue.")
            }
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int?>, emptyTitle: String) -> some View {
        Picker(title, selection: selection) {
            Text(emptyTitle).tag(Int?.none)
            ForEach(model.columnOptions) { option in
                Text(option.title).tag(Int?.some(option.index))
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Date format", selection: $model.mapping.dateFormat) {
                ForEach(CSVDateFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }

            Toggle("Purchases are negative numbers", isOn: $model.purchasesAreNegative)
                .accessibilityIdentifier("csvNegativeToggle")
        } header: {
            Text("Format")
        } footer: {
            Text("Apple Card exports list purchases as positive numbers. Most bank exports list them as negative numbers, with deposits and refunds positive. If the preview shows your purchases as refunds, flip this switch.")
        }
    }

    private var previewSection: some View {
        Section {
            if model.previewRows.isEmpty {
                Text("There are no data rows in this file.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.previewRows) { row in
                    CSVPreviewRow(row: row, categoryName: row.record.map { model.categoryName(for: $0) } ?? "")
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            if model.dataRowCount > model.previewRows.count {
                Text("Showing the first \(model.previewRows.count) of \(model.dataRowCount) rows, as they will be imported.")
            }
        }
    }

    private var duplicatesSection: some View {
        Section {
            Toggle("Import possible duplicates too", isOn: $model.includeDuplicates)
                .accessibilityIdentifier("csvIncludeDuplicatesToggle")

            DisclosureGroup(isExpanded: $showsDuplicates) {
                ForEach(Array(model.duplicateRows.prefix(25))) { row in
                    CSVPreviewRow(row: row, categoryName: row.record.map { model.categoryName(for: $0) } ?? "")
                }
                if model.duplicateRows.count > 25 {
                    Text("And \(model.duplicateRows.count - 25) more.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(model.duplicateRows.count == 1 ? "Show the 1 possible duplicate" : "Show the \(model.duplicateRows.count) possible duplicates")
            }
        } header: {
            Text("Possible duplicates")
        } footer: {
            Text("These rows have the same day, amount and merchant as a transaction you already have, so they are left out unless you switch this on. If you do import them, they are marked as possible duplicates in Needs Review.")
        }
    }

    private var unreadableSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsUnreadable) {
                ForEach(Array(model.unreadableRows.prefix(25))) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Row \(row.rowNumber)")
                            .font(.subheadline.weight(.semibold))
                        Text(row.problem ?? "This row couldn't be read.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if model.unreadableRows.count > 25 {
                    Text("And \(model.unreadableRows.count - 25) more.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(model.unreadableRows.count == 1 ? "1 row can't be read" : "\(model.unreadableRows.count) rows can't be read")
            }
        } header: {
            Text("Skipped rows")
        } footer: {
            Text("Usually this means the Date column or the date format above is wrong. Rows that still can't be read are skipped.")
        }
    }

    private var importSection: some View {
        Section {
            LabeledContent("Will be imported", value: "\(model.recordsToImport.count)")
            LabeledContent("Possible duplicates", value: "\(model.duplicateRows.count)")
            LabeledContent("Rows that can't be read", value: "\(model.unreadableRows.count)")
            LabeledContent("Will need review", value: "\(model.recordsToImport.filter { $0.needsReview }.count)")

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("csvErrorMessage")
            }

            Button {
                Task {
                    await model.importNow()
                }
            } label: {
                HStack {
                    if model.isWorking {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(importButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canImport)
            .accessibilityIdentifier("csvImportButton")
        } header: {
            Text("Summary")
        } footer: {
            Text("Rows with a missing amount or merchant are imported and put in Needs Review.")
        }
    }

    private var importButtonTitle: String {
        let count = model.recordsToImport.count
        if !model.mapping.isComplete { return "Pick the columns first" }
        if count == 0 { return "Nothing to Import" }
        return count == 1 ? "Import 1 Transaction" : "Import \(count) Transactions"
    }
}

/// One row of the preview: the transaction it will become, or why it can't be read.
private struct CSVPreviewRow: View {
    let row: CSVImportRow
    let categoryName: String

    var body: some View {
        if let record = row.record {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.merchant.isEmpty ? "No merchant" : record.merchant)
                        .font(.body)
                        .foregroundStyle(record.merchant.isEmpty ? Color.secondary : Color.primary)
                    Spacer(minLength: 8)
                    Text(MoneyFormat.string(record.amount, currencyCode: record.currencyCode))
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(record.amount < 0 ? Color.green : Color.primary)
                }
                Text(subtitle(for: record))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if row.isDuplicate {
                    Label("Possible duplicate", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if record.needsReview {
                    Label("Will need review", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Row \(row.rowNumber)")
                    .font(.subheadline.weight(.semibold))
                Text(row.problem ?? "This row couldn't be read.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func subtitle(for record: TransactionRecord) -> String {
        let date = record.date.formatted(date: .abbreviated, time: .omitted)
        let kind = record.amount < 0 ? "Refund" : categoryName
        if kind.isEmpty { return date }
        return date + " · " + kind
    }
}
