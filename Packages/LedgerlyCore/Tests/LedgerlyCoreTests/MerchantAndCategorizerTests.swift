import Foundation
import XCTest
@testable import LedgerlyCore

final class MerchantNormalizerTests: XCTestCase {
    private func n(_ text: String) -> String { MerchantNormalizer.normalize(text) }

    func testStoreNumberIsDropped() { XCTAssertEqual(n("SHELL OIL 57444"), "SHELL OIL") }
    func testCaseAndWhitespace() { XCTAssertEqual(n("  starbucks   coffee "), "STARBUCKS COFFEE") }
    func testHashStoreNumber() { XCTAssertEqual(n("Starbucks #1234"), "STARBUCKS") }
    func testShortHashStoreNumber() { XCTAssertEqual(n("Jewel-Osco #12"), "JEWEL OSCO") }
    func testLongZeroPaddedNumber() { XCTAssertEqual(n("TARGET 00012345"), "TARGET") }
    func testApostropheIsRemoved() { XCTAssertEqual(n("McDonald's"), "MCDONALDS") }
    func testCurlyApostrophe() { XCTAssertEqual(n("Trader Joe\u{2019}s"), "TRADER JOES") }
    func testPunctuationBecomesSpace() { XCTAssertEqual(n("JEWEL-OSCO"), "JEWEL OSCO") }
    func testAmpersand() { XCTAssertEqual(n("AT&T"), "AT T") }
    func testDiacritics() { XCTAssertEqual(n("Café Résumé"), "CAFE RESUME") }
    func testProcessorPrefix() { XCTAssertEqual(n("SQ *BLUE BOTTLE COFFEE"), "BLUE BOTTLE COFFEE") }
    func testPaypalPrefix() { XCTAssertEqual(n("PAYPAL *SPOTIFY"), "SPOTIFY") }
    func testReferenceCodeAfterStar() { XCTAssertEqual(n("AMZN Mktp US*2K4LM9XY1"), "AMZN MKTP US") }
    func testLeadingSmallNumberKept() { XCTAssertEqual(n("7-Eleven 34567"), "7 ELEVEN") }
    func testShortBrandNumberKept() { XCTAssertEqual(n("Phillips 66"), "PHILLIPS 66") }
    func testGluedStoreNumber() { XCTAssertEqual(n("STARBUCKS1234"), "STARBUCKS") }
    func testStoreWordWithNumber() { XCTAssertEqual(n("Walgreens Store 4521"), "WALGREENS") }
    func testPhoneNumberDropped() { XCTAssertEqual(n("NETFLIX.COM 866-579-7172"), "NETFLIX COM") }
    func testOnlyDigitsFallsBack() { XCTAssertEqual(n("123456"), "123456") }
    func testBlank() {
        XCTAssertEqual(n("   "), "")
        XCTAssertTrue(MerchantNormalizer.isBlank(" \n"))
        XCTAssertTrue(MerchantNormalizer.isBlank(nil))
        XCTAssertFalse(MerchantNormalizer.isBlank("x"))
    }
    func testSameMerchantDifferentSpellingsMatch() {
        XCTAssertEqual(n("SHELL OIL 57444"), n("Shell Oil #99"))
        XCTAssertEqual(n("shell   oil"), n("SHELL OIL 12345678"))
    }
    func testIdempotent() {
        for raw in ["SHELL OIL 57444", "McDonald's #123", "SQ *BLUE BOTTLE", "7-Eleven", "Trader Joe's"] {
            XCTAssertEqual(n(n(raw)), n(raw), raw)
        }
    }
    func testDisplayNameKeepsCaseAndCollapsesSpaces() {
        XCTAssertEqual(MerchantNormalizer.displayName("  Lou   Malnati's \n"), "Lou Malnati's")
    }
    func testSearchKey() { XCTAssertEqual(MerchantNormalizer.searchKey("Café Olé"), "cafe ole") }
}

final class CategorizerTests: XCTestCase {
    private let categorizer = Categorizer()

    private func key(_ merchant: String) -> String? { Categorizer.builtInSystemKey(for: merchant) }

