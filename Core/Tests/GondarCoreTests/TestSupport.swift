import Testing
import Foundation

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

func iso(_ string: String) throws -> Date {
    try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string)
}
