//
//  CWCSVParserTests.swift
//  CWCSVParserTests
//
//  Created by Carl Wieland on 11/22/17.
//  Copyright © 2017 Datum Apps. All rights reserved.
//

import XCTest
@testable import CWCSVParser

fileprivate let EMPTY = ""
fileprivate let COMMA = ","
fileprivate let SEMICOLON = ";"
fileprivate let DOUBLEQUOTE = "\""
fileprivate let NEWLINE = "\n"
fileprivate let TAB = "\t"
fileprivate let SPACE = " "
fileprivate let BACKSLASH = "\\"
fileprivate let OCTOTHORPE = "#"
fileprivate let EQUAL = "="

fileprivate let FIELD1 = "field1"
fileprivate let FIELD2 = "field2"
fileprivate let FIELD3 = "field3"
fileprivate let UTF8FIELD4 = "ḟīễłđ➃"

fileprivate let QUOTED_FIELD1 = "\(DOUBLEQUOTE)\(FIELD1)\(DOUBLEQUOTE)"
fileprivate let QUOTED_FIELD2 = "\(DOUBLEQUOTE)\(FIELD2)\(DOUBLEQUOTE)"
fileprivate let QUOTED_FIELD3 = "\(DOUBLEQUOTE)\(FIELD3)\(DOUBLEQUOTE)"

fileprivate let MULTILINE_FIELD = "\(FIELD1)\(NEWLINE)\(FIELD2)"

class CWCSVParserTests: XCTestCase {

    private func TEST_ARRAYS(_ actual: [Any], _ expected: [Any])  {

        XCTAssertEqual(actual.count, expected.count, "incorrect number of records")

        if actual.count == expected.count {
            for record in 0..<actual.count {
                guard let actualRow = actual[record] as? [Any],
                    let expectedRow = expected[record] as? [Any] else {
                        XCTAssertFalse(true, "Invalid objects in expected")
                        continue
                }
                XCTAssertEqual(actualRow.count, expectedRow.count, "incorrect number of fields on line \(record + 1)")
                if actualRow.count == expectedRow.count {
                    for field in 0..<actualRow.count {
                        let actualField = actualRow[field]
                        let expectedField = expectedRow[field]
                        XCTAssertEqual(actualField as? NSObject, expectedField as? NSObject,"mismatched field \(field) on line \(record + 1)")

                        if  actualField as? NSObject != nil, actualField as? NSObject != expectedField as? NSObject {
                            print("expected:\(expectedField) got: \(actualField)")
                        }
                    }
                }
            }
        }
    }

    private func TEST(_ str: String, _ expected: [Any], _ options: CSVParserOptions = []) {
        let parsed = str.CSVComponents(with: options)
        TEST_ARRAYS(parsed, expected)

    }


    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testSimple() {
        let csv = "\(FIELD1)\(COMMA)\(FIELD2)\(COMMA)\(FIELD3)"
        let expected = [[FIELD1, FIELD2, FIELD3]]
        TEST(csv, expected)
    }

    func testSimpleUTF8() {
        let csv = "\(FIELD1)\(COMMA)\(FIELD2)\(COMMA)\(FIELD3)\(COMMA)\(UTF8FIELD4)\(NEWLINE)\(FIELD1)\(COMMA)\(FIELD2)\(COMMA)\(FIELD3)\(COMMA)\(UTF8FIELD4)"
        let expected = [[FIELD1, FIELD2, FIELD3, UTF8FIELD4], [FIELD1, FIELD2, FIELD3, UTF8FIELD4]]
        TEST(csv, expected)
    }

    func testSanitizedLeadingEqual() {
        let csv = FIELD1 + COMMA + EQUAL + QUOTED_FIELD2 + COMMA + EQUAL + QUOTED_FIELD3
        let expected = [[FIELD1, FIELD2, FIELD3]]

        TEST(csv, expected, [.recognizesLeadingEqualSign , .sanitizesFields])
    }

    func testLeadingEqual() {
        let csv = FIELD1 + COMMA + EQUAL + QUOTED_FIELD2 + COMMA + EQUAL + QUOTED_FIELD3
        let expected = [[FIELD1, EQUAL + QUOTED_FIELD2, EQUAL + QUOTED_FIELD3]]

        TEST(csv, expected, [.recognizesLeadingEqualSign])
    }

    func testEmoji() {
        let csv = "1️⃣,2️⃣,3️⃣,4️⃣,5️⃣" + NEWLINE + "6️⃣,7️⃣,8️⃣,9️⃣,0️⃣"
        let expected = [["1️⃣","2️⃣","3️⃣","4️⃣","5️⃣"],["6️⃣","7️⃣","8️⃣","9️⃣","0️⃣"]]
        TEST(csv, expected)
    }

    func testTrailingTrimmedSpace() {
        let csv = FIELD1 + COMMA + FIELD2 + NEWLINE + SPACE
        let expected = [[FIELD1, FIELD2], [EMPTY]]
        TEST(csv, expected, .trimsWhitespace)
    }

    func testTrailingSpace() {
        let csv = FIELD1 + COMMA + FIELD2 + NEWLINE + SPACE
        let expected = [[FIELD1, FIELD2], [SPACE]]
        TEST(csv, expected)
    }

    func testTrailingNewline() {
        let csv = FIELD1 + COMMA + FIELD2 + NEWLINE
        let expected = [[FIELD1, FIELD2]]
        TEST(csv, expected)
    }

