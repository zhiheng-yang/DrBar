import AppKit
import DrBarKit
import SwiftUI

/// What a plan bar lets the user do with its blocks, much as Calendar does with events: drag an
/// end to change when a block starts or ends, drag the middle to move it, and, where given,
/// select one with a click, open it with a double-click, copy it by dragging with Option held,
/// tick it off or delete it, and draw a new one across empty days.
public struct BlockEditing {
    /// What the paper's work is measured against: a block dragged past the deadline it leads up to
    /// is marked while it is dragged.
    public var cutoffs: Cutoffs
    /// The days of the paper's deadlines, which a dragged block's ends can land on.
    public var deadlineDays: [Day]
    /// Blocks drawn in other rows, whose ends a dragged block can line up with.
    public var otherBlocks: [TimeBlock]
    /// The selected block, which has a ring.
    public var selection: TimeBlock.ID?
    /// Called when a drag ends with the block on other days.
    public var commit: (_ block: TimeBlock, _ handle: TimeBlock.Handle) -> Void
    /// Called with a block drawn across empty days, copied, or added as another round.
    public var add: ((TimeBlock) -> Void)?
    /// Called when a block is clicked, or empty days (`nil`). Without it, the click goes to the row.
    public var select: ((TimeBlock.ID?) -> Void)?
    /// Called when a block is double-clicked.
    public var open: ((TimeBlock) -> Void)?
    public var toggleDone: ((TimeBlock) -> Void)?
    public var delete: ((TimeBlock) -> Void)?
    /// Moves the axis by that many points, as a swipe does, while a drag is held at the edge of
    /// the bars.
    public var pan: ((CGFloat) -> Void)?
    /// Everyone a block can name as working on it, offered in its menu.
    public var people: [Person]
    /// Puts someone on a block, or takes them off it.
    public var togglePerson: ((TimeBlock, Person.ID) -> Void)?
    /// The block that drawing from one day to another makes, which the timeline gives each row.
    var newBlock: ((Day, Day) -> TimeBlock)?

    public init(
        cutoffs: Cutoffs = .none, deadlineDays: [Day] = [], otherBlocks: [TimeBlock] = [],
        selection: TimeBlock.ID? = nil,
        commit: @escaping (TimeBlock, TimeBlock.Handle) -> Void, add: ((TimeBlock) -> Void)? = nil,
        select: ((TimeBlock.ID?) -> Void)? = nil, open: ((TimeBlock) -> Void)? = nil,
        toggleDone: ((TimeBlock) -> Void)? = nil, delete: ((TimeBlock) -> Void)? = nil,
        pan: ((CGFloat) -> Void)? = nil, people: [Person] = [], togglePerson: ((TimeBlock, Person.ID) -> Void)? = nil
    ) {
        self.cutoffs = cutoffs
        self.deadlineDays = deadlineDays
        self.otherBlocks = otherBlocks
        self.selection = selection
        self.commit = commit
        self.add = add
        self.select = select
        self.open = open
        self.toggleDone = toggleDone
        self.delete = delete
        self.pan = pan
        self.people = people
        self.togglePerson = togglePerson
    }

    var hasMenu: Bool {
        open != nil || toggleDone != nil || delete != nil || add != nil
    }

    var canDraw: Bool {
        add != nil && newBlock != nil
    }

    /// The days an end of `block` is felt snapping onto: today, the deadlines, the days after them,
    /// and where the other blocks start and end.
    func guides(for block: TimeBlock, among blocks: [TimeBlock], today: Day) -> (starts: Set<Day>, ends: Set<Day>) {
        let others = (blocks + otherBlocks).filter { $0.id != block.id }
        var starts: Set<Day> = [today]
        var ends: Set<Day> = []
        for day in deadlineDays {
            ends.insert(day)
            starts.insert(day.adding(1))
        }
        for other in others {
            starts.formUnion([other.start, other.end.adding(1)])
            ends.formUnion([other.end, other.start.adding(-1)])
        }
        return (starts, ends)
    }
}

/// A block while it is dragged: as it was, the part held, the moment that was under the pointer
/// when the drag began, and where the pointer is now in the bar area. Measured in moments rather
/// than points, the block keeps up with an axis that moves under a held drag. Dragged with Option
/// held, it is a copy that moves, and the block stays.
struct BlockDrag: Equatable {
    let original: TimeBlock
    let handle: TimeBlock.Handle
    let anchor: Date
    var x: CGFloat
    /// The copy's id while Option is held.
    var copyID: UUID?

    func block(on axis: TimeAxis, width: CGFloat) -> TimeBlock {
        var block = original.dragged(handle, by: wholeDays(from: anchor, to: axis.date(atX: x, width: width)))
        if let copyID {
            block.id = copyID
            block.isDone = false
        }
        return block
    }
}

