import AppKit

/// How long a revealed full account number stays on screen: a minute, as long as a copy of it lasts,
/// or until the user steps away, whichever comes first. Showing it again asks for Touch ID again.
@MainActor
enum RevealedNumber {
    static let hideAfter: Duration = SensitivePasteboard.clearAfter

    /// Stepping away: Kortex stops being the active app, the screens sleep or lock, the Mac sleeps,
    /// or another user is switched in.
    static var away: [(NotificationCenter, Notification.Name)] {
        let workspace = NSWorkspace.shared.notificationCenter
        return [
            (.default, NSApplication.didResignActiveNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),
        ]
    }

    /// Returns when the number should hide, or as soon as the calling task is cancelled.
    static func waitToHide(after timeout: Duration = hideAfter, on events: [(NotificationCenter, Notification.Name)]? = nil) async {
        let events = events ?? away
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await Task.sleep(for: timeout) }
            for (center, name) in events {
                group.addTask { for await _ in center.notifications(named: name) { return } }
            }
            await group.next()
            group.cancelAll()
        }
    }
}
