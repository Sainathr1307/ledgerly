#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

public enum InsightKind: String, Codable, CaseIterable, Sendable {
    /// No earnings data: "add your earnings" instead of guessed numbers.
    case missingIncome
    /// Projected savings are below the goal: the cut list.
    case gapPlan
    /// Projected savings meet the goal (or, for a past month, the goal was met).
    case goalOnTrack
    /// A past month that ended below its goal.
    case goalMissed
    /// A category well above its usual amount for this point in the month.
    case overPace
    /// Many small purchases at one place (or coffee runs).
    case frequentSmallPurchases
    /// Top merchants and how they changed versus last month.
    case topMerchants
    /// Weekend and weekday daily spending differ a lot.
    case weekendVsWeekday
    /// A category well under its usual amount.
    case underUsual
    /// Expected income is an estimate from earlier weeks.
    case incomeEstimated
}

public enum InsightSentiment: String, Codable, Sendable {
    case warning, positive, neutral
}

/// One line of a gap-closing plan.
public struct GapCut: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var categoryName: String
    /// How much to cut, to the cent.
    public var amount: Decimal
    /// Standalone wording, e.g. "Cut dining out by $45" or "Pause one subscription ($15)".
    public var note: String
    /// Extra hint for the Subscriptions cut, e.g. "Spotify is $11.99 a month." Nil otherwise.
    public var suggestion: String?

    public init(categoryID: UUID, categoryName: String, amount: Decimal, note: String, suggestion: String? = nil) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.amount = amount
        self.note = note
        self.suggestion = suggestion
    }

    public var id: UUID { categoryID }
}

/// The concrete "how to still hit the goal" plan.
public struct GapPlan: Hashable, Sendable {
    public var goal: Decimal
    /// `goal − projectedSavings`, rounded to cents (always > 0).
    public var gap: Decimal
    /// Cuts in order: Food & Dining, Shopping, Recreation, Subscriptions, then user-made categories.
    /// Their amounts sum to exactly `min(gap, total cuttable)`.
    public var cuts: [GapCut]
    /// `gap − sum(cuts)`: what cannot be covered by cutting discretionary spending (0 when the plan closes the gap).
    public var uncovered: Decimal

    public init(goal: Decimal, gap: Decimal, cuts: [GapCut], uncovered: Decimal) {
        self.goal = goal
        self.gap = gap
        self.cuts = cuts
        self.uncovered = uncovered
    }

    /// Sum of the cut amounts.
    public var totalCuts: Decimal { cuts.reduce(Decimal(0)) { $0 + $1.amount } }
    /// The cuts cover the whole gap.
    public var closesGap: Bool { uncovered == 0 }
}

/// A plain-English insight card.
public struct Insight: Identifiable, Hashable, Sendable {
    /// Stable for a given kind + subject (e.g. "overPace-<category uuid>").
    public var id: String
    public var kind: InsightKind
    public var title: String
    /// One or two sentences with real dollar figures.
    public var body: String
    /// The headline figure: overPace/underUsual → amount above/below usual; gapPlan → the gap;
    /// frequentSmallPurchases → total spent; topMerchants → top merchant's total; weekendVsWeekday →
    /// difference in daily averages; goalOnTrack/goalMissed → projected (or actual) savings; missingIncome → spent so far;
    /// incomeEstimated → expected income.
    public var amount: Decimal?
    public var sentiment: InsightSentiment
    /// Higher = more important. The list returned by the engine is already sorted by this.
    public var priority: Int
    /// The category the card is about, when there is one (tap to drill in).
    public var categoryID: UUID?
    /// Only for `.gapPlan`.
    public var gapPlan: GapPlan?
    /// Only for `.topMerchants`.
    public var merchants: [MerchantSpend]

    public init(
        id: String, kind: InsightKind, title: String, body: String, amount: Decimal? = nil,
        sentiment: InsightSentiment, priority: Int, categoryID: UUID? = nil, gapPlan: GapPlan? = nil, merchants: [MerchantSpend] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.amount = amount
        self.sentiment = sentiment
        self.priority = priority
        self.categoryID = categoryID
        self.gapPlan = gapPlan
        self.merchants = merchants
    }
}

