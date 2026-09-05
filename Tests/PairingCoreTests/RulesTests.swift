import XCTest
@testable import PairingCore

final class RulesTests: XCTestCase {
    func testPinKeepsLeadingZeroAndAllowsNativeSpacing() {
        for input in ["012 345", "012\u{00a0}345", "0 1 2   3 4 5", "\n012\u{202f}345\n"] {
            XCTAssertEqual(PairingRules.pin(from: input), "012345")
        }
    }
    func testRejectsAmbiguousOrNonASCIICodes() {
        for input in ["12345", "1234567", "code 123456", "123-456", "１２３４５６", "123456 654321", "12\u{200b}3456"] {
            XCTAssertNil(PairingRules.pin(from:input))
        }
    }
    func testRequiresExactExtensionOriginAndPath() {
        let origin = "chrome-extension://\(PairingRules.extensionID)"
        XCTAssertTrue(PairingRules.isPopupURL(origin + "/page_popup.html?popupWindow=1"))
        for url in ["https://\(PairingRules.extensionID)/page_popup.html", origin + ".evil/page_popup.html",
                    origin + "/other.html", "chrome-extension://attacker/page_popup.html", origin + "/page_popup.html/", origin + ":80/page_popup.html"] {
            XCTAssertFalse(PairingRules.isPopupURL(url))
        }
    }
    func testStopsOnUnexpectedManualInputOrWrongProgress() {
        XCTAssertTrue(PairingRules.isExpectedProgress(values:["0","1","","","",""],pin:"012345",entered:2))
        XCTAssertFalse(PairingRules.isExpectedProgress(values:["0","1","9","","",""],pin:"012345",entered:2))
        XCTAssertFalse(PairingRules.isExpectedProgress(values:["0","","","","",""],pin:"012345",entered:2))
    }
}
