import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct KimiWebConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ConsoleController()

    var body: some Scene {
        WindowGroup("Kimi Web 控制台") {
            ContentView(controller: controller)
        }
        .defaultSize(width: 590, height: 540)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