    func testRecognizedComment() {
        let csv = FIELD1 + NEWLINE + OCTOTHORPE + FIELD2
        let expected = [[FIELD1]]
        TEST(csv, expected, .recognizesComments)
    }


    func testEmptyFields() {
        let csv = COMMA + COMMA
        let expected = [[EMPTY, EMPTY, EMPTY]]
        TEST(csv, expected)
    }

    func testSimpleWithInnerQuote() {
        let csv = FIELD1 + COMMA + FIELD2 + DOUBLEQUOTE + FIELD3
        let expected = [[FIELD1, FIELD2 + DOUBLEQUOTE + FIELD3]]
        TEST(csv, expected)
    }

    func testSimpleWithDoubledInnerQuote() {
        let csv = FIELD1 + COMMA + FIELD2 + DOUBLEQUOTE + DOUBLEQUOTE + FIELD3
        let expected = [[FIELD1, FIELD2 + DOUBLEQUOTE + DOUBLEQUOTE + FIELD3]]
        TEST(csv, expected)
    }

    func testInterspersedDoubleQuotes() {
    let csv = FIELD1 + COMMA + FIELD2 + DOUBLEQUOTE + FIELD3 + DOUBLEQUOTE
    let expected = [[FIELD1, FIELD2 + DOUBLEQUOTE + FIELD3 + DOUBLEQUOTE]]
    TEST(csv, expected)
    }

    func testSimpleQuoted() {
    let csv = QUOTED_FIELD1 + COMMA + QUOTED_FIELD2 + COMMA + QUOTED_FIELD3
    let expected = [[QUOTED_FIELD1, QUOTED_FIELD2, QUOTED_FIELD3]]
    TEST(csv, expected)
    }

    func testSimpleQuotedSanitized() {
    let csv = QUOTED_FIELD1 + COMMA + QUOTED_FIELD2 + COMMA + QUOTED_FIELD3
    let expected = [[FIELD1, FIELD2, FIELD3]]
    TEST(csv, expected, .sanitizesFields)
    }

    func testSimpleMultiline() {
        let csv = FIELD1 + COMMA + FIELD2 + COMMA + FIELD3 + NEWLINE + FIELD1 + COMMA + FIELD2 + COMMA + FIELD3
        let expected = [[FIELD1, FIELD2, FIELD3], [FIELD1, FIELD2, FIELD3]]
        TEST(csv, expected)
    }

    func testQuotedDelimiter() {
    let csv = FIELD1 + COMMA + DOUBLEQUOTE + FIELD2 + COMMA + FIELD3 + DOUBLEQUOTE
    let expected = [[FIELD1, DOUBLEQUOTE + FIELD2 + COMMA + FIELD3 + DOUBLEQUOTE]]
    TEST(csv, expected)
    }

    func testSanitizedQuotedDelimiter() {
        let csv = FIELD1 + COMMA + DOUBLEQUOTE + FIELD2 + COMMA + FIELD3 + DOUBLEQUOTE
        let expected = [[FIELD1, FIELD2 + COMMA + FIELD3]]
        TEST(csv, expected, .sanitizesFields)
    }

    func testQuotedMultiline() {
        let csv = FIELD1 + COMMA + DOUBLEQUOTE + MULTILINE_FIELD + DOUBLEQUOTE + NEWLINE + FIELD2
        let expected = [[FIELD1, DOUBLEQUOTE + MULTILINE_FIELD + DOUBLEQUOTE], [FIELD2]]
        TEST(csv, expected)
    }

    func testSanitizedMultiline() {
        let csv = FIELD1 + COMMA + DOUBLEQUOTE + MULTILINE_FIELD + DOUBLEQUOTE + NEWLINE + FIELD2
        let expected = [[FIELD1, MULTILINE_FIELD], [FIELD2]]
        TEST(csv, expected, .sanitizesFields)
    }

    func testWhitespace() {
        let csv = FIELD1 + COMMA + SPACE + SPACE + SPACE + FIELD2 + COMMA + FIELD3 + SPACE + SPACE + SPACE
        let expected = [[FIELD1, SPACE + SPACE + SPACE + FIELD2, FIELD3 + SPACE + SPACE + SPACE]]
        TEST(csv, expected)
    }

    func testTrimmedWhitespace() {
        let csv = FIELD1 + COMMA + SPACE + SPACE + SPACE + FIELD2 + COMMA + FIELD3 + SPACE + SPACE + SPACE
        let expected = [[FIELD1, FIELD2, FIELD3]]
        TEST(csv, expected, .trimsWhitespace)
    }

    func testSanitizedQuotedWhitespace() {
        let csv = FIELD1 + COMMA + DOUBLEQUOTE + SPACE + SPACE + SPACE + FIELD2 + DOUBLEQUOTE + COMMA + DOUBLEQUOTE + FIELD3 + SPACE + SPACE + SPACE + DOUBLEQUOTE
        let expected = [[FIELD1, SPACE + SPACE + SPACE + FIELD2, FIELD3 + SPACE + SPACE + SPACE]]
        TEST(csv, expected, .sanitizesFields)
    }

    func testUnrecognizedComment() {
        let csv = FIELD1 + NEWLINE + OCTOTHORPE + FIELD2
        let expected = [[FIELD1], [OCTOTHORPE + FIELD2]]
        TEST(csv, expected)
    }


}
