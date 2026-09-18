import XCTest

@testable import ZappaleCore
@testable import zappale

final class AIEndpointPolicyTests: XCTestCase {
    func testHTTPSAllowed() {
        XCTAssertTrue(AIEndpointPolicy.validate(URL(string: "https://api.deepseek.com/v1")!))
        XCTAssertTrue(AIEndpointPolicy.validate(URL(string: "HTTPS://api.openai.com/v1")!))
    }

    func testHTTPLoopbackAllowed() {
        XCTAssertTrue(AIEndpointPolicy.validate(URL(string: "http://localhost:11434/v1")!))
        XCTAssertTrue(AIEndpointPolicy.validate(URL(string: "http://127.0.0.1:8080/v1")!))
        XCTAssertTrue(AIEndpointPolicy.validate(URL(string: "http://[::1]:11434/v1")!))
    }

    func testHTTPRemoteRejected() {
        XCTAssertFalse(AIEndpointPolicy.validate(URL(string: "http://api.deepseek.com/v1")!))
        XCTAssertFalse(AIEndpointPolicy.validate(URL(string: "http://example.com/v1")!))
    }

    func testNonHTTPSchemeRejectedEvenOnLoopback() {
        XCTAssertFalse(AIEndpointPolicy.validate(URL(string: "ftp://localhost/models")!))
        XCTAssertFalse(AIEndpointPolicy.validate(URL(string: "file:///etc/passwd")!))
    }

    func testMissingHostRejected() {
        XCTAssertFalse(AIEndpointPolicy.validate(URL(string: "https:///v1")!))
    }

    func testTextValidationTrimsWhitespace() {
        XCTAssertTrue(AIEndpointPolicy.validate("  https://api.deepseek.com/v1  "))
        XCTAssertFalse(AIEndpointPolicy.validate("http://api.deepseek.com/v1"))
    }
}
