// CSVImportModel.swift — state and logic behind the CSV import screen: read the file, map columns, find duplicates, save.

import Foundation
import Observation
import LedgerlyCore

@MainActor
@Observable
final class CSVImportModel {
    enum Phase: Equatable {
        case pickFile, mapping, finished
    }

    /// One choice in a column picker.
    struct ColumnOption: Identifiable, Hashable {
        let index: Int
        let title: String
        var id: Int { index }
    }

    /// What an import did, for the last screen.
    struct Summary: Equatable {
        var imported: Int
        var duplicatesSkipped: Int
        var duplicatesIncluded: Int
        var unreadableRows: Int
        var needsReview: Int
    }

    private(set) var phase: Phase = .pickFile
    private(set) var fileName: String = ""
    /// Every row of the file as parsed, header included.
    private(set) var rows: [[String]] = []
    /// Which column feeds which field. Starts as Core's best guess; the screen edits it.
    var mapping: CSVColumnMapping = CSVColumnMapping()
    /// The rows turned into transactions with the current mapping.
    private(set) var result: CSVImportResult = CSVImportResult(rows: [])
    /// Possible duplicates are left out unless this is on.
    var includeDuplicates: Bool = false
    var errorMessage: String?
    private(set) var isWorking: Bool = false
    private(set) var summary: Summary?
    private(set) var categoryNames: [UUID: String] = [:]

    private var existing: [TransactionRecord] = []
    private var ingestor: TransactionIngestor = TransactionIngestor(categorizer: Categorizer())
    private let calendar: LedgerCalendar = LedgerCalendar.current

    init() {}

    // MARK: - Derived values

    /// The widest row among the first rows of the file.
    var columnCount: Int {
        rows.prefix(50).map { $0.count }.max() ?? 0
    }

    /// Picker choices: the header title when the file has one, otherwise "Column 2: STARBUCKS".
    var columnOptions: [ColumnOption] {
        let header: [String]? = mapping.hasHeader ? rows.first : nil
        let sample: [String]? = rows.dropFirst(mapping.hasHeader ? 1 : 0).first
        var options: [ColumnOption] = []
        for index in 0..<columnCount {
            var title = "Column \(index + 1)"
            if let header, index < header.count {
                let name = header[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { title = name }
            } else if let sample, index < sample.count {
                let value = sample[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { title += ": " + String(value.prefix(24)) }
            }
            options.append(ColumnOption(index: index, title: title))
        }
        return options
    }

    /// The sign toggle on the screen: on when purchases are negative numbers in the file (most bank exports).
    var purchasesAreNegative: Bool {
        get { !mapping.expensesArePositive }
        set { mapping.expensesArePositive = !newValue }
    }

    /// Number of data rows (the header doesn't count).
    var dataRowCount: Int {
        result.rows.count
    }

    var previewRows: [CSVImportRow] {
        Array(result.rows.prefix(5))
    }

    var duplicateRows: [CSVImportRow] {
        result.rows.filter { $0.isDuplicate }
    }

    var unreadableRows: [CSVImportRow] {
        result.rows.filter { $0.record == nil }
    }

    /// Exactly what "Import" will save.
    var recordsToImport: [TransactionRecord] {
        var records = result.newRecords
        if includeDuplicates {
            // Imported on request, but still marked so they show up in Needs Review as possible duplicates.
            for duplicate in result.duplicateRecords {
                var record = duplicate
                record.isPossibleDuplicate = true
                record.needsReview = true
                records.append(record)
            }
        }
        return records
    }

    var canImport: Bool {
        mapping.isComplete && !recordsToImport.isEmpty && !isWorking
    }

    func categoryName(for record: TransactionRecord) -> String {
        guard let id = record.categoryID, let name = categoryNames[id] else { return "Other" }
        return name
    }

    // MARK: - Steps

    /// Reads the picked file, guesses the column mapping and moves to the mapping step.
    func openFile(_ url: URL) {
        errorMessage = nil
        let text: String
        do {
            text = try CSVImportModel.readText(from: url)
        } catch {
            errorMessage = "Couldn't read that file. \(error.localizedDescription)"
            return
        }
        let parsed = CSV.parse(text)
        if parsed.isEmpty {
            errorMessage = "That file is empty, so there is nothing to import."
            return
        }
        let name = url.lastPathComponent
        isWorking = true
        Task {
            let data = await LedgerRepository.shared.snapshotAll()
            let categories = data.categories.isEmpty ? DefaultCategories.all : data.categories
            var names: [UUID: String] = [:]
            for category in categories {
                names[category.id] = category.name
            }
            categoryNames = names
            existing = data.transactions
            ingestor = TransactionIngestor(
                categorizer: Categorizer(rules: data.rules, categories: categories),
                defaultCurrencyCode: AppSettings.shared.currencyCode
            )
            fileName = name
            rows = parsed
            includeDuplicates = false
            summary = nil
            mapping = CSVImporter.guessMapping(rows: parsed, locale: ingestor.locale)
            recompute()
            phase = .mapping
            isWorking = false
        }
    }

    /// Re-runs Core's row → transaction step. Call after every mapping change.
    func recompute() {
        result = CSVImporter.prepare(
            rows: rows,
            mapping: mapping,
            existing: existing,
            ingestor: ingestor,
            calendar: calendar,
            now: Date()
        )
    }

    /// Saves everything in one batch (one save, one change notification).
    func importNow() async {
        guard canImport else { return }
        let records = recordsToImport
        let duplicateCount = result.duplicateCount
        let included = includeDuplicates ? duplicateCount : 0
        isWorking = true
        errorMessage = nil
        do {
            try await LedgerRepository.shared.upsertTransactions(records)
            summary = Summary(
                imported: records.count,
                duplicatesSkipped: duplicateCount - included,
                duplicatesIncluded: included,
                unreadableRows: result.failedCount,
                needsReview: records.filter { $0.needsReview }.count
            )
            phase = .finished
        } catch {
            errorMessage = "Nothing was imported. \(error.localizedDescription)"
        }
        isWorking = false
    }

    /// Back to the first step, ready for another file.
    func startOver() {
        phase = .pickFile
        fileName = ""
        rows = []
        mapping = CSVColumnMapping()
        result = CSVImportResult(rows: [])
        includeDuplicates = false
        errorMessage = nil
        summary = nil
    }

    // MARK: - File reading

    private enum ReadError: LocalizedError {
        case unknownEncoding

        var errorDescription: String? {
            "The file isn't plain text in an encoding Ledgerly understands. Try exporting it again as CSV (UTF-8)."
        }
    }

    /// Reads a file picked with the system file picker. Files outside the app's sandbox need
    /// security-scoped access for as long as they are being read.
    private static func readText(from url: URL) throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // UTF-16 only when the byte-order mark says so; almost any bytes "decode" as UTF-16 otherwise.
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF], let text = String(data: data, encoding: .utf16) {
            return text
        }
        // Older bank exports are often Windows-1252 / Latin-1.
        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw ReadError.unknownEncoding
    }
}
