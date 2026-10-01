import Foundation

/// Runs a `LightPublisher` on its own serial queue with its own timer.
///
/// The keepalive must outrun the firmware's 10 s watchdog. The main queue also
/// runs `it2` calls, each up to its 2 s timeout, so five stacked key presses
/// could starve a main-queue timer. Nothing on this queue calls `it2`, and
/// `publish` never blocks its caller. The only thing that can stall this
/// queue is the HID write itself (IOHIDDeviceSetReport is synchronous and has
/// no timeout), and a stalled USB device cannot be lit anyway.
public final class KeyboardLights: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fkeysd.keyboard")
    private let publisher: LightPublisher
    private let interval: TimeInterval
    private let leeway: TimeInterval
    private var timer: DispatchSourceTimer?

    public init(
        sink: ReportSink,
        palette: @escaping () -> Palette,
        log: @escaping (String) -> Void = { _ in },
        interval: TimeInterval = 2,
        leeway: TimeInterval = 0.2
    ) {
        self.publisher = LightPublisher(sink: sink, palette: palette, log: log)
        self.interval = interval
        self.leeway = leeway
    }

    /// Opens the link now and then ticks every `interval`.
    public func start() {
        queue.async { [self] in
            publisher.tick()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(leeway * 1000)))
            source.setEventHandler { [publisher] in publisher.tick() }
            source.resume()
            timer = source
        }
    }

    public func publish(_ states: [KeyState]) {
        queue.async { [publisher] in publisher.publish(states) }
    }

    /// Waits for queued work. Tests only.
    public func drain() {
        queue.sync {}
    }
}
