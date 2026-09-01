import XCTest
@testable import OllamaBar

final class BudgetPolicyTests: XCTestCase {

    private let exceededHard = BudgetSnapshot(dailyBudgetTokens: 100, todayTotalTokens: 100, budgetMode: .hard)
    private let exceededSoft = BudgetSnapshot(dailyBudgetTokens: 100, todayTotalTokens: 150, budgetMode: .soft)
    private let underHard = BudgetSnapshot(dailyBudgetTokens: 100, todayTotalTokens: 99, budgetMode: .hard)
    private let disabled = BudgetSnapshot(dailyBudgetTokens: 0, todayTotalTokens: 5000, budgetMode: .hard)

    func test_blocksGenerationWhenHardBudgetExceeded() {
        XCTAssertTrue(BudgetPolicy.shouldBlock(exceededHard, method: "POST", path: "/api/generate"))
        XCTAssertTrue(BudgetPolicy.shouldBlock(exceededHard, method: "POST", path: "/api/chat"))
        XCTAssertTrue(BudgetPolicy.shouldBlock(exceededHard, method: "post", path: "/v1/chat/completions"))
        XCTAssertTrue(BudgetPolicy.shouldBlock(exceededHard, method: "POST", path: "/api/embed?foo=bar"))
    }

    func test_neverBlocksManagementEndpoints() {
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededHard, method: "GET", path: "/api/tags"))
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededHard, method: "GET", path: "/api/ps"))
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededHard, method: "POST", path: "/api/pull"))
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededHard, method: "POST", path: "/api/show"))
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededHard, method: "DELETE", path: "/api/delete"))
    }

    func test_softBudgetNeverBlocks() {
        XCTAssertFalse(BudgetPolicy.shouldBlock(exceededSoft, method: "POST", path: "/api/generate"))
    }

    func test_underBudgetOrDisabledNeverBlocks() {
        XCTAssertFalse(BudgetPolicy.shouldBlock(underHard, method: "POST", path: "/api/generate"))
        XCTAssertFalse(BudgetPolicy.shouldBlock(disabled, method: "POST", path: "/api/generate"))
    }

    func test_snapshotIsExceeded() {
        XCTAssertTrue(exceededHard.isExceeded)
        XCTAssertFalse(underHard.isExceeded)
        XCTAssertFalse(disabled.isExceeded)
    }
}
