// CSVExporter.swift — writes every transaction to a CSV file in the temporary folder, ready for the share sheet.

import Foundation
import LedgerlyCore

enum CSVExporter {
    /// Writes all transactions (with category names) to "Ledgerly-export-yyyy-MM-dd.csv" in the
    /// temporary directory and returns the file's URL. The file can be imported again with the CSV import screen.
    static func makeExportFile() async throws -> URL {
        let data = await LedgerRepository.shared.snapshotAll()
        let calendar = LedgerCalendar.current
        let text = CSV.export(transactions: data.transactions, categories: data.categories, calendar: calendar)
        // The first ten characters of Core's timestamp are the local date, yyyy-MM-dd.
        let day = String(CSV.timestamp(Date(), calendar: calendar).prefix(10))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ledgerly-export-\(day).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
