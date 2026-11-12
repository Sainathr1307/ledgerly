import Foundation

/// RFC-4180 reading and writing.
public enum CSV {
    /// Parses CSV text into rows of cells.
    /// Handles quoted cells, doubled quotes, commas and line breaks inside quotes, CRLF / LF / CR line endings and a
    /// leading byte-order mark. Completely empty lines are skipped. Cells are not trimmed.
    /// - Parameter delimiter: nil → detected from the first line (comma, semicolon or tab).
    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let separator: Unicode.Scalar = delimiter?.unicodeScalars.first ?? detectDelimiter(scalars)

        var rows: [[String]] = []
        var row: [String] = []
        var cell = String.UnicodeScalarView()
        var inQuotes = false
        var cellWasQuoted = false
        var index = 0

        func endCell() {
            row.append(String(cell))
            cell = String.UnicodeScalarView()
            cellWasQuoted = false
        }
        func endRow() {
            endCell()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        cell.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    cell.append(scalar)
                }
            } else if scalar == "\"" && cell.isEmpty && !cellWasQuoted {
                inQuotes = true
                cellWasQuoted = true
            } else if scalar == separator {
                endCell()
            } else if scalar == "\r" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                endRow()
            } else if scalar == "\n" {
                endRow()
            } else {
                cell.append(scalar)
            }
            index += 1
        }
        if !cell.isEmpty || !row.isEmpty || cellWasQuoted { endRow() }
        return rows
    }

    /// The delimiter (",", ";" or tab) that appears most often outside quotes in the first line. Defaults to ",".
    public static func detectDelimiter(_ text: String) -> Character {
        Character(detectDelimiter(Array(text.unicodeScalars)))
    }

    private static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for scalar in scalars {
            if scalar == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if scalar == "\n" || scalar == "\r" { break }
            if counts[scalar] != nil { counts[scalar, default: 0] += 1 }
        }
        let comma = counts[","] ?? 0
        let semicolon = counts[";"] ?? 0
        let tab = counts["\t"] ?? 0
        if semicolon > comma && semicolon >= tab { return ";" }
        if tab > comma && tab > semicolon { return "\t" }
        return ","
    }

    /// Quotes a cell when it contains the delimiter, a quote, a line break, or leading/trailing spaces.
    public static func escape(_ field: String, delimiter: Character = ",") -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Joins rows into CSV text with CRLF line endings (RFC 4180).
    public static func write(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { row in row.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
            .joined(separator: "\r\n") + (rows.isEmpty ? "" : "\r\n")
    }

    /// Header row written by `export`.
    public static let exportHeader: [String] = ["Date", "Amount", "Currency", "Merchant", "Category", "Payment Method", "Source", "Notes", "Needs Review"]

    /// Exports transactions, oldest first.
    /// Dates are local wall-clock "yyyy-MM-dd HH:mm:ss" in `calendar`'s time zone; amounts are plain numbers with "."
    /// (expenses positive, refunds negative). Re-importing the file with `CSVImporter` reproduces date, amount, currency,
    /// merchant, category (by name), payment method and notes.
    public static func export(transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar) -> String {
        let resolver = CategoryResolver(categories: categories)
        var rows: [[String]] = [exportHeader]
        let sorted = transactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        for transaction in sorted {
            let category = resolver.record(resolver.resolve(transaction.categoryID))
            rows.append([
                timestamp(transaction.date, calendar: calendar),
                MoneyFormat.plain(transaction.amount),
                transaction.currencyCode,
                transaction.merchant,
                category.name,
                transaction.paymentMethod.displayName,
                transaction.source.rawValue,
                transaction.notes,
                transaction.needsReview ? "yes" : "no"
            ])
        }
        return write(rows)
    }

    /// A file name such as "ledgerly-2026-03-14.csv".
    public static func exportFileName(now: Date, calendar: LedgerCalendar) -> String {
        "ledgerly-" + String(timestamp(now, calendar: calendar).prefix(10)) + ".csv"
    }

    /// "yyyy-MM-dd HH:mm:ss" in the calendar's time zone.
    public static func timestamp(_ date: Date, calendar: LedgerCalendar) -> String {
        let parts = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2)) \(pad(parts.hour, 2)):\(pad(parts.minute, 2)):\(pad(parts.second, 2))"
    }
}

