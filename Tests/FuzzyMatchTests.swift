import XCTest

@testable import ZappaleCore
@testable import zappale

final class FuzzyMatchTests: XCTestCase {
    func testEmptyQueryReturnsZero() {
        XCTAssertEqual(FuzzyMatch.score(query: "", target: "Safari"), 0)
    }

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(FuzzyMatch.score(query: "xyz", target: "Safari"))
        XCTAssertNil(FuzzyMatch.score(query: "safarix", target: "Safari"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.score(query: "SAF", target: "safari"))
        XCTAssertEqual(
            FuzzyMatch.score(query: "saf", target: "Safari"),
            FuzzyMatch.score(query: "SAF", target: "safari")
        )
    }

    func testPrefixBeatsMiddleOccurrence() {
        let prefix = FuzzyMatch.score(query: "saf", target: "Safari")!
        let middle = FuzzyMatch.score(query: "saf", target: "InsomniacSafari")!
        XCTAssertGreaterThan(prefix, middle)
    }

    func testContiguousBeatsScattered() {
        let contiguous = FuzzyMatch.score(query: "sf", target: "Sfumato")!
        let scattered = FuzzyMatch.score(query: "sf", target: "Sofa")!
        XCTAssertGreaterThan(contiguous, scattered)
    }

    func testWordBoundaryBeatsMidWord() {
        let boundary = FuzzyMatch.score(query: "fc", target: "FileConverter")!
        let midWord = FuzzyMatch.score(query: "fc", target: "AfcBook")!
        XCTAssertGreaterThan(boundary, midWord)
    }

    func testChineseCharacters() {
        let score = FuzzyMatch.score(query: "访", target: "访达")
        XCTAssertNotNil(score)
        let exact = FuzzyMatch.score(query: "访达", target: "访达")!
        XCTAssertGreaterThan(exact, score!)
    }

    func testScoreIsDeterministic() {
        let a = FuzzyMatch.score(query: "term", target: "Terminal")
        let b = FuzzyMatch.score(query: "term", target: "Terminal")
        XCTAssertEqual(a, b)
    }
}
