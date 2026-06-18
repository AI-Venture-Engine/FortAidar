import AppKit
import SwiftUI

@main
struct FortAidarPrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PrototypeVaultStore()

    var body: some Scene {
        WindowGroup("Fort Aidar", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 920, minHeight: 620)
                .task {
                    await store.refresh()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandMenu("Vault") {
                Button("Create or Unlock") {
                    store.focusPassphraseField()
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button("Add Files or Folders") {
                    store.addItemsWithPicker()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!store.state.isMounted)

                Button("Lock") {
                    Task { await store.lock() }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!store.state.isMounted)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
