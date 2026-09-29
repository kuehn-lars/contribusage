import AppKit
import ContribusageCore
import Network

/// Tells the coordinator what the Mac is doing (SPEC §12 rules 1 to 3, ADR-018): sleep and wake, the network path and
/// Low Power Mode. Lives as long as the app, so its observers are never removed.
final class SystemConditions {
    private let onChange: (ScheduleConditions) -> Void
    private let monitor = NWPathMonitor()
    private var conditions = ScheduleConditions(isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled) {
        didSet { if conditions != oldValue { onChange(conditions) } }
    }

    init(onChange: @escaping (ScheduleConditions) -> Void) {
        self.onChange = onChange
        onChange(conditions)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.isAsleep = false
            $0.lastWake = .now
        }
        observe(.default, .NSProcessInfoPowerStateDidChange) {
            $0.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            MainActor.assumeIsolated { self?.conditions.isOnline = online }
        }
        monitor.start(queue: .main)
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ change: @escaping @Sendable @MainActor (inout ScheduleConditions) -> Void
    ) {
        // The center holds the block until it is removed, which never happens.
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(&self.conditions)
            }
        }
    }
}
