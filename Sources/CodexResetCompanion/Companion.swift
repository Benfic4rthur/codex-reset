import AppKit

/// A small background process started by launchd. It has no window or menu-bar
/// item; the monitor itself only runs while the ChatGPT/Codex desktop app runs.
@MainActor
private final class Companion {
    private let hostID = "com.openai.codex"
    private let monitorID = "com.arthurbenfica.codexreset"
    private let appURL: URL
    private var observers: [NSObjectProtocol] = []

    init(appURL: URL) {
        self.appURL = appURL
    }

    func run() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier == self?.hostID else { return }
            MainActor.assumeIsolated { self?.launchMonitor() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier == self?.hostID else { return }
            MainActor.assumeIsolated { self?.stopMonitorIfHostClosed() }
        })
        if hostIsRunning { launchMonitor() } else { stopMonitorIfHostClosed() }
        RunLoop.main.run()
    }

    private var hostIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: hostID)
            .contains { !$0.isTerminated }
    }

    private func launchMonitor() {
        guard hostIsRunning,
              NSRunningApplication.runningApplications(withBundleIdentifier: monitorID)
                .allSatisfy({ $0.isTerminated }) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) {
            _, error in
            if let error { NSLog("Codex Reset: %@", error.localizedDescription) }
        }
    }

    private func stopMonitorIfHostClosed() {
        guard !hostIsRunning else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: monitorID)
            .filter { !$0.isTerminated }
            .forEach { _ = $0.terminate() }
    }
}

@main
private struct CompanionMain {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("CodexResetCompanion requires the app path\n", stderr)
            return
        }
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        Companion(appURL: appURL).run()
    }
}
