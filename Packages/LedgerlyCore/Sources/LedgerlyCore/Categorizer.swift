#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// Why a category was chosen.
public enum CategorizationReason: String, Codable, Sendable {
    /// The user's own "always categorize X as Y" rule.
    case learnedRule
    /// A category name supplied with the data (e.g. a CSV "Category" column).
    case categoryHint
    /// The built-in keyword table.
    case builtInKeyword
    /// Nothing matched → Other.
    case fallback
}

public struct CategorizationResult: Hashable, Sendable {
    public var categoryID: UUID
    public var reason: CategorizationReason
    /// The built-in keyword (normalized) that matched, for `.builtInKeyword`.
    public var matchedKeyword: String?

    public init(categoryID: UUID, reason: CategorizationReason, matchedKeyword: String? = nil) {
        self.categoryID = categoryID
        self.reason = reason
        self.matchedKeyword = matchedKeyword
    }
}

/// One row of the built-in keyword table.
public struct KeywordRule: Hashable, Sendable {
    /// Normalized words that must appear next to each other as whole words, e.g. ["TRADER", "JOES"].
    public var tokens: [String]
    public var systemKey: String
    /// Generic words ("PIZZA", "PHARMACY") lose to brand names.
    public var isGeneric: Bool

    public init(tokens: [String], systemKey: String, isGeneric: Bool = false) {
        self.tokens = tokens
        self.systemKey = systemKey
        self.isGeneric = isGeneric
    }

    public var keyword: String { tokens.joined(separator: " ") }
}

/// Picks a category for a merchant: (1) learned rule, (2) built-in keywords, (3) Other.
public struct Categorizer: Sendable {
    public let rules: [MerchantRule]
    public let categories: [CategoryRecord]

    private let ruleLookup: [String: UUID]
    private let activeIDs: Set<UUID>
    private let activeBySystemKey: [String: UUID]
    private let otherID: UUID

    /// - Parameters:
    ///   - rules: learned merchant → category rules (`normalizedMerchant` is re-normalized defensively).
    ///   - categories: every category, archived ones included. Archived categories are never chosen.
    public init(rules: [MerchantRule] = [], categories: [CategoryRecord] = DefaultCategories.all) {
        self.rules = rules
        self.categories = categories
        var lookup: [String: UUID] = [:]
        for rule in rules {
            let key = MerchantNormalizer.normalize(rule.normalizedMerchant)
            if !key.isEmpty { lookup[key] = rule.categoryID }
        }
        self.ruleLookup = lookup
        var active = Set<UUID>()
        var bySystemKey: [String: UUID] = [:]
        for category in categories.sorted(by: { $0.sortOrder < $1.sortOrder }) where !category.isArchived {
            active.insert(category.id)
            if let key = category.systemKey, bySystemKey[key] == nil { bySystemKey[key] = category.id }
        }
        self.activeIDs = active
        self.activeBySystemKey = bySystemKey
        // "Other" is the last resort even if the user archived it.
        self.otherID = bySystemKey["other"]
            ?? categories.first(where: { $0.systemKey == "other" })?.id
            ?? DefaultCategories.otherID
    }

    /// Categorizes a raw merchant name.
    ///
    /// Order: learned rule (exact normalized match first, otherwise the longest rule whose words are a
    /// whole-word prefix of the merchant, so a rule for "STARBUCKS" also covers "STARBUCKS CHICAGO IL")
    /// → `categoryHint` (a category name such as a CSV cell) → built-in keywords → Other.
    /// A rule or keyword pointing at an archived or deleted category is skipped.
    public func categorize(merchant: String, categoryHint: String? = nil) -> CategorizationResult {
        let normalized = MerchantNormalizer.normalize(merchant)
        let tokens = MerchantNormalizer.tokens(normalized)

        if !tokens.isEmpty {
            if let id = ruleLookup[normalized], activeIDs.contains(id) {
                return CategorizationResult(categoryID: id, reason: .learnedRule)
            }
            if tokens.count > 1 {
                for length in stride(from: tokens.count - 1, through: 1, by: -1) {
                    let prefix = tokens[0..<length].joined(separator: " ")
                    if let id = ruleLookup[prefix], activeIDs.contains(id) {
                        return CategorizationResult(categoryID: id, reason: .learnedRule)
                    }
                }
            }
        }

        if let hint = categoryHint, let id = categoryID(forName: hint) {
            return CategorizationResult(categoryID: id, reason: .categoryHint)
        }

        if let match = Categorizer.builtInMatch(tokens: tokens), let id = activeBySystemKey[match.systemKey] {
            return CategorizationResult(categoryID: id, reason: .builtInKeyword, matchedKeyword: match.keyword)
        }

        return CategorizationResult(categoryID: otherID, reason: .fallback)
    }