/// Deterministic, on-device insights. Every number comes from `BudgetEngine` / `ChartData`.
public enum InsightsEngine {
    // Thresholds
    /// A category is over pace at ≥ 15 % and ≥ $10 above usual-by-this-day.
    public static var overPaceRatio: Decimal { Decimal(string: "1.15") ?? 1 }
    public static var underUsualRatio: Decimal { Decimal(string: "0.85") ?? 1 }
    public static var minimumPaceDifference: Decimal { 10 }
    /// "Small purchase" ceiling and minimum count.
    public static var smallPurchaseLimit: Decimal { 15 }
    public static var smallPurchaseMinimumCount: Int { 4 }
    /// Weekend vs weekday daily averages must differ by ≥ 30 %.
    public static var weekendDifferenceRatio: Decimal { Decimal(string: "1.3") ?? 1 }
    /// At most this many over-pace cards (the largest overshoots) are produced.
    public static var maximumOverPaceCards: Int { 3 }

    /// All insights for `month`, most important first. Convenience that builds the snapshot itself.
    public static func insights(
        month: MonthKey,
        now: Date,
        transactions: [TransactionRecord],
        earnings: [WeeklyEarning],
        goal: Decimal,
        categories: [CategoryRecord],
        calendar: LedgerCalendar,
        locale: Locale = .current,
        currencyCode: String = "USD"
    ) -> [Insight] {
        let snapshot = BudgetEngine.snapshot(
            month: month, now: now, transactions: transactions, earnings: earnings, goal: goal, categories: categories, calendar: calendar
        )
        return insights(snapshot: snapshot, transactions: transactions, categories: categories, calendar: calendar, locale: locale, currencyCode: currencyCode)
    }

    /// All insights for an existing snapshot, most important first (ties broken by id).
    /// `transactions` may be the whole store.
    public static func insights(
        snapshot: BudgetSnapshot,
        transactions: [TransactionRecord],
        categories: [CategoryRecord],
        calendar: LedgerCalendar,
        locale: Locale = .current,
        currencyCode: String = "USD"
    ) -> [Insight] {
        let context = Context(snapshot: snapshot, transactions: transactions, categories: categories, calendar: calendar, locale: locale, currencyCode: currencyCode)
        var result: [Insight] = []
        result += incomeInsights(context)
        result += goalInsights(context)
        result += paceInsights(context)
        result += frequentSmallPurchaseInsights(context)
        if let top = topMerchantsInsight(context) { result.append(top) }
        if let weekend = weekendInsight(context) { result.append(weekend) }
        return result.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
    }

    /// The first `count` insights (the Home screen shows three).
    public static func top(_ insights: [Insight], count: Int = 3) -> [Insight] {
        Array(insights.prefix(max(0, count)))
    }

