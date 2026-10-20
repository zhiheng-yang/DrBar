#if DEBUG
import AppKit
import DrBarKit
import DrBarUI
import SwiftUI

/// The app's motion, drawn frame by frame with the demo data, for the films of the website: a
/// folder of numbered PNG frames for each, in light and in dark, sixty to a second. Every frame is
/// set rather than timed, so that the films are the same on every Mac.
@MainActor
enum DebugRecording {
    /// What changes from one frame to the next, besides the store.
    @Observable
    final class Moment {
        var growth: CGFloat?
    }

    /// Where the planner's pages begin, past the sidebar, as the screenshots are cropped.
    private static let sidebarWidth: CGFloat = 228

    static func render(into folder: URL) async {
        let store = AppStore.shared
        await store.prepareForDemo()
        let paperID = store.userData.papers[0].id
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // The menu bar window opening: its bars grow out of today's line.
            store.popoverPosition = AxisPosition()
            await film(
                PopoverView(), width: PopoverView.width, appearance: appearance, frames: 84,
                to: folder.appending(path: "popover-grow-\(suffix)")
            ) { moment, frame in
                moment.growth = eased(frame - 12, over: 48)
            }

            // A paper's page as it opens, its plan growing in.
            store.plannerSelection = .paper(paperID)
            store.plannerPosition = AxisPosition()
            await film(
                PlannerWindow(), size: CGSize(width: 1100, height: 900),
                crop: CGRect(x: sidebarWidth, y: 0, width: 1100 - sidebarWidth, height: 815), appearance: appearance,
                frames: 84, to: folder.appending(path: "paper-grow-\(suffix)")
            ) { moment, frame in
                moment.growth = eased(frame - 12, over: 48)
            }

            // The overview zoomed in, until each day has a column, and out again, as by a pinch.
            store.plannerSelection = .overview
            await film(
                PlannerWindow(), size: CGSize(width: 1100, height: 1000),
                crop: CGRect(x: sidebarWidth, y: 0, width: 1100 - sidebarWidth, height: 638), appearance: appearance,
                frames: 240, to: folder.appending(path: "overview-zoom-\(suffix)")
            ) { moment, frame in
                moment.growth = 1
                let inward = smoothly(frame - 18, over: 96)
                let outward = smoothly(frame - 144, over: 84)
                store.plannerPosition.zoom = 1 + 3 * (inward - outward)
            }
            store.plannerPosition = AxisPosition()
        }
        store.plannerSelection = .overview
    }

    /// From 0 to 1 over `count` frames, quickly at first and then settling, as the app's glide
    /// does; 0 before and 1 after.
    private static func eased(_ frame: Int, over count: Int) -> CGFloat {
        let t = min(max(CGFloat(frame) / CGFloat(count), 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// From 0 to 1 over `count` frames, slow at both ends, as a pinch starts and stops.
    private static func smoothly(_ frame: Int, over count: Int) -> CGFloat {
        let t = min(max(CGFloat(frame) / CGFloat(count), 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Hosts the view in an offscreen window, as a snapshot does, and draws `frames` frames of it,
    /// each after `frame` has set what it shows.
    private static func film<V: View>(
        _ view: V, width: CGFloat? = nil, size: CGSize? = nil, crop: CGRect? = nil,
        appearance: NSAppearance.Name, frames: Int, to folder: URL, frame: (Moment, Int) -> Void
    ) async {
        let moment = Moment()
        frame(moment, 0)
        let host = NSHostingView(rootView: Stage(moment: moment, content: view))
        host.appearance = NSAppearance(named: appearance)
        var bounds = CGRect(origin: .zero, size: size ?? host.fittingSize)
        if let width {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            bounds.size = CGSize(width: width, height: host.fittingSize.height)
        }
        let window = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.frame = bounds
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        if let width {
            bounds.size = CGSize(width: width, height: host.fittingSize.height)
            window.setContentSize(bounds.size)
            host.frame = bounds
            try? await Task.sleep(for: .milliseconds(400))
        }
        window.makeFirstResponder(nil)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let area = crop ?? host.bounds
        for index in 0..<frames {
            frame(moment, index)
            try? await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: area) else { continue }
            host.cacheDisplay(in: area, to: rep)
            try? rep.converting(to: .sRGB, renderingIntent: .default)?
                .representation(using: .png, properties: [:])?
                .write(to: folder.appending(path: String(format: "%04d.png", index)))
        }
        window.orderOut(nil)
        window.contentView = nil
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// What views remember for themselves, in a domain of its own that starts empty.
    private static let storage: UserDefaults = {
        let name = "DrBarRecording"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }()

    /// The view as the app shows it, at the moment `moment` says, with nothing animated on its own.
    private struct Stage<Content: View>: View {
        let moment: Moment
        let content: Content

        var body: some View {
            content
                .modifier(TimelineEnvironment())
                .environment(AppStore.shared)
                .environment(\.recordedGrowth, moment.growth)
                .defaultAppStorage(DebugRecording.storage)
                .background(Color(nsColor: .windowBackgroundColor))
                .transaction { $0.animation = nil }
        }
    }
}
#endif