/// Days being drawn across with the pointer: the day where the drag began, and where the pointer
/// is now in the bar area, either way round.
struct BlockDrawing: Equatable {
    let from: Day
    var x: CGFloat

    func to(on axis: TimeAxis, width: CGFloat) -> Day {
        Day(axis.date(atX: min(max(x, 0), width), width: width))
    }

    func days(on axis: TimeAxis, width: CGFloat) -> (first: Day, last: Day) {
        let to = to(on: axis, width: width)
        return (min(from, to), max(from, to))
    }
}

/// What a drag keeps from where it began, such as the moment under the pointer, for that drag alone:
/// one whose end never comes, as when its view goes, leaves nothing behind for the next.
struct DragAnchor<Value> {
    private var start: CGPoint?
    private var value: Value?

    init() {}

    init(_ value: Value, at start: CGPoint) {
        self.start = start
        self.value = value
    }

    /// What was kept, if `drag` is the drag it was kept for.
    func value(for drag: DragGesture.Value) -> Value? {
        drag.startLocation == start ? value : nil
    }
}

/// The bar area of a timeline row, which its drags are measured in, wherever the row is in the window.
struct TrackSpace: Hashable {}

/// How many days lie between two moments, to the nearest day.
func wholeDays(from start: Date, to end: Date) -> Int {
    Int((end.timeIntervalSince(start) / 86_400).rounded())
}

/// Moves a timeline while a drag is held near either end of its bars, faster the closer it is, so
/// that a block or milestone can be taken past what is on screen. It stops with the drag, and also
/// once the button is up or the view gone, should the drag's end never come.
@MainActor
final class EdgeScroll {
    private nonisolated(unsafe) var timer: Timer?
    private var step: CGFloat = 0
    private var pan: ((CGFloat) -> Void)?

    /// How far from each end the scrolling starts.
    private static let zone: CGFloat = 36
    /// Points per frame at the very edge and beyond it.
    private static let fastest: CGFloat = 4

    /// Scrolls while `x` is near either end of a bar area `width` points wide, or past it, and stops
    /// otherwise.
    func follow(x: CGFloat, width: CGFloat, pan: ((CGFloat) -> Void)?) {
        let depth =
            x < Self.zone
            ? (Self.zone - x) / Self.zone : x > width - Self.zone ? (width - Self.zone - x) / Self.zone : 0
        guard let pan, depth != 0 else {
            stop()
            return
        }
        // Earlier at the left end, later at the right; slowly at first, so that a day can be hit.
        let clamped = min(max(depth, -1), 1)
        step = Self.fastest * clamped * abs(clamped)
        self.pan = pan
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Also while the mouse is tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pan = nil
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons != 0 else {
            stop()
            return
        }
        pan?(step)
    }

    deinit {
        timer?.invalidate()
    }
}

/// Where each block and milestone of a timeline is drawn, so that a popover can point at one.
public struct TimelineBounds: PreferenceKey {
    public static var defaultValue: [TimeBlock.ID: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [TimeBlock.ID: Anchor<CGRect>], nextValue: () -> [TimeBlock.ID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where a dragged block, milestone or deadline lands, above it: its days and length, its day, or
/// its moment.
struct DragLabel: View {
    let parts: [String]
    let isPastDeadline: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(parts.indices, id: \.self) { index in
                if index > 0 {
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                }
                Text(parts[index])
            }
            if isPastDeadline {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// Esc during a drag puts back what was dragged, as in Finder: `listen` when a drag starts, `stop`
/// when it ends.
@MainActor
public final class DragCancellation {
    private nonisolated(unsafe) var monitor: Any?

    public init() {}

    /// Calls `cancel` once if Esc is pressed before `stop`; what it puts back slides into place.
    public func listen(_ cancel: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            // A drag whose end never came is over once the button is up; the key goes on.
            guard NSEvent.pressedMouseButtons != 0 else {
                MainActor.assumeIsolated { self?.stop() }
                return event
            }
            MainActor.assumeIsolated {
                self?.stop()
                withMotion(.settle) { cancel() }
            }
            return nil
        }
    }

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

enum BlockCursor {
    static func hover(_ handle: TimeBlock.Handle) -> NSCursor {
        handle == .body ? .openHand : resize(handle)
    }

    static func drag(_ handle: TimeBlock.Handle, copies: Bool = false) -> NSCursor {
        copies ? .dragCopy : handle == .body ? .closedHand : resize(handle)
    }

    private static func resize(_ handle: TimeBlock.Handle) -> NSCursor {
        if #available(macOS 15, *) {
            return .frameResize(position: handle == .start ? .left : .right, directions: .all)
        }
        return .resizeLeftRight
    }
}