    /// The gap-closing plan, or nil when income is unknown, the goal is on track, or the month is over.
    ///
    /// `gap = goal − projectedSavings` (rounded to cents, `.plain`). Each discretionary category can give up
    /// at most `max(0, projected − spent)` (what is not spent yet, truncated to cents). The target
    /// `min(gap, Σcuttable)` is split in proportion to what is cuttable, each share rounded to cents (`.plain`);
    /// the rounding remainder goes, cent by cent, onto the largest cut that still has room, so the cuts add up
    /// to the target exactly. Bills and Health are never cut; Groceries, Gas, Transportation and Other are left out as needs.
    public static func gapPlan(
        snapshot: BudgetSnapshot,
        transactions: [TransactionRecord],
        categories: [CategoryRecord],
        calendar: LedgerCalendar,
        locale: Locale = .current,
        currencyCode: String = "USD"
    ) -> GapPlan? {
        guard !snapshot.isPastMonth, let savings = snapshot.projectedSavings else { return nil }
        let gap = MoneyFormat.round(snapshot.goal - savings, scale: 2)
        guard gap > 0 else { return nil }

        // Candidates in cut order.
        var candidates: [(category: CategoryRecord, cuttable: Decimal)] = []
        var ordered: [CategoryRecord] = []
        for key in CategoryRecord.discretionaryKeys {
            if let category = categories.first(where: { $0.systemKey == key && !$0.isArchived }) { ordered.append(category) }
        }
        ordered += categories.filter { $0.systemKey == nil && !$0.isArchived }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
        for category in ordered where category.isDiscretionary && !category.isProtected {
            let projected = snapshot.projectedByCategory[category.id] ?? 0
            let spent = snapshot.spentByCategory[category.id] ?? 0
            let cuttable = MoneyFormat.truncate(max(0, projected - spent), scale: 2)
            if cuttable > 0 { candidates.append((category, cuttable)) }
        }

        let totalCuttable = candidates.reduce(Decimal(0)) { $0 + $1.cuttable }
        let target = min(gap, totalCuttable)
        let amounts = allocate(target: target, capacities: candidates.map { $0.cuttable })

        var cuts: [GapCut] = []
        for (index, candidate) in candidates.enumerated() where amounts[index] > 0 {
            let amount = amounts[index]
            let money = MoneyFormat.compact(amount, currencyCode: currencyCode, locale: locale)
            let note: String
            var suggestion: String?
            switch candidate.category.systemKey {
            case "food": note = "Cut dining out by \(money)"
            case "shopping": note = "Cut shopping by \(money)"
            case "recreation": note = "Cut recreation by \(money)"
            case "subscriptions":
                // "Pause one" only when a recurring subscription actually fits inside the amount.
                if let pick = smallestRecurringSubscription(
                    upTo: amount, categoryID: candidate.category.id, month: snapshot.month, transactions: transactions, calendar: calendar
                ) {
                    note = "Pause one subscription (\(money))"
                    suggestion = "\(pick.name) is \(MoneyFormat.string(pick.amount, currencyCode: currencyCode, locale: locale)) a month."
                } else {
                    note = "Cut subscriptions by \(money)"
                }
            default: note = "Cut \(candidate.category.name) by \(money)"
            }
            cuts.append(GapCut(categoryID: candidate.category.id, categoryName: candidate.category.name, amount: amount, note: note, suggestion: suggestion))
        }
        return GapPlan(goal: snapshot.goal, gap: gap, cuts: cuts, uncovered: gap - target)
    }

    /// Splits `target` (cents) across `capacities` (cents) in proportion, never exceeding a capacity,
    /// with the result summing to exactly `min(target, Σcapacities)`. Rounding is `.plain`.
    public static func allocate(target: Decimal, capacities: [Decimal]) -> [Decimal] {
        let caps = capacities.map { MoneyFormat.truncate(max(0, $0), scale: 2) }
        let total = caps.reduce(Decimal(0), +)
        let goal = min(MoneyFormat.round(max(0, target), scale: 2), total)
        guard total > 0, goal > 0 else { return caps.map { _ in Decimal(0) } }

        var shares = caps.map { min($0, MoneyFormat.round(goal * $0 / total, scale: 2)) }
        let cent = Decimal(string: "0.01") ?? 0
        var remainder = goal - shares.reduce(Decimal(0), +)
        // Largest first; ties keep the original order.
        let order = caps.indices.sorted { caps[$0] != caps[$1] ? caps[$0] > caps[$1] : $0 < $1 }
        var guardCounter = 0
        while remainder != 0 && guardCounter < 100_000 {
            guardCounter += 1
            var moved = false
            for index in order {
                if remainder > 0, shares[index] + cent <= caps[index] {
                    shares[index] += cent
                    remainder -= cent
                    moved = true
                    break
                }
                if remainder < 0, shares[index] - cent >= 0 {
                    shares[index] -= cent
                    remainder += cent
                    moved = true
                    break
                }
            }
            if !moved { break }
        }
        return shares
    }

    // MARK: - Internals

    private struct Context {
        let snapshot: BudgetSnapshot
        let transactions: [TransactionRecord]
        let categories: [CategoryRecord]
        let calendar: LedgerCalendar
        let locale: Locale
        let currencyCode: String
        let resolver: CategoryResolver
        let monthTransactions: [TransactionRecord]

