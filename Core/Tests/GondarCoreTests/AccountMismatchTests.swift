import Testing

@testable import GondarCore

/// A switch half done is waited out twice; the third disagreement in a row is reported.
@Test func reportsTheThirdDisagreementInARow() {
    var mismatch = AccountMismatch()
    let reported = (0..<4).map { _ in mismatch.disagreed() }
    #expect(reported == [false, false, true, true])
}

@Test func agreementResetsTheCount() {
    var mismatch = AccountMismatch()
    _ = mismatch.disagreed()
    _ = mismatch.disagreed()
    mismatch.agreed()
    let reported = (0..<3).map { _ in mismatch.disagreed() }
    #expect(reported == [false, false, true])
}
