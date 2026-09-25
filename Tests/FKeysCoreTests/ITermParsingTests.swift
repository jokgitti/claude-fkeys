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

// Real captured output from `it2 tab list --json`. Key order deliberately
// differs between the two objects — the parser must not depend on it.
private let tabListSample = """
[
  {
    "sessions" : 1,
    "index" : 0,
    "id" : "1",
    "is_active" : false,
    "window_id" : "pty-89CA3495-C90F-439D-9652-759281746556"
  },
  {
    "is_active" : true,
    "id" : "2",
    "sessions" : 1,
    "window_id" : "pty-89CA3495-C90F-439D-9652-759281746556",
    "index" : 1
  }
]
"""

@Test func parsesTabListJSONRegardlessOfKeyOrder() {
    #expect(ITermParsing.tabs(from: tabListSample) == [
        TabInfo(index: 0, id: "1", windowID: "pty-89CA3495-C90F-439D-9652-759281746556", isActive: false, sessionCount: 1),
        TabInfo(index: 1, id: "2", windowID: "pty-89CA3495-C90F-439D-9652-759281746556", isActive: true, sessionCount: 1),
    ])
}

@Test func tabsReturnsEmptyForAnEmptyArray() {
    #expect(ITermParsing.tabs(from: "[]") == [])
}

@Test func tabsReturnsNilForMalformedJSON() {
    #expect(ITermParsing.tabs(from: "not json") == nil)
    #expect(ITermParsing.tabs(from: "") == nil)
}

// Real captured output from `it2 window list --json` on this machine.
private let windowListSample = """
[
  {
    "width" : 2560,
    "x" : 0,
    "tabs" : 2,
    "id" : "pty-89CA3495-C90F-439D-9652-759281746556",
    "y" : 0,
    "height" : 1404,
    "is_fullscreen" : true
  }
]
"""

@Test func parsesFirstWindowIDFromWindowList() {
    #expect(ITermParsing.firstWindowID(from: windowListSample) == "pty-89CA3495-C90F-439D-9652-759281746556")
}

@Test func firstWindowIDReturnsNilForAnEmptyArray() {
    #expect(ITermParsing.firstWindowID(from: "[]") == nil)
}

@Test func firstWindowIDReturnsNilForMalformedJSON() {
    #expect(ITermParsing.firstWindowID(from: "not json") == nil)
    #expect(ITermParsing.firstWindowID(from: "") == nil)
}

// Real captured output from `it2 session get-var tab.id -s <uuid>`: a
// quoted string, e.g. `"2"`.
@Test func parsesAQuotedTabID() {
    #expect(ITermParsing.tabID(from: "\"2\"\n") == "2")
}

@Test func tabIDReturnsNilForEmptyOutput() {
    #expect(ITermParsing.tabID(from: "") == nil)
    #expect(ITermParsing.tabID(from: "   \n") == nil)
}