        init(snapshot: BudgetSnapshot, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar, locale: Locale, currencyCode: String) {
            self.snapshot = snapshot
            self.transactions = transactions
            self.categories = categories
            self.calendar = calendar
            self.locale = locale
            self.currencyCode = currencyCode
            self.resolver = CategoryResolver(categories: categories)
            self.monthTransactions = BudgetEngine.transactions(in: snapshot.month, from: transactions, calendar: calendar)
        }

        func whole(_ amount: Decimal) -> String { MoneyFormat.whole(amount, currencyCode: currencyCode, locale: locale) }
        func compact(_ amount: Decimal) -> String { MoneyFormat.compact(amount, currencyCode: currencyCode, locale: locale) }
        /// "this month" for the current/future month, "in October" for a past one.
        var when: String { snapshot.isPastMonth ? "in \(InsightsEngine.monthName(snapshot.month))" : "this month" }
    }

    static func monthName(_ month: MonthKey) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return names[min(max(month.month, 1), 12) - 1]
    }

    private static func incomeInsights(_ c: Context) -> [Insight] {
        let s = c.snapshot
        switch s.incomeBasis {
        case .unknown:
            var body = "Add your weekly earnings to see projected savings and a safe-to-spend number."
            if s.spent > 0 { body += " So far you've spent \(c.whole(s.spent)) \(c.when)." }
            return [Insight(
                id: "missingIncome", kind: .missingIncome, title: "Add your earnings", body: body,
                amount: s.spent, sentiment: .neutral, priority: 1000
            )]
        case .estimatedFromHistory:
            guard let expected = s.expectedIncome else { return [] }
            return [Insight(
                id: "incomeEstimated", kind: .incomeEstimated, title: "Income is an estimate",
                body: "No earnings entered for \(monthName(s.month)) yet, so income is estimated at \(c.whole(expected)) from your recent weeks. Enter a week to firm it up.",
                amount: expected, sentiment: .neutral, priority: 200
            )]
        case .entered:
            return []
        }
    }

    private static func goalInsights(_ c: Context) -> [Insight] {
        let s = c.snapshot
        guard let savings = s.projectedSavings else { return [] }
        let goalText = c.whole(s.goal)

        if s.isPastMonth {
            let month = monthName(s.month)
            if savings >= s.goal {
                var body = "You saved \(c.whole(savings)) in \(month)"
                if s.goal > 0 {
                    body += savings == s.goal ? ", right at your \(goalText) goal." : ", \(c.whole(savings - s.goal)) over your \(goalText) goal."
                } else {
                    body += "."
                }
                return [Insight(id: "goalOnTrack", kind: .goalOnTrack, title: "Goal met", body: body, amount: savings, sentiment: .positive, priority: 850)]
            }
            let body: String
            if savings >= 0 {
                body = "You saved \(c.whole(savings)) in \(month), \(c.whole(s.goal - savings)) short of your \(goalText) goal."
            } else {
                body = "You spent \(c.whole(-savings)) more than you earned in \(month), missing your \(goalText) goal by \(c.whole(s.goal - savings))."
            }
            return [Insight(id: "goalMissed", kind: .goalMissed, title: "Goal missed", body: body, amount: savings, sentiment: .warning, priority: 850)]
        }

        if savings >= s.goal {
            var body = "You're on track to save \(c.whole(savings)) this month"
            if s.goal > 0 {
                body += savings == s.goal ? ", right at your \(goalText) goal." : ", \(c.whole(savings - s.goal)) over your \(goalText) goal."
            } else {
                body += "."
            }
            return [Insight(id: "goalOnTrack", kind: .goalOnTrack, title: "On track", body: body, amount: savings, sentiment: .positive, priority: 850)]
        }

        guard let plan = gapPlan(snapshot: s, transactions: c.transactions, categories: c.categories, calendar: c.calendar, locale: c.locale, currencyCode: c.currencyCode) else {
            return []
        }
        return [Insight(
            id: "gapPlan", kind: .gapPlan, title: "How to hit \(goalText)", body: gapPlanBody(plan, c),
            amount: plan.gap, sentiment: .warning, priority: 900, gapPlan: plan
        )]
    }

    private static func gapPlanBody(_ plan: GapPlan, _ c: Context) -> String {
        let goalText = c.whole(plan.goal)
        guard !plan.cuts.isEmpty else {
            return "You're projected to miss your \(goalText) goal by \(c.compact(plan.gap)), and there's nothing left to trim in dining, shopping, recreation or subscriptions this month."
        }
        // "cut dining out by $45, shopping by $30, and pause one subscription ($15)"
        var parts: [String] = []
        var saidCut = false
        for cut in plan.cuts {
            let lowered = cut.note.prefix(1).lowercased() + cut.note.dropFirst()
            if lowered.hasPrefix("cut ") {
                parts.append(saidCut ? String(lowered.dropFirst(4)) : lowered)
                saidCut = true
            } else {
                parts.append(lowered)
            }
        }
        var body = "To hit \(goalText): \(joined(parts))."
        if plan.uncovered > 0 {
            body += " That still leaves \(c.compact(plan.uncovered)) to find; the rest is already spent or goes to essentials."
        }
        return body
    }

    static func joined(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + ", and " + (parts.last ?? "")
        }
    }

    /// Smallest subscription merchant charged in at least two of the last four months (this one included)
    /// whose latest charge is at most `limit`.
    private static func smallestRecurringSubscription(
        upTo limit: Decimal, categoryID: UUID, month: MonthKey, transactions: [TransactionRecord], calendar: LedgerCalendar
    ) -> (name: String, amount: Decimal)? {
        let start = calendar.monthStart(month.adding(months: -3))
        let end = calendar.monthStart(month.next)
        struct Entry { var months = Set<MonthKey>(); var latest = Date.distantPast; var amount: Decimal = 0; var name = "" }
        var entries: [String: Entry] = [:]
        for transaction in transactions where transaction.categoryID == categoryID && transaction.amount > 0 && transaction.date >= start && transaction.date < end {
            let key = MerchantNormalizer.normalize(transaction.merchant)
            guard !key.isEmpty else { continue }
            var entry = entries[key] ?? Entry()
            entry.months.insert(MonthKey(date: transaction.date, calendar: calendar))
            if transaction.date >= entry.latest {
                entry.latest = transaction.date
                entry.amount = transaction.amount
                entry.name = MerchantNormalizer.displayName(transaction.merchant)
            }
            entries[key] = entry
        }
        let picks = entries.filter { $0.value.months.count >= 2 && $0.value.amount <= limit }.sorted {
            if $0.value.amount != $1.value.amount { return $0.value.amount < $1.value.amount }
            return $0.key < $1.key
        }
        return picks.first.map { ($0.value.name, $0.value.amount) }
    }

    private static func paceInsights(_ c: Context) -> [Insight] {
        let s = c.snapshot
        guard s.hasHistory, s.dayOfMonth > 0 else { return [] }
        var over: [(category: CategoryRecord, spent: Decimal, usual: Decimal)] = []
        var under: [(category: CategoryRecord, spent: Decimal, usual: Decimal)] = []
        for (id, usual) in s.usualByThisDayByCategory where usual > 0 {
            let category = c.resolver.record(id)
            // Bills and subscriptions are charged on fixed days, so "by this point in the month" is not a fair
            // yardstick for them until the month is over.
            let fixedCharges = category.systemKey == "bills" || category.systemKey == "subscriptions"
            if fixedCharges && !s.isPastMonth { continue }
            let spent = s.spentByCategory[id] ?? 0
            if spent >= usual * overPaceRatio && spent - usual >= minimumPaceDifference {
                over.append((category, spent, usual))
            } else if spent >= 0 && spent <= usual * underUsualRatio && usual - spent >= minimumPaceDifference
                        && (s.isPastMonth || s.dayOfMonth >= 7) {
                under.append((category, spent, usual))
            }
        }
        over.sort { ($0.spent - $0.usual, $1.category.name) > ($1.spent - $1.usual, $0.category.name) }
        under.sort { ($0.usual - $0.spent, $1.category.name) > ($1.usual - $1.spent, $0.category.name) }

        var result: [Insight] = []
        for (index, item) in over.prefix(maximumOverPaceCards).enumerated() {
            // "40% above your usual $220" — or "about 5.5 times your usual $93" once it is more than triple.
            let ratio = item.spent / item.usual
            let comparison: String
            if ratio >= 3 {
                let rounded = MoneyFormat.round(ratio, scale: ratio >= 10 ? 0 : 1)
                comparison = "about \(NSDecimalNumber(decimal: rounded).stringValue) times your usual \(c.whole(item.usual))"
            } else {
                comparison = "\(MoneyFormat.percent(ratio - 1)) above your usual \(c.whole(item.usual))"
            }
            let body: String
            if s.isPastMonth {
                body = "\(item.category.name) came to \(c.whole(item.spent)) in \(monthName(s.month)), \(comparison)."
            } else {
                body = "\(item.category.name) is at \(c.whole(item.spent)), \(comparison) by this point in the month."
            }
            result.append(Insight(
                id: "overPace-\(item.category.id.uuidString)", kind: .overPace, title: "\(item.category.name) is running high", body: body,
                amount: item.spent - item.usual, sentiment: .warning, priority: max(700, 800 - index), categoryID: item.category.id
            ))
        }
        for (index, item) in under.prefix(2).enumerated() {
            let percent = MoneyFormat.percent((item.usual - item.spent) / item.usual)
            let body: String
            if MoneyFormat.round(item.spent, scale: 0) <= 0 {
                body = s.isPastMonth
                    ? "You spent nothing on \(item.category.name) in \(monthName(s.month)). A usual month is \(c.whole(item.usual)). Nice work."
                    : "You haven't spent anything on \(item.category.name) this month. You've usually spent \(c.whole(item.usual)) by now. Nice work."
            } else if s.isPastMonth {
                body = "\(item.category.name) came to \(c.whole(item.spent)) in \(monthName(s.month)), \(percent) below your usual \(c.whole(item.usual)). Nice work."
            } else {
                body = "\(item.category.name) is at \(c.whole(item.spent)), \(percent) below your usual \(c.whole(item.usual)) by this point in the month. Nice work."
            }
            result.append(Insight(
                id: "underUsual-\(item.category.id.uuidString)", kind: .underUsual, title: "\(item.category.name) is under control", body: body,
                amount: item.usual - item.spent, sentiment: .positive, priority: 300 - index, categoryID: item.category.id
            ))
        }
        return result
    }

    private static func frequentSmallPurchaseInsights(_ c: Context) -> [Insight] {
        struct Group { var count = 0; var total: Decimal = 0; var name = ""; var latest = Date.distantPast }
        var coffee = Group()
        var groups: [String: Group] = [:]
        for transaction in c.monthTransactions where transaction.amount > 0 && transaction.amount <= smallPurchaseLimit {
            let key = MerchantNormalizer.normalize(transaction.merchant)
            guard !key.isEmpty else { continue }
            if c.resolver.record(c.resolver.resolve(transaction.categoryID)).isProtected { continue }
            if Categorizer.isCoffeeMerchant(key) {
                coffee.count += 1
                coffee.total += transaction.amount
                continue
            }
            var group = groups[key] ?? Group()
            group.count += 1
            group.total += transaction.amount
            if transaction.date >= group.latest {
                group.latest = transaction.date
                group.name = MerchantNormalizer.displayName(transaction.merchant)
            }
            groups[key] = group
        }

        var result: [Insight] = []
        if coffee.count >= smallPurchaseMinimumCount {
            result.append(Insight(
                id: "frequent-coffee", kind: .frequentSmallPurchases, title: "Coffee runs add up",
                body: "\(coffee.count) coffee runs \(c.when) = \(c.whole(coffee.total)). Halving that saves \(c.whole(coffee.total / 2)).",
                amount: coffee.total, sentiment: .neutral, priority: 600
            ))
        }
        let others = groups.filter { $0.value.count >= smallPurchaseMinimumCount }.sorted {
            if $0.value.total != $1.value.total { return $0.value.total > $1.value.total }
            return $0.key < $1.key
        }
        for (index, entry) in others.prefix(3).enumerated() {
            let group = entry.value
            result.append(Insight(
                id: "frequent-\(entry.key)", kind: .frequentSmallPurchases, title: "Small purchases at \(group.name)",
                body: "\(group.count) small purchases at \(group.name) \(c.when) = \(c.whole(group.total)). Halving that saves \(c.whole(group.total / 2)).",
                amount: group.total, sentiment: .neutral, priority: 590 - index
            ))
        }
        return result
    }

    private static func topMerchantsInsight(_ c: Context) -> Insight? {
        let merchants = ChartData.topMerchants(month: c.snapshot.month, transactions: c.transactions, calendar: c.calendar, limit: 5)
        guard let first = merchants.first else { return nil }
        func change(_ merchant: MerchantSpend) -> String {
            if merchant.isNew { return "new \(c.snapshot.isPastMonth ? "that month" : "this month")" }
            let delta = MoneyFormat.round(merchant.change, scale: 0)
            let reference = c.snapshot.isPastMonth ? "the month before" : "last month"
            if delta == 0 { return "about the same as \(reference)" }
            return delta > 0 ? "up \(c.whole(delta)) from \(reference)" : "down \(c.whole(-delta)) from \(reference)"
        }
        var body = "\(first.displayName) is your top merchant \(c.when) at \(c.whole(first.amount)) (\(change(first)))."
        let rest = merchants.dropFirst().prefix(2).map { "\($0.displayName) \(c.whole($0.amount)) (\(change($0)))" }
        if !rest.isEmpty { body += " Next: \(joined(Array(rest)))." }
        return Insight(
            id: "topMerchants", kind: .topMerchants, title: "Top merchants", body: body,
            amount: first.amount, sentiment: .neutral, priority: 500, merchants: merchants
        )
    }

    private static func weekendInsight(_ c: Context) -> Insight? {
        let s = c.snapshot
        guard s.dayOfMonth > 0 else { return nil }
        var weekendDays = 0
        var weekdayDays = 0
        let start = c.calendar.monthStart(s.month)
        for offset in 0..<s.dayOfMonth {
            if c.calendar.isWeekend(c.calendar.startOfDay(start, addingDays: offset)) { weekendDays += 1 } else { weekdayDays += 1 }
        }
        guard weekendDays >= 2, weekdayDays >= 3 else { return nil }

        var weekendTotal: Decimal = 0
        var weekdayTotal: Decimal = 0
        for transaction in c.monthTransactions {
            let category = c.resolver.record(c.resolver.resolve(transaction.categoryID))
            // Fixed charges land on arbitrary days and would drown out the pattern.
            if category.systemKey == "bills" || category.systemKey == "subscriptions" { continue }
            if c.calendar.isWeekend(transaction.date) { weekendTotal += transaction.amount } else { weekdayTotal += transaction.amount }
        }
        let weekendAverage = max(0, weekendTotal) / Decimal(weekendDays)
        let weekdayAverage = max(0, weekdayTotal) / Decimal(weekdayDays)
        let higher = max(weekendAverage, weekdayAverage)
        let lower = min(weekendAverage, weekdayAverage)
        guard higher >= 1, higher >= lower * weekendDifferenceRatio else { return nil }

        let weekendHigher = weekendAverage >= weekdayAverage
        let body: String
        if MoneyFormat.round(lower, scale: 0) <= 0 {
            body = weekendHigher
                ? "You spend about \(c.whole(higher)) a day on weekends and almost nothing on weekdays."
                : "You spend about \(c.whole(higher)) a day on weekdays and almost nothing on weekends."
        } else {
            let percent = MoneyFormat.percent((higher - lower) / lower)
            body = weekendHigher
                ? "You spend about \(c.whole(weekendAverage)) a day on weekends and \(c.whole(weekdayAverage)) on weekdays. That's \(percent) more on weekends."
                : "You spend about \(c.whole(weekdayAverage)) a day on weekdays and \(c.whole(weekendAverage)) on weekends. That's \(percent) more on weekdays."
        }
        return Insight(
            id: "weekendVsWeekday", kind: .weekendVsWeekday, title: weekendHigher ? "Weekends cost more" : "Weekdays cost more", body: body,
            amount: higher - lower, sentiment: .neutral, priority: 400
        )
    }
}
