/// F*n* switches to tab n-1 of the cached window first, then raises the app.
/// The tab changes while iTerm is still behind, so the window comes up already
/// showing it.
public struct TabFocus {
    private let gotoTab: (Int, String?) -> Void
    private let windowID: () -> String?
    private let activate: () -> Void

    /// `windowID` must return a cached value: a keypress does no extra it2 lookup.
    public init(
        gotoTab: @escaping (Int, String?) -> Void,
        windowID: @escaping () -> String?,
        activate: @escaping () -> Void
    ) {
        self.gotoTab = gotoTab
        self.windowID = windowID
        self.activate = activate
    }

    /// The production wiring, kept here so a test covers it: `it2 tab goto`
    /// gets the window id the resolver last resolved.
    public init(cli: ITermCLI, resolver: TabResolver, activate: @escaping () -> Void) {
        self.init(
            gotoTab: { index, window in cli.gotoTab(index, window: window) },
            windowID: { resolver.windowID },
            activate: activate
        )
    }

    public func focus(key: Int) {
        gotoTab(key - 1, windowID())
        activate()
    }
}
