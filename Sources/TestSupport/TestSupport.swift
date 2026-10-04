import Foundation

// Lightweight executable-test assertions for Command Line Tools installations without XCTest.
// These familiar names do not provide XCTest discovery or reporting. A failed assertion stops
// the executable immediately, including optimized builds, with the source file and line.

public func XCTFail(_ message: @autoclosure () -> String = "Test failed", file: StaticString = #filePath, line: UInt = #line) -> Never {
    fatalError(message(), file: (file), line: line)
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    guard evaluate(expression, file: file, line: line) else { XCTFail(message(), file: file, line: line) }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    guard !evaluate(expression, file: file, line: line) else { XCTFail(message(), file: file, line: line) }
}

public func XCTAssertEqual<T: Equatable>(_ expression: @autoclosure () throws -> T, _ expectedExpression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let actual = evaluate(expression, file: file, line: line)
    let expected = evaluate(expectedExpression, file: file, line: line)
    guard actual == expected else { XCTFail("Expected \(expected), got \(actual). \(message())", file: file, line: line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ expression: @autoclosure () throws -> T, _ unexpectedExpression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let actual = evaluate(expression, file: file, line: line)
    let unexpected = evaluate(unexpectedExpression, file: file, line: line)
    guard actual != unexpected else { XCTFail("Unexpected equal values: \(actual). \(message())", file: file, line: line) }
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ expression: @autoclosure () throws -> T, _ expectedExpression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let actual = evaluate(expression, file: file, line: line)
    let expected = evaluate(expectedExpression, file: file, line: line)
    guard actual <= expected else { XCTFail("Expected at most \(expected), got \(actual). \(message())", file: file, line: line) }
}

public func XCTAssertNil<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "Expected nil", file: StaticString = #filePath, line: UInt = #line) {
    guard evaluate(expression, file: file, line: line) == nil else { XCTFail(message(), file: file, line: line) }
}

public func XCTAssertNotNil<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "Expected a value", file: StaticString = #filePath, line: UInt = #line) {
    guard evaluate(expression, file: file, line: line) != nil else { XCTFail(message(), file: file, line: line) }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "Expected an error", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (any Error) -> Void = { _ in }) {
    do { _ = try expression() }
    catch { errorHandler(error); return }
    XCTFail(message(), file: file, line: line)
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() }
    catch { XCTFail("Unexpected error: \(error). \(message())", file: file, line: line) }
}

public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "Expected a value", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value = evaluate(expression, file: file, line: line) else { XCTFail(message(), file: file, line: line) }
    return value
}

private func evaluate<T>(_ expression: () throws -> T, file: StaticString, line: UInt) -> T {
    do { return try expression() }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
