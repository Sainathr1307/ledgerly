import Foundation
import XCTest
@testable import LedgerlyCore

final class AmountParserTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")
    private let fr = Locale(identifier: "fr_FR")

    private func parse(_ text: String, _ locale: Locale? = nil) -> Decimal? {
        AmountParser.parse(text, locale: locale ?? us)
    }

    func testPlainDecimal() { XCTAssertEqual(parse("12.40"), T.d("12.40")) }
    func testWholeNumber() { XCTAssertEqual(parse("7"), T.d("7")) }
    func testDollarSignWithThousands() { XCTAssertEqual(parse("$1,234.56"), T.d("1234.56")) }
    func testDollarSignWithSpace() { XCTAssertEqual(parse("$ 12.40"), T.d("12.40")) }
    func testZero() { XCTAssertEqual(parse("0"), T.d("0")) }
    func testZeroWithDecimals() { XCTAssertEqual(parse("$0.00"), T.d("0")) }
    func testNegativeZeroIsZero() { XCTAssertEqual(parse("-0.00"), T.d("0")) }

    func testEmptyIsNil() { XCTAssertNil(parse("")) }
    func testWhitespaceIsNil() { XCTAssertNil(parse("   \n\t ")) }
    func testGarbageIsNil() { XCTAssertNil(parse("abc")) }
    func testCurrencySymbolAloneIsNil() { XCTAssertNil(parse("$")) }
    func testTwoNumbersIsNil() { XCTAssertNil(parse("12.40 and 13")) }
    func testScientificNotationIsNil() { XCTAssertNil(parse("1e5")) }

    func testGermanFormat() { XCTAssertEqual(parse("1.234,56", de), T.d("1234.56")) }
    func testGermanFormatParsedUnderUSLocaleStillUsesLastSeparator() { XCTAssertEqual(parse("1.234,56", us), T.d("1234.56")) }
    func testUSFormatParsedUnderGermanLocaleStillUsesLastSeparator() { XCTAssertEqual(parse("1,234.56", de), T.d("1234.56")) }
    func testFrenchDecimalComma() { XCTAssertEqual(parse("12,40", fr), T.d("12.40")) }
    func testDecimalCommaEvenInUSLocale() { XCTAssertEqual(parse("12,40", us), T.d("12.40")) }
    func testSpaceGrouping() { XCTAssertEqual(parse("1 234,56", fr), T.d("1234.56")) }
    func testNoBreakSpaceGrouping() { XCTAssertEqual(parse("1\u{00A0}234,56 €", fr), T.d("1234.56")) }
    func testNarrowNoBreakSpaceGrouping() { XCTAssertEqual(parse("1\u{202F}234,56\u{00A0}€", fr), T.d("1234.56")) }
    func testSwissApostropheGrouping() { XCTAssertEqual(parse("CHF 1'234.50"), T.d("1234.50")) }
    func testBadSpaceGroupingIsNil() { XCTAssertNil(parse("12 40")) }

    func testEuroPrefix() { XCTAssertEqual(parse("€12.40"), T.d("12.40")) }
    func testEuroSuffix() { XCTAssertEqual(parse("12,40 €", de), T.d("12.40")) }
    func testCurrencyCodePrefix() { XCTAssertEqual(parse("USD 12.40"), T.d("12.40")) }
    func testCurrencyCodeSuffix() { XCTAssertEqual(parse("12.40 USD"), T.d("12.40")) }
    func testPrefixedDollar() { XCTAssertEqual(parse("US$12.40"), T.d("12.40")) }
    func testPoundAndYen() {
        XCTAssertEqual(parse("£3.50"), T.d("3.50"))
        XCTAssertEqual(parse("¥1,200"), T.d("1200"))
    }

    func testParenthesesAreNegative() { XCTAssertEqual(parse("(5.00)"), T.d("-5.00")) }
    func testParenthesesWithSymbol() { XCTAssertEqual(parse("($1,005.25)"), T.d("-1005.25")) }
    func testLeadingMinus() { XCTAssertEqual(parse("-5.00"), T.d("-5.00")) }
    func testMinusBeforeSymbol() { XCTAssertEqual(parse("-$5.00"), T.d("-5.00")) }
    func testMinusAfterSymbol() { XCTAssertEqual(parse("$-5.00"), T.d("-5.00")) }
    func testTrailingMinus() { XCTAssertEqual(parse("5.00-"), T.d("-5.00")) }
    func testUnicodeMinus() { XCTAssertEqual(parse("\u{2212}3"), T.d("-3")) }
    func testNegativeInteger() { XCTAssertEqual(parse("-3"), T.d("-3")) }
    func testPlusSignIgnored() { XCTAssertEqual(parse("+8.25"), T.d("8.25")) }

    func testAmbiguousThreeDigitsFollowsUSLocale() {
        XCTAssertEqual(parse("1,234", us), T.d("1234"))
        XCTAssertEqual(parse("1.234", us), T.d("1.234"))
    }
    func testAmbiguousThreeDigitsFollowsGermanLocale() {
        XCTAssertEqual(parse("1.234", de), T.d("1234"))
        XCTAssertEqual(parse("1,234", de), T.d("1.234"))
    }
    func testThreeDecimalsAfterZeroIsAlwaysDecimal() {
        XCTAssertEqual(parse("0,125", us), T.d("0.125"))
        XCTAssertEqual(parse("0.125", de), T.d("0.125"))
    }
    func testLongIntegerPartCannotBeGrouping() { XCTAssertEqual(parse("1234,567", us), T.d("1234.567")) }
    func testRepeatedSeparatorIsGrouping() {
        XCTAssertEqual(parse("1,234,567", us), T.d("1234567"))
        XCTAssertEqual(parse("1.234.567", de), T.d("1234567"))
    }
    func testIndianGrouping() { XCTAssertEqual(parse("₹1,23,456.78"), T.d("123456.78")) }
    func testDecimalSeparatorTwiceIsNil() { XCTAssertNil(parse("1,234.56.78")) }
    func testLeadingDecimalPoint() { XCTAssertEqual(parse(".50"), T.d("0.50")) }
    func testTrailingDecimalPoint() { XCTAssertEqual(parse("12."), T.d("12")) }
    func testAbbreviationDotIsNotDecimalPoint() { XCTAssertEqual(parse("Rs.500"), T.d("500")) }
    func testOneDecimalDigit() { XCTAssertEqual(parse("12.4"), T.d("12.4")) }
    func testSurroundingWhitespace() { XCTAssertEqual(parse("  $12.40\n"), T.d("12.40")) }

    func testArabicIndicDigits() { XCTAssertEqual(parse("١٢٫٤٠"), T.d("12.40")) }
    func testEasternArabicDigitsWithThousands() { XCTAssertEqual(parse("۱٬۲۳۴٫۵۶"), T.d("1234.56")) }
    func testFullWidthDigits() { XCTAssertEqual(parse("￥１２００"), T.d("1200")) }

    func testVeryLargeAmount() { XCTAssertEqual(parse("$99,999,999,999.99"), T.d("99999999999.99")) }
    func testTooManyDigitsIsNil() { XCTAssertNil(parse(String(repeating: "9", count: 40))) }
    func testResultIsExactNotBinaryFloat() {
        // 0.1 + 0.2 must be exactly 0.3 in Decimal.
        XCTAssertEqual(parse("0.1")! + parse("0.2")!, T.d("0.3"))
    }
}