/// The order of the numbers in a CSV date.
public enum CSVDateFormat: String, Codable, CaseIterable, Sendable {
    /// 2026-03-14, 2026/03/14
    case yearMonthDay
    /// 03/14/2026, 3/14/26 (US)
    case monthDayYear
    /// 14/03/2026, 14.03.2026
    case dayMonthYear

    public var displayName: String {
        switch self {
        case .yearMonthDay: return "Year-Month-Day"
        case .monthDayYear: return "Month/Day/Year"
        case .dayMonthYear: return "Day/Month/Year"
        }
    }
}

/// Which CSV column feeds which field. Indexes are 0-based; nil = not mapped.
public struct CSVColumnMapping: Hashable, Codable, Sendable {
    public var date: Int?
    public var amount: Int?
    public var merchant: Int?
    public var category: Int?
    public var notes: Int?
    /// Card / account / payment-method column.
    public var card: Int?
    public var currency: Int?
    /// Skip the first row.
    public var hasHeader: Bool
    public var dateFormat: CSVDateFormat
    /// True when purchases are positive numbers (Apple Card export). False when purchases are negative (most bank exports).
    public var expensesArePositive: Bool

    public init(
        date: Int? = nil, amount: Int? = nil, merchant: Int? = nil, category: Int? = nil, notes: Int? = nil,
        card: Int? = nil, currency: Int? = nil,
        hasHeader: Bool = true, dateFormat: CSVDateFormat = .monthDayYear, expensesArePositive: Bool = true
    ) {
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.notes = notes
        self.card = card
        self.currency = currency
        self.hasHeader = hasHeader
        self.dateFormat = dateFormat
        self.expensesArePositive = expensesArePositive
    }

    /// Date, amount and merchant are all mapped — the minimum needed to import.
    public var isComplete: Bool { date != nil && amount != nil && merchant != nil }
}

/// One CSV row after mapping.
public struct CSVImportRow: Identifiable, Hashable, Sendable {
    /// 1-based row number in the file (the header is row 1 when present).
    public var rowNumber: Int
    public var cells: [String]
    /// The transaction this row would create; nil when the row cannot be imported.
    public var record: TransactionRecord?
    /// Same day + amount + normalized merchant as a transaction already in the store.
    public var isDuplicate: Bool
    /// Why the row cannot be imported (nil when it can).
    public var problem: String?

    public init(rowNumber: Int, cells: [String], record: TransactionRecord?, isDuplicate: Bool, problem: String?) {
        self.rowNumber = rowNumber
        self.cells = cells
        self.record = record
        self.isDuplicate = isDuplicate
        self.problem = problem
    }

    public var id: Int { rowNumber }
}

public struct CSVImportResult: Hashable, Sendable {
    public var rows: [CSVImportRow]

    public init(rows: [CSVImportRow]) {
        self.rows = rows
    }

    /// Records for rows that parsed and are not duplicates — what "Import" saves by default.
    public var newRecords: [TransactionRecord] { rows.filter { !$0.isDuplicate }.compactMap { $0.record } }
    /// Records for rows flagged as duplicates (each has `isPossibleDuplicate = true`), in case the user wants them anyway.
    public var duplicateRecords: [TransactionRecord] { rows.filter { $0.isDuplicate }.compactMap { $0.record } }
    public var duplicateCount: Int { rows.filter { $0.isDuplicate }.count }
    public var failedCount: Int { rows.filter { $0.record == nil }.count }
    public var needsReviewCount: Int { newRecords.filter { $0.needsReview }.count }
}

/// CSV import: header detection, column guessing, date sniffing, rows → records, duplicate detection.
public enum CSVImporter {
    /// True when the first row looks like column titles (a known title word, or no digits anywhere).
    public static func hasHeader(_ rows: [[String]]) -> Bool {
        guard let first = rows.first else { return false }
        let titles = ["date", "amount", "description", "merchant", "payee", "category", "memo", "debit", "credit", "notes"]
        let cells = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if cells.contains(where: { cell in titles.contains(where: { cell.contains($0) }) && !cell.contains(where: { $0.isNumber }) }) {
            return true
        }
        return !cells.contains { $0.contains(where: { $0.isNumber }) }
    }

