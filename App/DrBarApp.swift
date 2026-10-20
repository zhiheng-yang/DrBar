import AppKit
import DrBarKit
import DrBarUI
import SwiftUI

@main
struct DrBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .modifier(TimelineEnvironment())
                .environment(store)
        } label: {
            MenuBarLabelView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        // A single window, so the planner can never be opened twice.
        Window("Planner", id: WindowID.planner) {
            PlannerWindow()
                .modifier(TimelineEnvironment())
                .environment(store)
                .tracksWindow(WindowID.planner, in: store)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Paper") { store.request(.paper) }
                    .keyboardShortcut("n")
                Button("New Group") { store.request(.group) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Group {
                    Button("Back") { store.goBack() }
                        .keyboardShortcut("[")
                        .disabled(!store.canGoBack)
                    Button("Forward") { store.goForward() }
                        .keyboardShortcut("]")
                        .disabled(!store.canGoForward)
                    Divider()
                    Button("Zoom In") { zoomPlanner(to: store.plannerPosition.zoom * 1.5) }
                        .keyboardShortcut("=")
                    Button("Zoom Out") { zoomPlanner(to: store.plannerPosition.zoom / 1.5) }
                        .keyboardShortcut("-")
                    Button("Actual Size") { zoomPlanner(to: 1) }
                        .keyboardShortcut("0")
                        .disabled(store.plannerPosition.zoom == 1)
                }
                .disabled(!store.isPlannerOpen)
                Picker("Row Size", selection: store.rowSize) {
                    RowSizeChoices()
                }
            }
        }

        Window("Deadline", id: WindowID.deadline) {
            DeadlineWindow()
                .modifier(TimelineEnvironment())
                .environment(store)
                .tracksWindow(WindowID.deadline, in: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(store)
                .tracksWindow(WindowID.settings, in: store)
        }
    }

    /// The View menu zooms the planner around today, or around the middle when today is out of
    /// sight.
    private func zoomPlanner(to level: Double) {
        withMotion(.glide) {
            store.plannerPosition.zoom(to: level, now: store.now, range: store.axisRange)
        }
    }
}

extension View {
    /// Tells the store when the window opens and closes; while one is open, the app shows in the
    /// Dock and in ⌘Tab.
    fileprivate func tracksWindow(_ id: String, in store: AppStore) -> some View {
        onAppear { store.windowDidAppear(id) }
            .onDisappear { store.windowDidDisappear(id) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let folder = DemoData.snapshotFolder {
            Task {
                await DebugSnapshots.render(into: folder)
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = DemoData.recordingFolder {
            Task {
                await DebugRecording.render(into: folder)
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        AppStore.shared.start()
    }

    /// Closing the planner must not quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
