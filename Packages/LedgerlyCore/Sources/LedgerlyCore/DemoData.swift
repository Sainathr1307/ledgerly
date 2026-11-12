import Foundation

/// SplitMix64: a tiny deterministic generator, so demo data is the same on every run and every platform.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in a closed range (simple modulo; the tiny bias does not matter for demo data).
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        return range.lowerBound + Int(next() % span)
    }

    /// True `percent` times out of 100.
    public mutating func chance(_ percent: Int) -> Bool {
        int(in: 0...99) < percent
    }

    /// A deterministic (version-4 shaped) UUID.
    public mutating func uuid() -> UUID {
        let a = next()
        let b = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((a >> UInt64(8 * (7 - index))) & 0xFF)
            bytes[8 + index] = UInt8((b >> UInt64(8 * (7 - index))) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Everything the DEBUG demo seeder inserts.
public struct DemoDataSet: Hashable, Sendable {
    /// Oldest first.
    public var transactions: [TransactionRecord]
    public var earnings: [WeeklyEarning]
    public var goals: [MonthlyGoal]
    public var categories: [CategoryRecord]

    public init(transactions: [TransactionRecord], earnings: [WeeklyEarning], goals: [MonthlyGoal], categories: [CategoryRecord]) {
        self.transactions = transactions
        self.earnings = earnings
        self.goals = goals
        self.categories = categories
    }
}

/// Three months of realistic data relative to `now`: the two full months before the current one, and the current
/// month up to `now`. Same `now`, time zone and seed → identical output.
public enum DemoData {
    /// $200, used for all three months.
    public static var goalAmount: Decimal { 200 }

    /// - Weekly earnings exist for every completed week whose Monday falls in the three months, except the most recent
    ///   completed week, so the "enter last week's earnings" card shows.
    /// - The current month is tuned so that Food & Dining runs over pace and projected savings fall short of the
    ///   $200 goal (a non-empty gap plan), provided the month still has days left.
    /// - Two Needs Review items are included (a $0 amount and a blank merchant).
    public static func generate(now: Date, calendar: LedgerCalendar, seed: UInt64 = 20_240_607) -> DemoDataSet {
        var rng = SplitMix64(seed: seed)
        let categories = DefaultCategories.all
        let categorizer = Categorizer(rules: [], categories: categories)
        let currentMonth = MonthKey(date: now, calendar: calendar)
        let months = [currentMonth.adding(months: -2), currentMonth.previous, currentMonth]
        var transactions: [TransactionRecord] = []

        func money(_ cents: Int) -> Decimal { Decimal(cents) / 100 }

        func add(
            _ merchant: String, cents: Int, on day: Date, minuteOfDay: Int, method: PaymentMethod? = nil,
            notes: String = "", needsReview: Bool = false, rng: inout SplitMix64
        ) {
            var date = calendar.calendar.date(byAdding: .minute, value: minuteOfDay, to: day) ?? day
            if date > now { date = now }
            let payment: PaymentMethod
            if let method {
                payment = method
            } else {
                let roll = rng.int(in: 0...99)
                payment = roll < 60 ? .walletCard("Apple Card") : (roll < 85 ? .walletCard("Chase Freedom") : .cash)
            }
            let source: SourceKind
            if case .walletCard = payment { source = .walletShortcut } else { source = .manual }
            transactions.append(TransactionRecord(
                id: rng.uuid(), amount: money(cents), currencyCode: "USD", merchant: merchant,
                categoryID: categorizer.categorize(merchant: merchant).categoryID,
                date: date, paymentMethod: payment, source: source, notes: notes,
                needsReview: needsReview, isPossibleDuplicate: false, createdAt: date
            ))
        }

        func pick(_ options: [String], rng: inout SplitMix64) -> String {
            options[rng.int(in: 0...(options.count - 1))]
        }

        let coffeeShops = ["Starbucks", "Starbucks", "Starbucks", "Dunkin", "Dunkin", "Colectivo Coffee"]
        let restaurants = ["Chipotle", "McDonald's", "Portillo's", "Panera Bread", "Lou Malnati's", "Chick-fil-A", "Taco Bell", "DoorDash", "Noodles & Company", "Culver's"]
        let grocers = ["Jewel-Osco", "Jewel-Osco", "Aldi", "Trader Joe's", "Mariano's", "Costco"]
        let gasStations = ["Shell", "SHELL OIL 57444", "BP", "Speedway", "Marathon"]
        let shops = ["Target", "Amazon", "Amazon", "Walmart", "Best Buy", "TJ Maxx", "Old Navy"]
        let fun = ["AMC Theatres", "Steam Games", "Topgolf", "Dave & Buster's", "Ticketmaster", "Bowlero"]
        let rides = ["Uber", "Lyft"]
        let pharmacies = ["Walgreens", "CVS Pharmacy"]
        let misc = ["USPS", "Great Clips", "Venmo"]
        let mealNotes = ["", "", "", "", "", "", "Lunch with coworkers", "Date night", "Birthday dinner", ""]

        // (day of month, merchant, low cents, high cents)
        let fixedCharges: [(Int, String, Int, Int)] = [
            (2, "YouTube Premium", 1399, 1399),
            (3, "State Farm", 11240, 11240),
            (5, "ComEd", 6800, 9600),
            (8, "Netflix", 1549, 1549),
            (12, "Xfinity", 6500, 6500),
            (14, "Spotify", 1199, 1199),
            (17, "Planet Fitness", 2499, 2499),
            (18, "AT&T", 5500, 5500),
            (20, "Apple.com/Bill", 299, 299),
            (22, "Nicor Gas", 3800, 7200),
            (25, "Hulu", 999, 999)
        ]

        for month in months {
            let isCurrent = month == currentMonth
            for day in calendar.days(in: month) where day <= now {
                let dayNumber = calendar.dayOfMonth(day)
                let weekend = calendar.isWeekend(day)

                // Coffee runs — frequent and small.
                if rng.chance((weekend ? 40 : 62) + (isCurrent ? 12 : 0)) {
                    add(pick(coffeeShops, rng: &rng), cents: rng.int(in: 425...725), on: day, minuteOfDay: rng.int(in: 400...560), rng: &rng)
                }
                // Meals out — noticeably heavier in the current month.
                if rng.chance(isCurrent ? (weekend ? 78 : 50) : (weekend ? 55 : 34)) {
                    let base = rng.int(in: 895...3450)
                    add(pick(restaurants, rng: &rng), cents: isCurrent ? base * 115 / 100 : base, on: day,
                        minuteOfDay: rng.int(in: 690...1230), notes: pick(mealNotes, rng: &rng), rng: &rng)
                }
                if rng.chance(26) {
                    add(pick(grocers, rng: &rng), cents: rng.int(in: 2800...9600), on: day, minuteOfDay: rng.int(in: 600...1140), rng: &rng)
                }
                if rng.chance(12) {
                    add(pick(gasStations, rng: &rng), cents: rng.int(in: 3100...5400), on: day, minuteOfDay: rng.int(in: 420...1200), rng: &rng)
                }
                if rng.chance(weekend ? 20 : 12) {
                    add(pick(shops, rng: &rng), cents: rng.int(in: 1400...8900), on: day, minuteOfDay: rng.int(in: 600...1260), rng: &rng)
                }
                // Recreation — mostly weekends.
                if rng.chance(weekend ? 55 : 5) {
                    add(pick(fun, rng: &rng), cents: rng.int(in: 1200...5800), on: day, minuteOfDay: rng.int(in: 780...1320), rng: &rng)
                }
                if rng.chance(9) {
                    add(pick(rides, rng: &rng), cents: rng.int(in: 1100...2900), on: day, minuteOfDay: rng.int(in: 480...1380), rng: &rng)
                }
                if dayNumber == 1 || dayNumber == 11 || dayNumber == 21 {
                    add("Ventra", cents: 2000, on: day, minuteOfDay: 455, method: .walletCard("Apple Card"), rng: &rng)
                }
                if rng.chance(6) {
                    add(pick(pharmacies, rng: &rng), cents: rng.int(in: 700...3400), on: day, minuteOfDay: rng.int(in: 540...1200), rng: &rng)
                }
                if rng.chance(4) {
                    add(pick(misc, rng: &rng), cents: rng.int(in: 500...3200), on: day, minuteOfDay: rng.int(in: 540...1200), rng: &rng)
                }
                for charge in fixedCharges where charge.0 == dayNumber {
                    add(charge.1, cents: rng.int(in: charge.2...charge.3), on: day, minuteOfDay: 365, method: .otherCard, rng: &rng)
                }
                // Refunds.
                if dayNumber == 16 {
                    add("Amazon", cents: -rng.int(in: 1800...4200), on: day, minuteOfDay: 615, method: .otherCard, notes: "Returned item", rng: &rng)
                }
                if dayNumber == 24 {
                    add("Target", cents: -rng.int(in: 1200...2500), on: day, minuteOfDay: 840, method: .walletCard("Apple Card"), notes: "Refund", rng: &rng)
                }
            }
        }

        // Weekly earnings: every completed week except the most recent one.
        var earnings: [WeeklyEarning] = []
        let lastCompleted = calendar.lastCompletedWeekStart(now: now)
        for month in months {
            for monday in calendar.mondays(in: month) where monday < lastCompleted {
                earnings.append(WeeklyEarning(weekStart: monday, amount: money(rng.int(in: 54000...58500))))
            }
        }

        let goals = months.map { MonthlyGoal(month: $0, amount: goalAmount) }

        // --- Tuning so the current month tells a story ---
        let elapsedDays = calendar.days(in: currentMonth).filter { $0 <= now }
        func snapshot() -> BudgetSnapshot {
            BudgetEngine.snapshot(
                month: currentMonth, now: now, transactions: transactions, earnings: earnings,
                goal: goalAmount, categories: categories, calendar: calendar
            )
        }
        let foodID = DefaultCategories.id("food")

        // 1. Food & Dining clearly over pace.
        let dinners = ["Lou Malnati's", "Chipotle", "Portillo's", "DoorDash"]
        var attempts = 0
        while attempts < 12, let day = elapsedDays.isEmpty ? nil : elapsedDays[rng.int(in: 0...(elapsedDays.count - 1))] {
            let current = snapshot()
            let usual = current.usualByThisDayByCategory[foodID] ?? 0
            let spent = current.spentByCategory[foodID] ?? 0
            if usual > 0 && spent >= usual * (Decimal(string: "1.25") ?? 1) + 12 { break }
            add(dinners[attempts % dinners.count], cents: rng.int(in: 2200...3800), on: day, minuteOfDay: rng.int(in: 1080...1260), rng: &rng)
            attempts += 1
        }

        // 2. Projected savings short of the goal: add the largest purchase that does not overshoot much.
        let bigTickets: [(String, Int)] = [
            ("Apple Store", 99900), ("Best Buy", 64999), ("IKEA", 38950), ("Ticketmaster", 24860),
            ("Nike", 16499), ("Target", 11842), ("Topgolf", 8640), ("Amazon", 5999)
        ]
        var remainingTickets = bigTickets
        while !remainingTickets.isEmpty, !elapsedDays.isEmpty {
            let current = snapshot()
            guard let savings = current.projectedSavings else { break }
            let needed = savings - goalAmount + 40          // how much projected spending must rise
            if needed <= 0 { break }
            let day = elapsedDays[rng.int(in: 0...(elapsedDays.count - 1))]
            // A purchase of A raises the projection by roughly A × (1 + remaining/daysInMonth).
            let factor = 1 + Decimal(current.daysInMonth - current.dayOfMonth) / Decimal(current.daysInMonth)
            let index = remainingTickets.firstIndex { money($0.1) * factor <= needed + 150 } ?? (remainingTickets.count - 1)
            let ticket = remainingTickets.remove(at: index)
            add(ticket.0, cents: ticket.1, on: day, minuteOfDay: rng.int(in: 660...1200), rng: &rng)
        }

        // 3. Needs Review examples from the Wallet automation.
        let twoHoursAgo = calendar.calendar.date(byAdding: .hour, value: -2, to: now) ?? now
        let yesterday = calendar.calendar.date(byAdding: .hour, value: -26, to: now) ?? now
        transactions.append(TransactionRecord(
            id: rng.uuid(), amount: 0, currencyCode: "USD", merchant: "Shell",
            categoryID: categorizer.categorize(merchant: "Shell").categoryID, date: twoHoursAgo,
            paymentMethod: .walletCard("Apple Card"), source: .walletShortcut, notes: "",
            needsReview: true, isPossibleDuplicate: false, createdAt: twoHoursAgo
        ))
        transactions.append(TransactionRecord(
            id: rng.uuid(), amount: money(1875), currencyCode: "USD", merchant: "",
            categoryID: categorizer.fallbackCategoryID, date: yesterday,
            paymentMethod: .walletCard("Chase Freedom"), source: .walletShortcut, notes: "",
            needsReview: true, isPossibleDuplicate: false, createdAt: yesterday
        ))

        transactions.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        return DemoDataSet(transactions: transactions, earnings: earnings, goals: goals, categories: categories)
    }
}
