import AppKit
import SwiftUI

// Debug hook: `BNTransMac --dump-models` prints the model list for the
// saved settings and exits — lets the fetcher be verified from a shell.
if CommandLine.arguments.contains("--dump-models") {
    let settings = Settings.load()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let models = try await ModelsFetcher.fetch(settings: settings)
            print(models.joined(separator: "\n"))
            print("-- \(models.count) models")
        } catch {
            print("ERR \(error.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon

// Debug hook: `--open-settings` opens the settings window after launch.
let openSettings = CommandLine.arguments.contains("--open-settings")
if openSettings {
    NotificationCenter.default.addObserver(
        forName: NSApplication.didFinishLaunchingNotification,
        object: nil, queue: .main
    ) { _ in
        Task { @MainActor in
            (app.delegate as? AppDelegate)?.openSettingsForDebug()
        }
    }
}

// Debug hook: `--test-select` opens a standalone window with the model
// select force-opened, to verify the AppKit panel presents correctly.
if CommandLine.arguments.contains("--test-select") {
    NotificationCenter.default.addObserver(
        forName: NSApplication.didFinishLaunchingNotification,
        object: nil, queue: .main
    ) { _ in
        Task { @MainActor in
            let win = NSWindow(
                contentRect: NSRect(x: 300, y: 600, width: 420, height: 200),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "Select Test"
            win.contentView = NSHostingView(rootView: SelectTestView())
            win.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }
    }
}

app.run()