    /// Finds a non-archived category by its name (case-insensitive), or by a common bank-export
    /// category word ("Restaurants", "Grocery", "Entertainment", …).
    public func categoryID(forName name: String) -> UUID? {
        let key = MerchantNormalizer.searchKey(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let exact = categories.first(where: { !$0.isArchived && MerchantNormalizer.searchKey($0.name) == key }) {
            return exact.id
        }
        if let systemKey = Categorizer.exportCategorySynonyms[key], let id = activeBySystemKey[systemKey] {
            return id
        }
        return nil
    }

    /// The category id used when nothing matches.
    public var fallbackCategoryID: UUID { otherID }

    // MARK: Built-in keywords

    /// The system key the built-in table gives a raw merchant name, ignoring learned rules. Nil when nothing matches.
    public static func builtInSystemKey(for merchant: String) -> String? {
        builtInMatch(tokens: MerchantNormalizer.tokens(MerchantNormalizer.normalize(merchant)))?.systemKey
    }

    /// True for coffee shops ("STARBUCKS", "… COFFEE", "CAFE …"). Takes a raw or normalized name.
    public static func isCoffeeMerchant(_ merchant: String) -> Bool {
        let tokens = MerchantNormalizer.tokens(MerchantNormalizer.normalize(merchant))
        guard !tokens.isEmpty else { return false }
        for keyword in coffeeKeywords {
            if firstIndex(of: keyword, in: tokens) != nil { return true }
        }
        return false
    }

    /// Best keyword match: brand names beat generic words, longer keywords beat shorter ones
    /// ("UBER EATS" → food beats "UBER" → transportation), then the earliest position wins.
    static func builtInMatch(tokens: [String]) -> KeywordRule? {
        guard !tokens.isEmpty else { return nil }
        let index = keywordIndex
        var best: (rule: KeywordRule, position: Int)?
        for (position, token) in tokens.enumerated() {
            guard let candidates = index[token] else { continue }
            for rule in candidates {
                guard position + rule.tokens.count <= tokens.count else { continue }
                var matched = true
                for offset in 1..<max(rule.tokens.count, 1) where tokens[position + offset] != rule.tokens[offset] {
                    matched = false
                    break
                }
                guard matched else { continue }
                if let current = best {
                    let better: Bool
                    if rule.isGeneric != current.rule.isGeneric {
                        better = !rule.isGeneric
                    } else if rule.tokens.count != current.rule.tokens.count {
                        better = rule.tokens.count > current.rule.tokens.count
                    } else {
                        better = position < current.position
                    }
                    if better { best = (rule, position) }
                } else {
                    best = (rule, position)
                }
            }
        }
        return best?.rule
    }

    private static func firstIndex(of keyword: [String], in tokens: [String]) -> Int? {
        guard !keyword.isEmpty, keyword.count <= tokens.count else { return nil }
        for start in 0...(tokens.count - keyword.count) where Array(tokens[start..<(start + keyword.count)]) == keyword {
            return start
        }
        return nil
    }

    /// The whole built-in table, normalized.
    public static let builtInKeywords: [KeywordRule] = {
        var rules: [KeywordRule] = []
        var seen = Set<String>()
        func add(_ names: [String], _ systemKey: String, generic: Bool = false) {
            for name in names {
                let tokens = MerchantNormalizer.tokens(MerchantNormalizer.normalize(name))
                guard !tokens.isEmpty else { continue }
                let key = tokens.joined(separator: " ")
                guard seen.insert(key).inserted else { continue }
                rules.append(KeywordRule(tokens: tokens, systemKey: systemKey, isGeneric: generic))
            }
        }
        add(gasBrands, "gas")
        add(foodBrands, "food")
        add(foodGeneric, "food", generic: true)
        add(shoppingBrands, "shopping")
        add(groceryBrands, "groceries")
        add(groceryGeneric, "groceries", generic: true)
        add(subscriptionBrands, "subscriptions")
        add(transportationBrands, "transportation")
        add(transportationGeneric, "transportation", generic: true)
        add(healthBrands, "health")
        add(healthGeneric, "health", generic: true)
        add(billsBrands, "bills")
        add(billsGeneric, "bills", generic: true)
        add(recreationBrands, "recreation")
        add(recreationGeneric, "recreation", generic: true)
        return rules
    }()

    private static let keywordIndex: [String: [KeywordRule]] = {
        var index: [String: [KeywordRule]] = [:]
        for rule in builtInKeywords {
            if let first = rule.tokens.first { index[first, default: []].append(rule) }
        }
        return index
    }()

    private static let coffeeKeywords: [[String]] = [
        "Starbucks", "Dunkin", "Dunkin Donuts", "Peet's", "Peets Coffee", "Dutch Bros", "Tim Hortons", "Caribou",
        "Blue Bottle", "Intelligentsia", "Philz", "Colectivo", "La Colombe", "Scooter's Coffee", "Biggby",
        "Coffee", "Cafe", "Caffe", "Espresso", "Roasters", "Roastery"
    ].map { MerchantNormalizer.tokens(MerchantNormalizer.normalize($0)) }

    /// Category words seen in Apple Card / bank exports → system key.
    private static let exportCategorySynonyms: [String: String] = [
        "restaurants": "food", "restaurant": "food", "food & drink": "food", "food and drink": "food", "dining": "food",
        "food": "food", "coffee": "food", "fast food": "food",
        "grocery": "groceries", "groceries": "groceries", "supermarkets": "groceries",
        "gas": "gas", "gas stations": "gas", "fuel": "gas", "gasoline": "gas",
        "shopping": "shopping", "merchandise": "shopping", "retail": "shopping",
        "entertainment": "recreation", "recreation": "recreation", "movies": "recreation",
        "utilities": "bills", "bills": "bills", "bills & utilities": "bills", "insurance": "bills", "phone": "bills",
        "transportation": "transportation", "transit": "transportation", "travel": "transportation", "rideshare": "transportation",
        "parking": "transportation",
        "health": "health", "medical": "health", "health & wellness": "health", "pharmacy": "health", "healthcare": "health",
        "subscriptions": "subscriptions", "subscription": "subscriptions", "services": "subscriptions",
        "other": "other", "miscellaneous": "other", "misc": "other"
    ]

    // MARK: Keyword lists (written the way people write them; normalized when the table is built)

    private static let gasBrands: [String] = [
        "Shell", "Chevron", "BP", "Speedway", "Exxon", "ExxonMobil", "Mobil", "Marathon", "Citgo", "Sunoco", "Valero",
        "Phillips 66", "Conoco", "Arco", "Texaco", "Casey's", "Kwik Trip", "Kwik Star", "QuikTrip", "Wawa", "Sheetz",
        "Thorntons", "Love's", "Flying J", "Circle K", "Costco Gas", "Costco Fuel", "Sam's Fuel", "Sams Club Fuel",
        "Murphy USA", "Murphy Express", "Sinclair", "RaceTrac", "Meijer Gas", "Buc-ee's", "Bucees", "Kum & Go",
        "Cenex", "Holiday Station", "Holiday Stationstores", "Maverik", "GetGo", "Kroger Fuel", "Walmart Fuel", "Union 76",
        "Minuteman", "Road Ranger", "Gas N Wash", "Fuel", "Gasoline", "Petroleum"
    ]

    private static let foodBrands: [String] = [
        "Starbucks", "McDonald's", "Chipotle", "Dunkin", "Dunkin Donuts", "Subway", "Taco Bell", "Burger King", "Wendy's",
        "Chick-fil-A", "Chickfila", "Panera", "Domino's", "Pizza Hut", "Papa John's", "KFC", "Popeyes", "Five Guys",
        "Shake Shack", "Portillo's", "Culver's", "Jimmy John's", "Potbelly", "Panda Express", "Sonic Drive", "Arby's",
        "Dairy Queen", "IHOP", "Denny's", "Olive Garden", "Applebee's", "Chili's", "Buffalo Wild Wings", "Peet's",
        "Dutch Bros", "Tim Hortons", "Caribou Coffee", "Blue Bottle", "Intelligentsia", "Philz", "Colectivo", "La Colombe",
        "DoorDash", "Grubhub", "Uber Eats", "UberEats", "Postmates", "Lou Malnati's", "Giordano's", "Noodles & Company",
        "Qdoba", "Sweetgreen", "Jersey Mike's", "Raising Cane's", "In-N-Out", "Whataburger", "Wingstop", "Little Caesars",
        "Krispy Kreme", "Jack in the Box", "Carl's Jr", "Hardee's", "White Castle", "Steak n Shake", "Cracker Barrel",
        "Texas Roadhouse", "Outback Steakhouse", "Red Lobster", "Cheesecake Factory", "Nando's", "Cava", "Panda Exp",
        "Einstein Bros", "Auntie Anne's", "Baskin Robbins", "Cold Stone", "Jamba", "Smoothie King", "Insomnia Cookies",
        "Crumbl", "Stan's Donuts", "Do-Rite Donuts", "Portillos Hot Dogs", "Buona", "Nando's Peri Peri", "Seamless", "Caviar"
    ]

    private static let foodGeneric: [String] = [
        "Coffee", "Cafe", "Caffe", "Espresso", "Restaurant", "Ristorante", "Pizza", "Pizzeria", "Grill", "Diner", "Bakery",
        "Taqueria", "Tacos", "Sushi", "Ramen", "BBQ", "Burger", "Burgers", "Bistro", "Deli", "Kitchen", "Eatery", "Steakhouse",
        "Tavern", "Pub", "Brewery", "Donuts", "Bagels", "Noodle", "Thai", "Cantina", "Trattoria", "Creamery", "Boba", "Teahouse"
    ]

    private static let shoppingBrands: [String] = [
        "Target", "Amazon", "Amzn", "Amazon.com", "Walmart", "Wal-Mart", "Wal Mart", "Best Buy", "Home Depot", "Lowe's", "IKEA",
        "Macy's", "Kohl's", "Nordstrom", "TJ Maxx", "TJMaxx", "Marshalls", "Ross Stores", "Ross Dress", "Old Navy", "Gap",
        "Nike", "Adidas", "Apple Store", "eBay", "Etsy", "Sephora", "Ulta", "H&M", "Zara", "Uniqlo", "Dollar Tree",
        "Dollar General", "Five Below", "Bath & Body Works", "Menards", "Ace Hardware", "Michaels", "Hobby Lobby", "Wayfair",
        "Shein", "Temu", "Burlington", "JCPenney", "Banana Republic", "Lululemon", "Foot Locker", "Dick's Sporting",
        "Bed Bath", "Container Store", "Crate & Barrel", "Staples", "Office Depot", "Micro Center", "Costco.com", "PetSmart",
        "Petco", "Chewy", "AliExpress", "Barnes & Noble", "HomeGoods", "World Market", "Urban Outfitters", "American Eagle",
        "Victoria's Secret", "Kay Jewelers", "Zappos", "DSW", "Famous Footwear", "Harbor Freight", "AutoZone", "O'Reilly Auto"
    ]

    private static let groceryBrands: [String] = [
        "Jewel-Osco", "Jewel Osco", "Jewel", "Aldi", "Trader Joe's", "Whole Foods", "WholeFds", "Kroger", "Mariano's", "Meijer",
        "Costco", "Costco Whse", "Sam's Club", "SamsClub", "Safeway", "Publix", "Hy-Vee", "HyVee", "Wegmans", "Fresh Thyme",
        "Woodman's", "Pete's Fresh Market", "Tony's Fresh Market", "H Mart", "HMart", "Patel Brothers", "Sprouts", "Food Lion",
        "Giant Eagle", "Stop & Shop", "H-E-B", "HEB", "Albertsons", "WinCo", "Instacart", "Fresh Market", "Piggly Wiggly",
        "Schnucks", "Food 4 Less", "Save A Lot", "Lidl", "Ralphs", "Vons", "Harris Teeter", "ShopRite", "Fry's Food",
        "King Soopers", "Smith's Food", "Cermak Fresh Market", "Fresh Farms", "Butera", "Caputo's", "Valli Produce",
        "Walmart Grocery", "Walmart Neighborhood Market", "Target Grocery", "Amazon Fresh", "Market Basket", "BJ's Wholesale"
    ]

    private static let groceryGeneric: [String] = ["Grocery", "Groceries", "Supermarket", "Supermercado", "Produce", "Foods"]

    private static let subscriptionBrands: [String] = [
        "Netflix", "Spotify", "Hulu", "Disney Plus", "DisneyPlus", "HBO", "HBO Max", "YouTube Premium", "YouTube TV", "YouTube",
        "YouTubePremium", "Apple Music", "Apple TV", "Apple.com/Bill", "Apple Com Bill", "iCloud", "Amazon Prime", "Prime Video",
        "Audible", "Paramount", "Peacock", "Patreon", "Dropbox", "Adobe", "Microsoft", "Google One", "Google Storage",
        "ChatGPT", "OpenAI", "Claude", "Anthropic", "GitHub", "NYTimes", "New York Times", "Peloton", "Whoop", "Crunchyroll",
        "SiriusXM", "Duolingo", "Notion", "1Password", "Kindle Unlimited", "Pandora", "Tidal", "Substack", 
        "LinkedIn Premium", "Canva", "Evernote", "Headspace", "Strava", "Nintendo Online", "PlayStation Plus",
        "Xbox Game Pass", "Wall Street Journal", "WSJ", "Washington Post", "Chicago Tribune", "ESPN Plus", "Sling", "FuboTV",
        "Discovery Plus", "Apple One", "Google Play", "Zoom", "Slack", "Proton", "NordVPN", "ExpressVPN"
    ]

    private static let transportationBrands: [String] = [
        "Uber", "Lyft", "Ventra", "CTA", "Metra", "Amtrak", "Pace Bus", "Divvy", "SpotHero", "ParkMobile",
        "ParkChicago", "I-Pass", "IPass", "Illinois Tollway", "Tollway", "E-ZPass", "EZPass", "Greyhound", "MTA", "BART",
        "Delta Air", "United Airlines", "American Airlines", "Southwest Airlines", "Southwes", "JetBlue", "Spirit Airlines",
        "Frontier Airlines", "Alaska Airlines", "Megabus", "Zipcar", "Turo", "Hertz", "Enterprise Rent", "Avis", "Budget Rent",
        "LAZ Parking", "SP Plus", "WMATA", "Caltrain", "Clipper", "NJ Transit", "MBTA", "SEPTA"
    ]

    private static let transportationGeneric: [String] = ["Parking", "Taxi", "Cab", "Transit", "Toll", "Tolls", "Rideshare", "Garage", "Airlines", "Airways"]

    private static let healthBrands: [String] = [
        "CVS", "Walgreens", "Rite Aid", "Duane Reade", "Planet Fitness", "LA Fitness", "Anytime Fitness", "XSport",
        "YMCA", "Lifetime Fitness", "Life Time", "Orangetheory", "Equinox", "Crunch Fitness", "LabCorp", "Quest Diagnostics",
        "Northwestern Medicine", "GNC", "Vitamin Shoppe", "Kaiser", "Aspen Dental", "LensCrafters", "Warby Parker",
        "Walmart Pharmacy", "Costco Pharmacy", "Target Pharmacy", "Jewel Pharmacy", "Minute Clinic", "MinuteClinic", "Zocdoc",
        "Rush University Medical", "Northshore", "Endeavor Health", "OSF", "Athletico", "One Medical", "GoodRx", "Hims", "Teladoc"
    ]

    private static let healthGeneric: [String] = [
        "Pharmacy", "Dental", "Dentist", "Clinic", "Hospital", "Medical", "Urgent Care", "Optical", "Chiropractic",
        "Dermatology", "Pediatrics", "Physicians", "Health", "Fitness", "Gym", "Yoga", "Orthodontics", "Vision", "Therapy", "Drugstore"
    ]

    private static let billsBrands: [String] = [
        "ComEd", "Commonwealth Edison", "Nicor", "Nicor Gas", "Peoples Gas", "Xfinity", "Comcast", "AT&T", "ATT", "Verizon",
        "T-Mobile", "TMobile", "Sprint", "Mint Mobile", "Spectrum", "Cox Communications", "Google Fi", "State Farm",
        "Geico", "Progressive", "Allstate", "Duke Energy", "Con Edison", "ConEd", "PG&E", "PGE", "Ameren", "Xcel Energy",
        "National Grid", "Dominion Energy", "DTE Energy", "We Energies", "Consumers Energy", "Cricket Wireless", "Boost Mobile",
        "US Cellular", "Metro by T-Mobile", "Liberty Mutual", "Farmers Insurance", "USAA", "Nationwide", "Lemonade",
        "North Shore Gas", "Republic Services", "Waste Management", "Frontier Communications", "RCN", "Astound", "Optimum",
        "CenturyLink", "Dish Network", "DirecTV", "City of Chicago Water", "Village of Mundelein"
    ]

    private static let billsGeneric: [String] = [
        "Electric", "Utility", "Utilities", "Water Dept", "Water Bill", "Water Department", "Insurance", "Energy", "Wireless",
        "Sewer", "Internet", "Broadband", "Rent", "Mortgage", "HOA"
    ]

    private static let recreationBrands: [String] = [
        "AMC", "AMC Theatres", "Regal", "Cinemark", "Marcus Theatres", "Fandango", "Steam", "SteamGames", "Steam Games",
        "Steampowered", "PlayStation", "Xbox", "Nintendo", "Ticketmaster", "StubHub", "Eventbrite", "Dave & Buster's",
        "Topgolf", "Main Event", "Bowlero", "GameStop", "Live Nation", "SeatGeek", "Twitch", "Epic Games", "Riot Games",
        "Six Flags", "Great Wolf", "Sky Zone", "Urban Air", "Pinstripes", "Punch Bowl", "Round1", "Chuck E Cheese",
        "Alamo Drafthouse", "Landmark Theatres", "Music Box Theatre", "iPic", "Emagine", "Classic Cinemas", "AXS",
        "Blizzard", "Roblox", "Shedd Aquarium", "Field Museum", "Art Institute", "Lincoln Park Zoo", "Brookfield Zoo",
        "Navy Pier", "Wrigley Field", "United Center", "Soldier Field", "Ravinia", "WhirlyBall", "Lucky Strike"
    ]

    private static let recreationGeneric: [String] = [
        "Cinema", "Cinemas", "Theatre", "Theatres", "Theater", "Theaters", "Bowling", "Museum", "Zoo", "Arcade", "Golf",
        "Aquarium", "Concert", "Tickets", "Billiards", "Karaoke", "Mini Golf", "Escape Room", "Trampoline", "Skating", "Games"
    ]
}
