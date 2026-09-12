import XCTest
@testable import larping

final class EventNamerTests: XCTestCase {
    func testBaseNameWhenNothingExists() {
        XCTAssertEqual(EventNamer.nextName(base: "Larping Run", existing: []), "Larping Run")
    }

    func testBumpsToFirstNumberWhenBaseExists() {
        XCTAssertEqual(EventNamer.nextName(base: "Larping Run", existing: ["Larping Run"]), "Larping Run 1")
    }

    func testIncrementsPastExistingNumbers() {
        let existing = ["Larping Run", "Larping Run 1", "Larping Run 2"]
        XCTAssertEqual(EventNamer.nextName(base: "Larping Run", existing: existing), "Larping Run 3")
    }

    func testIgnoresUnrelatedNames() {
        XCTAssertEqual(EventNamer.nextName(base: "Larping Bike", existing: ["Larping Run 4"]), "Larping Bike")
    }

    func testIgnoresNonNumericSuffixes() {
        XCTAssertEqual(EventNamer.nextName(base: "Larping Run", existing: ["Larping Run Marathon"]), "Larping Run")
    }

    func testStaysBaseWhenSuffixHolesExist() {
        XCTAssertEqual(EventNamer.nextName(base: "Larping Run", existing: ["Larping Run 5"]), "Larping Run 6")
    }
}