    func testSpecGasKeywords() {
        for merchant in ["Shell", "Chevron", "BP", "Speedway", "SHELL OIL 57444"] {
            XCTAssertEqual(categorizer.categorize(merchant: merchant).categoryID, T.id("gas"), merchant)
        }
    }
    func testSpecFoodKeywords() {
        for merchant in ["Starbucks", "McDonald's", "Chipotle", "STARBUCKS #1234"] {
            XCTAssertEqual(categorizer.categorize(merchant: merchant).categoryID, T.id("food"), merchant)
        }
    }
    func testSpecShoppingKeywords() {
        for merchant in ["Target", "Amazon", "Walmart", "TARGET 00012345", "AMZN Mktp US*2K4LM9XY1"] {
            XCTAssertEqual(categorizer.categorize(merchant: merchant).categoryID, T.id("shopping"), merchant)
        }
    }
    func testSpecGroceryKeywords() {
        for merchant in ["Jewel-Osco", "Aldi", "Trader Joe's", "JEWEL OSCO 3456"] {
            XCTAssertEqual(categorizer.categorize(merchant: merchant).categoryID, T.id("groceries"), merchant)
        }
    }
    func testSpecSubscriptionKeywords() {
        for merchant in ["Netflix", "Spotify", "NETFLIX.COM", "PAYPAL *SPOTIFY"] {
            XCTAssertEqual(categorizer.categorize(merchant: merchant).categoryID, T.id("subscriptions"), merchant)
        }
    }
    func testWiderKeywordTable() {
        XCTAssertEqual(key("Uber"), "transportation")
        XCTAssertEqual(key("Lyft *RIDE SUN 5PM"), "transportation")
        XCTAssertEqual(key("Ventra"), "transportation")
        XCTAssertEqual(key("CVS Pharmacy"), "health")
        XCTAssertEqual(key("Walgreens #4521"), "health")
        XCTAssertEqual(key("ComEd"), "bills")
        XCTAssertEqual(key("AT&T"), "bills")
        XCTAssertEqual(key("Xfinity"), "bills")
        XCTAssertEqual(key("AMC Theatres"), "recreation")
        XCTAssertEqual(key("Steam Games"), "recreation")
        XCTAssertEqual(key("Dunkin"), "food")
        XCTAssertEqual(key("Marathon"), "gas")
        XCTAssertEqual(key("Hulu"), "subscriptions")
    }
    func testWholeWordMatchingOnly() {
        XCTAssertNil(key("BPM Studio"))
        XCTAssertNil(key("Targeted Marketing LLC"))
        XCTAssertNil(key("Shellfish Shack Supply"))
        XCTAssertEqual(key("BP 9921"), "gas")
    }
    func testKeywordInTheMiddleOfTheName() { XCTAssertEqual(key("SQ *DOWNTOWN STARBUCKS KIOSK"), "food") }
    func testLongerKeywordWins() {
        XCTAssertEqual(key("Uber Eats"), "food")
        XCTAssertEqual(key("Uber"), "transportation")
        XCTAssertEqual(key("Amazon Prime"), "subscriptions")
        XCTAssertEqual(key("Costco Gas"), "gas")
        XCTAssertEqual(key("Costco"), "groceries")
    }
    func testBrandBeatsGenericWord() {
        // "Coffee" is a generic food word; "Shell" is a gas brand.
        XCTAssertEqual(key("Shell Coffee Corner"), "gas")
        XCTAssertEqual(key("Corner Coffee House"), "food")
    }
    func testUnknownMerchantFallsBackToOther() {
        let result = categorizer.categorize(merchant: "Zzyzx Holdings")
        XCTAssertEqual(result.categoryID, T.id("other"))
        XCTAssertEqual(result.reason, .fallback)
    }
    func testBlankMerchantFallsBackToOther() {
        XCTAssertEqual(categorizer.categorize(merchant: "  ").categoryID, T.id("other"))
    }
    func testReasonForKeyword() {
        let result = categorizer.categorize(merchant: "Trader Joe's #552")
        XCTAssertEqual(result.reason, .builtInKeyword)
        XCTAssertEqual(result.matchedKeyword, "TRADER JOES")
    }
    func testLearnedRuleBeatsKeyword() {
        let rules = [MerchantRule(normalizedMerchant: "TARGET", categoryID: T.id("groceries"))]
        let result = Categorizer(rules: rules).categorize(merchant: "Target 00012345")
        XCTAssertEqual(result.categoryID, T.id("groceries"))
        XCTAssertEqual(result.reason, .learnedRule)
    }
    func testLearnedRuleForUnknownMerchant() {
        let rules = [MerchantRule(normalizedMerchant: MerchantNormalizer.normalize("Joe's Barber Shop"), categoryID: T.id("health"))]
        XCTAssertEqual(Categorizer(rules: rules).categorize(merchant: "JOES BARBER SHOP #2").categoryID, T.id("health"))
    }
    func testLearnedRuleMatchesAsWordPrefix() {
        let rules = [MerchantRule(normalizedMerchant: "STARBUCKS", categoryID: T.id("recreation"))]
        let categorizer = Categorizer(rules: rules)
        XCTAssertEqual(categorizer.categorize(merchant: "Starbucks Chicago IL").categoryID, T.id("recreation"))
        // Not a whole-word prefix → the rule does not apply.
        XCTAssertEqual(categorizer.categorize(merchant: "Starbucksville Diner").categoryID, T.id("food"))
    }
    func testLongestLearnedRuleWins() {
        let rules = [
            MerchantRule(normalizedMerchant: "COSTCO", categoryID: T.id("groceries")),
            MerchantRule(normalizedMerchant: "COSTCO TRAVEL", categoryID: T.id("recreation"))
        ]
        XCTAssertEqual(Categorizer(rules: rules).categorize(merchant: "Costco Travel Booking").categoryID, T.id("recreation"))
    }
    func testRuleStoredUnnormalizedStillWorks() {
        let rules = [MerchantRule(normalizedMerchant: "Lou Malnati's", categoryID: T.id("recreation"))]
        XCTAssertEqual(Categorizer(rules: rules).categorize(merchant: "LOU MALNATIS 14").categoryID, T.id("recreation"))
    }
    func testRuleToArchivedCategoryIsSkipped() {
        var categories = T.categories
        let custom = CategoryRecord(name: "Pets", colorHex: "#123456", symbolName: "pawprint.fill", sortOrder: 10, isArchived: true)
        categories.append(custom)
        let rules = [MerchantRule(normalizedMerchant: "TARGET", categoryID: custom.id)]
        let result = Categorizer(rules: rules, categories: categories).categorize(merchant: "Target")
        XCTAssertEqual(result.categoryID, T.id("shopping"))
        XCTAssertEqual(result.reason, .builtInKeyword)
    }
    func testKeywordToArchivedCategoryFallsBackToOther() {
        var categories = T.categories
        let index = categories.firstIndex { $0.systemKey == "gas" }!
        categories[index].isArchived = true
        let result = Categorizer(categories: categories).categorize(merchant: "Shell")
        XCTAssertEqual(result.categoryID, T.id("other"))
        XCTAssertEqual(result.reason, .fallback)
    }
    func testRuleToDeletedCategoryIsSkipped() {
        let rules = [MerchantRule(normalizedMerchant: "SHELL", categoryID: UUID())]
        XCTAssertEqual(Categorizer(rules: rules).categorize(merchant: "Shell").categoryID, T.id("gas"))
    }
    func testCategoryHintUsedBeforeKeywordsButAfterRules() {
        let hinted = categorizer.categorize(merchant: "Target", categoryHint: "Groceries")
        XCTAssertEqual(hinted.categoryID, T.id("groceries"))
        XCTAssertEqual(hinted.reason, .categoryHint)
        let rules = [MerchantRule(normalizedMerchant: "TARGET", categoryID: T.id("health"))]
        XCTAssertEqual(Categorizer(rules: rules).categorize(merchant: "Target", categoryHint: "Groceries").categoryID, T.id("health"))
    }
    func testBankCategoryWords() {
        XCTAssertEqual(categorizer.categoryID(forName: "Restaurants"), T.id("food"))
        XCTAssertEqual(categorizer.categoryID(forName: "food & dining"), T.id("food"))
        XCTAssertNil(categorizer.categoryID(forName: "Wibble"))
    }
    func testCoffeeMerchants() {
        XCTAssertTrue(Categorizer.isCoffeeMerchant("Starbucks #1234"))
        XCTAssertTrue(Categorizer.isCoffeeMerchant("Colectivo Coffee"))
        XCTAssertFalse(Categorizer.isCoffeeMerchant("Chipotle"))
    }
    func testDefaultCategories() {
        let all = DefaultCategories.all
        XCTAssertEqual(all.map { $0.name }, [
            "Food & Dining", "Groceries", "Gas", "Shopping", "Recreation & Entertainment",
            "Bills & Utilities", "Transportation", "Health", "Subscriptions", "Other"
        ])
        XCTAssertEqual(Set(all.map { $0.id }).count, 10)
        XCTAssertEqual(Set(all.map { $0.colorHex }).count, 10)
        XCTAssertEqual(all.map { $0.sortOrder }, Array(0..<10))
        XCTAssertEqual(DefaultCategories.id("food").uuidString, "4C454447-4552-4C59-8000-000000000001")
        XCTAssertEqual(DefaultCategories.id("other").uuidString, "4C454447-4552-4C59-8000-00000000000A")
        XCTAssertEqual(DefaultCategories.id("nonsense"), DefaultCategories.otherID)
        for category in all {
            XCTAssertTrue(category.colorHex.hasPrefix("#") && category.colorHex.count == 7, category.name)
            XCTAssertEqual(DefaultCategories.id(category.systemKey!), category.id)
        }
    }
    func testDiscretionaryAndProtectedFlags() {
        func category(_ key: String) -> CategoryRecord { DefaultCategories.category(key)! }
        XCTAssertEqual(DefaultCategories.all.filter { $0.isDiscretionary }.compactMap { $0.systemKey }, ["food", "shopping", "recreation", "subscriptions"])
        XCTAssertEqual(DefaultCategories.all.filter { $0.isProtected }.compactMap { $0.systemKey }, ["bills", "health"])
        XCTAssertFalse(category("groceries").isDiscretionary)
        let custom = CategoryRecord(name: "Pets", colorHex: "#123456", symbolName: "pawprint.fill", sortOrder: 10)
        XCTAssertTrue(custom.isDiscretionary)
        XCTAssertFalse(custom.isProtected)
    }
    func testEveryBuiltInKeywordPointsAtAKnownCategory() {
        XCTAssertGreaterThan(Categorizer.builtInKeywords.count, 300)
        for rule in Categorizer.builtInKeywords {
            XCTAssertTrue(DefaultCategories.systemKeys.contains(rule.systemKey), rule.keyword)
            XCTAssertFalse(rule.tokens.isEmpty)
        }
    }
}