    /// Best-guess mapping for a parsed file. With a header the column titles decide; without one the first rows' contents do.
    /// The user confirms or corrects the result in the mapping step.
    public static func guessMapping(rows: [[String]], locale: Locale = .current) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()
        mapping.hasHeader = hasHeader(rows)
        let dataRows = Array(rows.dropFirst(mapping.hasHeader ? 1 : 0))
        let sample = Array(dataRows.prefix(50))

        if mapping.hasHeader, let header = rows.first {
            let titles = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            func find(_ candidates: [String], exact: Bool = false, excluding: Set<Int> = []) -> Int? {
                for candidate in candidates {
                    if let index = titles.indices.first(where: {
                        !excluding.contains($0) && (exact ? titles[$0] == candidate : titles[$0].contains(candidate))
                    }) { return index }
                }
                return nil
            }
            mapping.date = find(["transaction date", "trans date", "trans. date"]) ?? find(["date"], exact: true) ?? find(["date", "posted", "time"])
            mapping.amount = find(["amount"]) ?? find(["debit", "total", "value", "price"])
            mapping.merchant = find(["merchant"]) ?? find(["description", "payee", "name", "details", "vendor"])
            mapping.category = find(["category"])
            var used = Set([mapping.date, mapping.amount, mapping.merchant, mapping.category].compactMap { $0 })
            mapping.notes = find(["memo", "notes", "note", "comment"], excluding: used)
            if let notes = mapping.notes { used.insert(notes) }
            mapping.card = find(["payment method", "card", "account"], excluding: used)
            if let card = mapping.card { used.insert(card) }
            mapping.currency = find(["currency"], excluding: used)
        }

        // Fill gaps (or everything, when there is no header) from the contents.
        let columnCount = sample.map { $0.count }.max() ?? 0
        func column(_ index: Int) -> [String] {
            sample.compactMap { index < $0.count ? $0[index].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.filter { !$0.isEmpty }
        }
        if mapping.date == nil {
            mapping.date = (0..<columnCount).first { index in
                let values = column(index)
                return !values.isEmpty && sniffDateFormat(values) != nil
            }
        }
        if mapping.amount == nil {
            mapping.amount = (0..<columnCount).first { index in
                guard index != mapping.date else { return false }
                let values = column(index)
                return !values.isEmpty && values.allSatisfy { looksLikeAmount($0, locale: locale) }
            }
        }
        if mapping.merchant == nil {
            var best: (index: Int, length: Int)?
            for index in 0..<columnCount where index != mapping.date && index != mapping.amount {
                let values = column(index)
                guard !values.isEmpty, values.contains(where: { $0.contains(where: { $0.isLetter }) }) else { continue }
                let length = values.reduce(0) { $0 + $1.count } / values.count
                if best == nil || length > (best?.length ?? 0) { best = (index, length) }
            }
            mapping.merchant = best?.index
        }

        if let dateColumn = mapping.date, let format = sniffDateFormat(column(dateColumn)) {
            mapping.dateFormat = format
        }
        if let amountColumn = mapping.amount {
            let values = column(amountColumn).compactMap { AmountParser.parse($0, locale: locale) }
            let negatives = values.filter { $0 < 0 }.count
            let positives = values.filter { $0 > 0 }.count
            mapping.expensesArePositive = positives >= negatives
        }
        return mapping
    }

    /// Works out the order of the date parts from sample cells. Nil when the samples are not dates.
    /// A four-digit first part → year first. Otherwise a first part above 12 → day first, a second part above 12 →
    /// month first, and when every date is ambiguous (e.g. 03/04/2026) → month first (US).
    public static func sniffDateFormat(_ samples: [String]) -> CSVDateFormat? {
        let values = samples.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        var sawYearFirst = false
        var firstAbove12 = false
        var secondAbove12 = false
        for value in values {
            guard let parts = dateNumbers(value) else { return nil }
            if parts.yearFirst { sawYearFirst = true }
            if parts.numbers[0] > 12 { firstAbove12 = true }
            if parts.numbers[1] > 12 { secondAbove12 = true }
        }
        if sawYearFirst { return .yearMonthDay }
        if firstAbove12 && !secondAbove12 { return .dayMonthYear }
        if firstAbove12 && secondAbove12 { return nil }
        return .monthDayYear
    }

