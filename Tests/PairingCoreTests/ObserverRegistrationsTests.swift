import XCTest
import ApplicationServices
@testable import PairingCore

final class ObserverRegistrationsTests: XCTestCase {
    func testLaunchIPCFailureIsRetriedWithoutReregisteringSuccessfulListeners() {
        var state = ObserverRegistrations(names: ["window", "focus"])
        state.retry { $0 == "window" ? .success : .cannotComplete }
        XCTAssertEqual(state.registered, 1)
        XCTAssertEqual(state.unsupported, 0)
        XCTAssertEqual(state.pending, 1)
        XCTAssertEqual(state.failures, ["focus": AXError.cannotComplete.rawValue])
        var retried: [String] = []
        state.retry { retried.append($0); return .success }
        XCTAssertEqual(retried, ["focus"])
        XCTAssertEqual(state.registered, 2)
        XCTAssertEqual(state.pending, 0)
        XCTAssertTrue(state.failures.isEmpty)
        state.retry { _ in XCTFail("Ready listeners must not be registered again"); return .failure }
    }

    func testUnsupportedAndAlreadyRegisteredAreSettledButPermissionFailureIsNot() {
        var state = ObserverRegistrations(names: ["unsupported", "existing", "permission"])
        state.retry { name in
            switch name {
            case "unsupported": return .notificationUnsupported
            case "existing": return .notificationAlreadyRegistered
            default: return .apiDisabled
            }
        }
        XCTAssertEqual(state.registered, 1)
        XCTAssertEqual(state.unsupported, 1)
        XCTAssertEqual(state.pending, 1)
        state.retry { name in
            XCTAssertEqual(name, "permission")
            return .success
        }
        XCTAssertEqual(state.pending, 0)
    }

    func testNewProcessDoesNotInheritPreviousProcessRegistrations() {
        var old = ObserverRegistrations(names: ["window", "focus"])
        old.retry { _ in .success }
        var replacement = ObserverRegistrations(names: ["window", "focus"])
        XCTAssertEqual(replacement.registered, 0)
        XCTAssertEqual(replacement.pending, 2)
        var calls = 0
        replacement.retry { _ in calls += 1; return .success }
        XCTAssertEqual(calls, 2)
    }
}
