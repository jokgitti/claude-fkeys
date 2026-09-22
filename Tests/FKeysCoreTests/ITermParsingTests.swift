import Testing
@testable import FKeysCore

private let sample = """
BFCB9F58-8EFE-432D-8DAB-07FD5388D158\tchat (claude)\tchat (claude)\t364x93\t\\/dev\\/ttys000
6D50EE3D-2C78-4AB2-8AA3-9282A5B0E43D\t✳ Companion AI harness investigation (claude)\t✳ Companion AI harness investigation (claude)\t364x93\t\\/dev\\/ttys005
3583E997-62AE-4FBE-8522-3BE2C0913374\t◑ FLOWS-1162 (claude)\t◑ FLOWS-1162 (claude)\t364x90\t\\/dev\\/ttys008
"""

@Test func extractsUUIDsFromRealOutput() {
    #expect(ITermParsing.sessionUUIDs(from: sample) == [
        "BFCB9F58-8EFE-432D-8DAB-07FD5388D158",
        "6D50EE3D-2C78-4AB2-8AA3-9282A5B0E43D",
        "3583E997-62AE-4FBE-8522-3BE2C0913374",
    ])
}

@Test func ignoresLinesWhoseFirstFieldIsNotAUUID() {
    let output = """
    No sessions found.
    BFCB9F58-8EFE-432D-8DAB-07FD5388D158\tchat\tchat\t80x24\t/dev/ttys000
    """
    #expect(ITermParsing.sessionUUIDs(from: output) == ["BFCB9F58-8EFE-432D-8DAB-07FD5388D158"])
}

@Test func handlesEmptyAndBlankOutput() {
    #expect(ITermParsing.sessionUUIDs(from: "").isEmpty)
    #expect(ITermParsing.sessionUUIDs(from: "\n\n  \n").isEmpty)
}

@Test func toleratesTrailingWhitespaceAndCRLF() {
    let output = "BFCB9F58-8EFE-432D-8DAB-07FD5388D158\tchat\r\n"
    #expect(ITermParsing.sessionUUIDs(from: output) == ["BFCB9F58-8EFE-432D-8DAB-07FD5388D158"])
}