    /// Parses a CSV date cell: "2026-03-14", "03/14/2026", "3/14/26", "14.03.2026", optionally followed by a time
    /// ("14:05", "14:05:09", "2:05 PM", or ISO "T14:05:09"). A trailing "Z" means UTC; otherwise the time is local to `calendar`.
    /// Two-digit years are 2000-based. Returns nil for anything else, including impossible dates.
    public static func parseDate(_ text: String, format: CSVDateFormat, calendar: LedgerCalendar) -> Date? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        var isUTC = false
        if value.hasSuffix("Z") || value.hasSuffix("z") {
            isUTC = true
            value.removeLast()
        }
        // Split date and time.
        var datePart = value
        var timePart = ""
        if let colon = value.firstIndex(of: ":") {
            let beforeColon = value[..<colon]
            if let split = beforeColon.lastIndex(where: { $0 == " " || $0 == "T" || $0 == "t" }) {
                datePart = String(value[..<split])
                timePart = String(value[value.index(after: split)...])
            } else {
                return nil
            }
        }
        guard let parts = dateNumbers(datePart) else { return nil }
        let numbers = parts.numbers
        var year: Int, month: Int, day: Int
        if parts.yearFirst {
            (year, month, day) = (numbers[0], numbers[1], numbers[2])
        } else {
            switch format {
            case .yearMonthDay: (year, month, day) = (numbers[0], numbers[1], numbers[2])
            case .monthDayYear: (month, day, year) = (numbers[0], numbers[1], numbers[2])
            case .dayMonthYear: (day, month, year) = (numbers[0], numbers[1], numbers[2])
            }
        }
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day), (1900...2200).contains(year) else { return nil }

        var hour = 0, minute = 0, second = 0
        if !timePart.isEmpty {
            var time = timePart.trimmingCharacters(in: .whitespaces).uppercased()
            var meridiem: String?
            if time.hasSuffix("AM") || time.hasSuffix("PM") {
                meridiem = String(time.suffix(2))
                time = String(time.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            let pieces = time.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2 || pieces.count == 3, let h = Int(pieces[0]), let m = Int(pieces[1]) else { return nil }
            hour = h
            minute = m
            if pieces.count == 3 {
                // Seconds may carry a fraction: "09.123".
                let wholeSeconds = pieces[2].split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                guard let s = Int(wholeSeconds) else { return nil }
                second = s
            }
            if let meridiem {
                guard (1...12).contains(hour) else { return nil }
                if meridiem == "AM" { hour = hour == 12 ? 0 : hour } else { hour = hour == 12 ? 12 : hour + 12 }
            }
            guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        }

        if isUTC, let utc = TimeZone(identifier: "UTC") {
            return LedgerCalendar(timeZone: utc).date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        }
        return calendar.date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    /// Turns parsed rows into records using the mapping.
    ///
    /// - Rows whose date cannot be read are reported with a `problem` and no record.
    /// - Unparseable or zero amounts and blank merchants still produce a record with `needsReview = true`
    ///   (same rule as every other source).
    /// - A row is a duplicate when a transaction in `existing` has the same calendar day, amount and normalized
    ///   merchant. Duplicate rows keep their record (with `isPossibleDuplicate = true`) but are left out of `newRecords`.
    ///   Identical rows inside the same file are not flagged against each other.
    /// - Record ids are random unless `idProvider` is given (tests).
    public static func prepare(
        rows: [[String]],
        mapping: CSVColumnMapping,
        existing: [TransactionRecord],
        ingestor: TransactionIngestor,
        calendar: LedgerCalendar,
        now: Date,
        idProvider: ((Int) -> UUID)? = nil
    ) -> CSVImportResult {
        var existingKeys = Set<String>()
        for transaction in existing { existingKeys.insert(duplicateKey(transaction, calendar: calendar)) }

        var result: [CSVImportRow] = []
        for (index, cells) in rows.enumerated() {
            if mapping.hasHeader && index == 0 { continue }
            let rowNumber = index + 1
            func cell(_ column: Int?) -> String {
                guard let column, column >= 0, column < cells.count else { return "" }
                return cells[column].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }

            guard let date = parseDate(cell(mapping.date), format: mapping.dateFormat, calendar: calendar) else {
                let shown = cell(mapping.date)
                result.append(CSVImportRow(
                    rowNumber: rowNumber, cells: cells, record: nil, isDuplicate: false,
                    problem: shown.isEmpty ? "No date in this row." : "Couldn't read the date \"\(shown)\"."
                ))
                continue
            }
            let categoryText = cell(mapping.category)
            let currencyText = cell(mapping.currency)
            let incoming = IncomingTransaction(
                rawAmount: cell(mapping.amount),
                merchant: cell(mapping.merchant),
                cardName: mapping.card == nil ? nil : cell(mapping.card),
                date: date,
                source: .csvImport,
                currencyCode: currencyText.isEmpty ? nil : currencyText,
                notes: cell(mapping.notes),
                categoryHint: categoryText.isEmpty ? nil : categoryText,
                negateAmount: !mapping.expensesArePositive
            )
            var record = ingestor.ingest(incoming, existing: [], now: now, id: idProvider?(rowNumber) ?? UUID(), checkDuplicates: false).record
            let duplicate = record.amount != 0 && existingKeys.contains(duplicateKey(record, calendar: calendar))
            if duplicate { record.isPossibleDuplicate = true }
            result.append(CSVImportRow(rowNumber: rowNumber, cells: cells, record: record, isDuplicate: duplicate, problem: nil))
        }
        return CSVImportResult(rows: result)
    }

    /// Convenience: parse the text, guess the mapping and prepare the rows in one go.
    public static func prepare(
        text: String,
        existing: [TransactionRecord],
        ingestor: TransactionIngestor,
        calendar: LedgerCalendar,
        now: Date
    ) -> (mapping: CSVColumnMapping, rows: [[String]], result: CSVImportResult) {
        let rows = CSV.parse(text)
        let mapping = guessMapping(rows: rows, locale: ingestor.locale)
        let result = prepare(rows: rows, mapping: mapping, existing: existing, ingestor: ingestor, calendar: calendar, now: now)
        return (mapping, rows, result)
    }

    /// Import duplicate rule: same calendar day, same amount, same normalized merchant.
    public static func isImportDuplicate(_ a: TransactionRecord, _ b: TransactionRecord, calendar: LedgerCalendar) -> Bool {
        duplicateKey(a, calendar: calendar) == duplicateKey(b, calendar: calendar)
    }

    // MARK: Helpers

    private static func duplicateKey(_ transaction: TransactionRecord, calendar: LedgerCalendar) -> String {
        let day = calendar.calendar.dateComponents([.year, .month, .day], from: transaction.date)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(MoneyFormat.plain(transaction.amount))|\(MerchantNormalizer.normalize(transaction.merchant))"
    }

    private static func looksLikeAmount(_ text: String, locale: Locale) -> Bool {
        guard AmountParser.parse(text, locale: locale) != nil else { return false }
        // Dates such as 14.03.2026 are not amounts.
        return dateNumbers(text) == nil
    }

    /// The three numbers of a date such as "2026-03-14", "3/14/26" or "14.03.2026", ignoring any time after a space or "T".
    private static func dateNumbers(_ text: String) -> (numbers: [Int], yearFirst: Bool)? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = value.firstIndex(of: ":") {
            guard let split = value[..<colon].lastIndex(where: { $0 == " " || $0 == "T" || $0 == "t" }) else { return nil }
            value = String(value[..<split])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = value.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
        guard pieces.count == 3 else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 4, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        let yearFirst = pieces[0].count == 4
        if !yearFirst && pieces[2].count == 3 { return nil }
        return (numbers, yearFirst)
    }
}
