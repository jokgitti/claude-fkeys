/// F*n* switches to tab n-1 first, then raises the app. The tab changes while
/// iTerm is still behind, so the window comes up already showing it.
public struct TabFocus {
    private let gotoTab: (Int) -> Void
    private let activate: () -> Void

    public init(gotoTab: @escaping (Int) -> Void, activate: @escaping () -> Void) {
        self.gotoTab = gotoTab
        self.activate = activate
    }

    public func focus(key: Int) {
        gotoTab(key - 1)
        activate()
    }
}
