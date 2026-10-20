import DrBarKit
import DrBarUI
import Foundation
import SwiftUI

/// Changes to papers and the items of other groups, to groups, blocks, milestones, to-dos,
/// deadlines and stars that Edit › Undo takes back. Each undo reverses only its own change, so whatever was
/// edited in between stays.
extension AppStore {
    // MARK: Papers and items

    /// A new paper, or a new item of the group with `groupID`, selected, with its title ready to
    /// type.
    func addItem(in groupID: UUID? = nil, undoManager: UndoManager?) {
        let title = groupID == nil ? String(localized: "New Paper") : String(localized: "New Item")
        let item = Paper(title: title, groupID: groupID)
        insert(item, at: userData.papers.count, title, undoManager)
        focusRequest = item.id
    }

    /// A paper, or an item of the group with `groupID`, named `title` and due at 23:59 on `day`, as
    /// Siri and Shortcuts add one: where the others are, without opening it. Returns its id, or
    /// `nil` when the group is gone.
    func addWork(title: String, in groupID: UUID?, dueOn day: Day) -> UUID? {
        guard groupID == nil || userData.groups.contains(where: { $0.id == groupID }) else { return nil }
        let item = Paper(title: title, groupID: groupID)
        userData.papers.append(item)
        addDeadline(to: item.id, on: day, undoManager: nil)
        return item.id
    }

    /// Moves a paper or an item to Recently Deleted, where it stays for thirty days.
    func deletePaper(_ id: UUID, undoManager: UndoManager?) {
        delete([id], undoManager: undoManager)
    }

    /// Moves papers or items to Recently Deleted together, to come back together with ⌘Z.
    func delete(_ ids: [UUID], undoManager: UndoManager?) {
        let deleted = (userData.papers + userData.archive).filter { ids.contains($0.id) }
        guard !deleted.isEmpty else { return }
        let actionName =
            switch (deleted.allSatisfy(\.isPaper), deleted.count) {
            case (true, 1): String(localized: "Delete Paper")
            case (true, _): String(localized: "Delete Papers")
            case (false, 1): String(localized: "Delete Item")
            case (false, _): String(localized: "Delete Items")
            }
        trash(deleted.map(\.id), actionName, undoManager)
    }

    /// Moves papers or items, or parts of them, to Recently Deleted, at the moment it happens, so
    /// that what is deleted one after another is listed in that order.
    private func trash(_ ids: [UUID], _ actionName: String, _ undoManager: UndoManager?) {
        let deleted = userData.delete(ids, now: Date())
        guard !deleted.isEmpty else { return }
        leavePages(of: deleted)
        registerUndo(actionName, undoManager) { $0.recover(deleted, actionName, undoManager) }
    }

    /// Brings papers, items or parts of them back from Recently Deleted; a part's paper or item
    /// comes back with it.
    func recover(_ ids: [UUID], undoManager: UndoManager?) {
        recover(ids, String(localized: "Recover"), undoManager)
    }

    /// Its undo returns each to Recently Deleted as it was there, with its days and its group.
    private func recover(_ ids: [UUID], _ actionName: String, _ undoManager: UndoManager?) {
        let recovery = userData.recover(ids)
        guard !recovery.ids.isEmpty else { return }
        registerUndo(actionName, undoManager) { store in
            let returned = store.userData.putBack(recovery, now: Date())
            store.leavePages(of: returned)
            store.registerUndo(actionName, undoManager) { $0.recover(returned, actionName, undoManager) }
        }
    }

    /// The overview instead of the page of a paper or an item that went.
    func leavePages(of ids: [UUID]) {
        if case let .paper(selected) = plannerSelection, ids.contains(selected) {
            plannerSelection = .overview
        }
        closeSendSheet(of: ids)
    }

    /// Closes the send sheet of a paper that went, unless its update is going out.
    private func closeSendSheet(of ids: [UUID]) {
        if let paperID = sendSheetPaperID, ids.contains(paperID), !isSendingProgress {
            sendSheetPaperID = nil
        }
    }

    /// Deletes for good; there is nothing to undo.
    func deleteForever(_ ids: Set<UUID>) {
        userData.deleteForever(ids)
    }

    /// Puts a paper or an item away in the Archive.
    func archive(_ id: UUID, undoManager: UndoManager?) {
        guard let index = userData.archive(id, now: now) else { return }
        closeSendSheet(of: [id])
        registerUndo(String(localized: "Archive"), undoManager) { store in
            store.userData.unarchive(id, at: index)
            store.registerUndo(String(localized: "Archive"), undoManager) { $0.archive(id, undoManager: undoManager) }
        }
    }

    /// Moves papers or items back from the Archive to the end of their groups.
    func unarchive(_ ids: [UUID], undoManager: UndoManager?) {
        let archived = userData.archive.filter { ids.contains($0.id) }
        guard !archived.isEmpty else { return }
        for paper in archived {
            userData.unarchive(paper.id)
        }
        registerUndo(String(localized: "Move Back"), undoManager) { store in
            for paper in archived {
                store.userData.archive(paper.id, now: paper.archivedAt ?? store.now)
            }
            store.registerUndo(String(localized: "Move Back"), undoManager) {
                $0.unarchive(archived.map(\.id), undoManager: undoManager)
            }
        }
    }

    /// Moves a paper or an item to the end of another group, or of the papers, while that group is
    /// there. Returns whether it moved.
    @discardableResult
    func move(_ id: UUID, toGroup groupID: UUID?, undoManager: UndoManager?) -> Bool {
        guard let index = userData.papers.firstIndex(where: { $0.id == id }), userData.papers[index].groupID != groupID,
            groupID == nil || userData.groups.contains(where: { $0.id == groupID })
        else { return false }
        var item = userData.papers.remove(at: index)
        let old = item.groupID
        item.groupID = groupID
        userData.papers.append(item)
        registerUndo(String(localized: "Move to Group"), undoManager) { store in
            // Back to its place, as near as the papers and items left allow.
            guard store.move(id, toGroup: old, undoManager: undoManager),
                let back = store.userData.papers.firstIndex(where: { $0.id == id })
            else { return }
            let item = store.userData.papers.remove(at: back)
            store.userData.papers.insert(item, at: min(index, store.userData.papers.count))
        }
        return true
    }

    /// Puts a paper or an item back, unless it has come back some other way meanwhile.
    private func insert(_ paper: Paper, at index: Int, _ actionName: String, _ undoManager: UndoManager?) {
        guard !userData.contains(paper.id) else { return }
        userData.papers.insert(paper, at: min(index, userData.papers.count))
        plannerSelection = .paper(paper.id)
        registerUndo(actionName, undoManager) { $0.remove(paper: paper.id, as: paper, actionName, undoManager) }
    }

    /// Takes back a new paper or item: away as it came, or, once it holds anything more, such as a
    /// title typed in or blocks from Siri, to Recently Deleted, from where Redo brings it back.
    private func remove(paper id: UUID, as made: Paper, _ actionName: String, _ undoManager: UndoManager?) {
        guard let index = userData.papers.firstIndex(where: { $0.id == id }) else { return }
        guard userData.papers[index] == made, !userData.deletedParts.contains(where: { $0.paperID == id }) else {
            trash([id], actionName, undoManager)
            return
        }
        let paper = userData.papers.remove(at: index)
        leavePages(of: [id])
        registerUndo(actionName, undoManager) { $0.insert(paper, at: index, actionName, undoManager) }
    }

    /// How tall each track of a paper's bar is in the overview, or `nil` to fit it to the blocks
    /// again.
    func setTrackHeight(_ height: Double?, of paperID: UUID, undoManager: UndoManager?) {
        guard let index = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        let old = userData.papers[index].trackHeight
        guard old != height else { return }
        userData.papers[index].trackHeight = height
        registerUndo(String(localized: "Resize Row"), undoManager) {
            $0.setTrackHeight(old, of: paperID, undoManager: undoManager)
        }
    }

    /// Puts the groups and their items in the order of `rows`, as the sidebar arranges them by
    /// dragging: a group moved, an item moved to another group, or one moved within its group.
    func arrange(_ rows: [SidebarRow], undoManager: UndoManager?) {
        let before = (rows: userData.sidebarRows, groups: userData.groupOrder, papers: userData.papers)
        guard rows != before.rows else { return }
        userData.arrange(rows)
        let groupIDs = Dictionary(before.papers.map { ($0.id, $0.groupID) }, uniquingKeysWith: { first, _ in first })
        let actionName =
            if userData.groupOrder != before.groups {
                String(localized: "Move Group")
            } else if userData.papers.contains(where: { groupIDs[$0.id] != $0.groupID }) {
                String(localized: "Move to Group")
            } else if userData.items(in: nil).map(\.id) != before.papers.filter(\.isPaper).map(\.id) {
                String(localized: "Move Paper")
            } else {
                String(localized: "Move Item")
            }
        registerUndo(actionName, undoManager) { $0.arrange(before.rows, undoManager: undoManager) }
    }

    /// Moves a group, with its items, one place up or down among the groups.
    func moveGroup(_ id: UUID?, by offset: Int, undoManager: UndoManager?) {
        let rows = userData.sidebarRows
        let boundaries = rows.indices.filter { rows[$0].isHeading } + [rows.count]
        guard let position = boundaries.firstIndex(where: { $0 < rows.count && rows[$0] == .heading(id) }) else {
            return
        }
        let destination = offset < 0 ? position - 1 : position + 2
        guard boundaries.indices.contains(destination) else { return }
        arrange(
            rows.moving(fromOffsets: [boundaries[position]], toOffset: boundaries[destination]),
            undoManager: undoManager)
    }

    /// Moves a paper or an item one place up or down within its group.
    func moveItem(_ id: UUID, by offset: Int, undoManager: UndoManager?) {
        let rows = userData.sidebarRows
        guard let index = rows.firstIndex(of: .item(id)), rows.indices.contains(index + offset),
            !rows[index + offset].isHeading
        else { return }
        arrange(
            rows.moving(fromOffsets: [index], toOffset: offset < 0 ? index + offset : index + offset + 1),
            undoManager: undoManager)
    }

    // MARK: Stars

    /// Follows a conference series, or stops following it.
    func toggleStar(_ seriesKey: String, undoManager: UndoManager?) {
        toggleStar(
            seriesKey, isStarred(seriesKey) ? String(localized: "Unstar") : String(localized: "Star"), undoManager)
    }

    private func toggleStar(_ seriesKey: String, _ actionName: String, _ undoManager: UndoManager?) {
        if userData.favoriteSeries.remove(seriesKey) == nil {
            userData.favoriteSeries.insert(seriesKey)
        }
        registerUndo(actionName, undoManager) { $0.toggleStar(seriesKey, actionName, undoManager) }
    }

    // MARK: Groups

    /// A new group after the others, its name ready to type in the sidebar.
    func addGroup(undoManager: UndoManager?) {
        let group = ItemGroup(name: "")
        insert(group, at: userData.groupOrder.count, String(localized: "New Group"), undoManager)
        renamingGroup = group.id
    }

    func renameGroup(_ id: UUID, to name: String, undoManager: UndoManager?) {
        guard let index = userData.groups.firstIndex(where: { $0.id == id }) else { return }
        let old = userData.groups[index].name
        guard old != name else { return }
        userData.groups[index].name = name
        registerUndo(String(localized: "Rename Group"), undoManager) {
            $0.renameGroup(id, to: old, undoManager: undoManager)
        }
    }

    /// Shows a group's items with another symbol, in the sidebar and the menu bar.
    func setSymbol(_ symbol: String, ofGroup id: UUID, undoManager: UndoManager?) {
        guard let index = userData.groups.firstIndex(where: { $0.id == id }) else { return }
        let old = userData.groups[index].shownSymbol
        guard old != symbol else { return }
        userData.groups[index].symbol = symbol
        registerUndo(String(localized: "Change Icon"), undoManager) {
            $0.setSymbol(old, ofGroup: id, undoManager: undoManager)
        }
    }

    /// Deletes a group; its items, also those in the Archive, go to Recently Deleted, and the group
    /// comes back with the first of them recovered.
    func deleteGroup(_ id: UUID, undoManager: UndoManager?) {
        remove(group: id, String(localized: "Delete Group"), undoManager)
    }

    /// Puts a group into the sidebar at `position` among the others.
    private func insert(_ group: ItemGroup, at position: Int, _ actionName: String, _ undoManager: UndoManager?) {
        guard !userData.groups.contains(where: { $0.id == group.id }) else { return }
        userData.insertGroup(group, at: position)
        registerUndo(actionName, undoManager) { $0.remove(group: group.id, actionName, undoManager) }
    }

    /// Takes a group out of the sidebar, as deleting it or undoing New Group does. Items in it,
    /// such as those that came from Siri while it was there, go to Recently Deleted, the archived
    /// ones too, and come back with it.
    private func remove(group id: UUID, _ actionName: String, _ undoManager: UndoManager?) {
        guard userData.hasItems(inGroup: id) else {
            guard let (group, position) = userData.removeGroup(id) else { return }
            registerUndo(actionName, undoManager) { $0.insert(group, at: position, actionName, undoManager) }
            return
        }
        let ids = userData.deleteGroup(id, now: Date())
        leavePages(of: ids)
        registerUndo(actionName, undoManager) { store in
            store.userData.recover(ids)
            store.registerUndo(actionName, undoManager) { $0.remove(group: id, actionName, undoManager) }
        }
    }

    // MARK: Conference, stage and deadlines

    /// Points a paper or an item at a conference edition, or at another round of it. A new edition
    /// lets go of the old one's ticks and of the own deadlines that have passed.
    func setTarget(_ target: Paper.Target, of paperID: UUID, undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }), paper.target != target else { return }
        let isNewEdition = paper.target.map { $0.series != target.series || $0.year != target.year } ?? true
        userData.setTarget(target, of: paperID, catalog: catalog, now: now)
        let actionName = isNewEdition ? String(localized: "Change Conference") : String(localized: "Change Round")
        registerUndo(actionName, from: paper, undoManager) {
            $0.setTarget(target, of: paperID, undoManager: undoManager)
        }
    }

    /// Takes the conference away; the paper or the item then aims at its next own deadline.
    func removeConference(of paperID: UUID, undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }), paper.target != nil else { return }
        userData.removeConference(of: paperID, now: now)
        registerUndo(String(localized: "Remove Conference"), from: paper, undoManager) {
            $0.removeConference(of: paperID, undoManager: undoManager)
        }
    }

    /// Moves a paper to another stage, or marks an item done or not.
    func setStage(_ stage: Paper.Stage, of paperID: UUID, actionName: String, undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }), paper.stage != stage else { return }
        userData.setStage(stage, of: paperID, catalog: catalog, now: now)
        registerUndo(actionName, from: paper, undoManager) {
            $0.setStage(stage, of: paperID, actionName: actionName, undoManager: undoManager)
        }
    }

    func makeMainDeadline(_ id: UUID, of paperID: UUID, undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }), paper.mainDeadline != id else { return }
        userData.makeMainDeadline(id, of: paperID)
        registerUndo(String(localized: "Make Main Deadline"), from: paper, undoManager) {
            $0.makeMainDeadline(id, of: paperID, undoManager: undoManager)
        }
    }

    /// A new deadline of the paper's or the item's own, named `title`, at 23:59 local time on
    /// `day`, or else where a new one goes. Returns its id.
    @discardableResult
    func addDeadline(to paperID: UUID, on day: Day? = nil, title: String = "", undoManager: UndoManager?) -> UUID? {
        guard let paper = userData.papers.first(where: { $0.id == paperID }) else { return nil }
        var deadline =
            day.map { day in
                CustomDeadline(
                    title: "", date: Calendar.gregorianLocal.lastMinute(of: day.startDate()),
                    timeZone: TimeZone.current.identifier)
            } ?? newDeadline(for: paper)
        deadline.title = title
        add(deadline, to: paperID, undoManager)
        return deadline.id
    }

    private func add(_ deadline: CustomDeadline, to paperID: UUID, _ undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }),
            !paper.deadlines.contains(where: { $0.id == deadline.id })
        else { return }
        userData.addDeadline(deadline, to: paperID, now: now)
        registerUndo(String(localized: "Add Deadline"), undoManager) {
            $0.takeBack(deadline.id, aimingAt: paper.mainDeadline, from: paperID, undoManager)
        }
    }

    /// Undoes adding a deadline: takes it out, and aims the paper at what it aimed at before.
    private func takeBack(_ id: UUID, aimingAt main: UUID?, from paperID: UUID, _ undoManager: UndoManager?) {
        guard let (p, index) = indices(of: id, in: \.deadlines, of: paperID) else { return }
        var paper = userData.papers[p]
        let deadline = paper.deadlines.remove(at: index)
        paper.mainDeadline = main
        userData.papers[p] = paper
        registerUndo(String(localized: "Add Deadline"), undoManager) { $0.add(deadline, to: paperID, undoManager) }
    }

    /// Moves an own deadline to Recently Deleted. When the paper aimed at it, it aims at its next
    /// own one, and at this one again when it comes back.
    func deleteDeadline(_ id: UUID, undoManager: UndoManager?) {
        trash([id], String(localized: "Delete Deadline"), undoManager)
    }

    /// Moves an own deadline by whole days of its time zone, keeping its time of day there; its
    /// undo moves it back by as many, keeping what the editor has changed since.
    func moveDeadline(_ id: UUID, byDays days: Int, in paperID: UUID, undoManager: UndoManager?) {
        guard days != 0, let (p, index) = indices(of: id, in: \.deadlines, of: paperID) else { return }
        userData.papers[p].deadlines[index] = userData.papers[p].deadlines[index].moved(byDays: days)
        registerUndo(String(localized: "Move Deadline"), undoManager) {
            $0.moveDeadline(id, byDays: -days, in: paperID, undoManager: undoManager)
        }
    }

    /// Ticks a deadline off or back on: one of its own, or one of its conference's dates. A paper's
    /// main deadline is done by marking the paper submitted, and undone by taking it back to
    /// Writing.
    func setDone(_ isDone: Bool, of deadline: PaperDeadline, in paperID: UUID, undoManager: UndoManager?) {
        guard !deadline.isDoneByStage else { return }
        switch deadline.completion {
        case .submission:
            guard let paper = userData.papers.first(where: { $0.id == paperID }), paper.stage.isSubmitted != isDone
            else { return }
            setStage(
                isDone ? .submitted : .writing, of: paperID,
                actionName: isDone
                    ? String(localized: "Mark as Submitted") : String(localized: "Mark as Not Submitted"),
                undoManager: undoManager)
        case .tick:
            guard deadline.isDone != isDone else { return }
            tick(deadline, isDone, in: paperID, doneActionName(isDone), undoManager)
        case .decision:
            break
        }
    }

    private func tick(
        _ deadline: PaperDeadline, _ isDone: Bool, in paperID: UUID, _ actionName: String, _ undoManager: UndoManager?
    ) {
        userData.setDone(isDone, of: deadline, in: paperID)
        var ticked = deadline
        ticked.isDone = isDone
        registerUndo(actionName, undoManager) { $0.tick(ticked, !isDone, in: paperID, actionName, undoManager) }
    }

    /// Where a new deadline goes: at 23:59 a week after the main deadline while that is ahead, as a
    /// supplementary deadline usually is, or else thirty days from now; in the main deadline's time
    /// zone, or else AoE for a paper and local time for an item.
    private func newDeadline(for paper: Paper) -> CustomDeadline {
        let main = overview(for: paper).deadlines.main
        let zone =
            main.flatMap { DeadlineTimeZone.custom($0.timeZone) == nil ? nil : $0.timeZone }
            ?? (paper.isPaper ? "AoE" : TimeZone.current.identifier)
        let calendar = Calendar.gregorian(in: DeadlineTimeZone.custom(zone) ?? .current)
        let day =
            main?.date.flatMap { $0 > now ? calendar.date(byAdding: .day, value: 7, to: $0) : nil }
            ?? now.addingTimeInterval(30 * 86_400)
        return CustomDeadline(title: "", date: calendar.lastMinute(of: day), timeZone: zone)
    }

    // MARK: Blocks

    /// A block dragged on a timeline: moved, or one of its ends moved.
    func drag(_ block: TimeBlock, _ handle: TimeBlock.Handle, in paperID: UUID, undoManager: UndoManager?) {
        let name = handle == .body ? String(localized: "Move Block") : String(localized: "Resize Block")
        setDays(block.start, block.end, ofBlock: block.id, in: paperID, actionName: name, undoManager: undoManager)
    }

    /// Moves a block, or one of its ends, to other days.
    func setDays(
        _ start: Day, _ end: Day, ofBlock id: UUID, in paperID: UUID, actionName: String, undoManager: UndoManager?
    ) {
        guard let (p, b) = indices(of: id, in: \.blocks, of: paperID) else { return }
        let old = userData.papers[p].blocks[b]
        guard old.start != start || old.end != end else { return }
        userData.papers[p].blocks[b].start = start
        userData.papers[p].blocks[b].end = max(end, start)
        registerUndo(actionName, undoManager) {
            $0.setDays(old.start, old.end, ofBlock: id, in: paperID, actionName: actionName, undoManager: undoManager)
        }
    }

    /// Puts someone on a block, or takes them off it.
    func togglePerson(_ personID: UUID, onBlock id: UUID, in paperID: UUID, undoManager: UndoManager?) {
        guard let (p, b) = indices(of: id, in: \.blocks, of: paperID) else { return }
        if let index = userData.papers[p].blocks[b].people.firstIndex(of: personID) {
            userData.papers[p].blocks[b].people.remove(at: index)
        } else {
            userData.papers[p].blocks[b].people.append(personID)
        }
        registerUndo(String(localized: "Change People"), undoManager) {
            $0.togglePerson(personID, onBlock: id, in: paperID, undoManager: undoManager)
        }
    }

    /// Lets someone hear about a paper or an item in the updates of the others, or no longer.
    func toggleVisibility(to personID: UUID, of paperID: UUID, undoManager: UndoManager?) {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        if let index = userData.papers[p].visibleTo.firstIndex(of: personID) {
            userData.papers[p].visibleTo.remove(at: index)
        } else {
            userData.papers[p].visibleTo.append(personID)
        }
        registerUndo(String(localized: "Change Visibility"), undoManager) {
            $0.toggleVisibility(to: personID, of: paperID, undoManager: undoManager)
        }
    }

    func setDone(_ isDone: Bool, ofBlock id: UUID, in paperID: UUID, undoManager: UndoManager?) {
        setDone(isDone, of: id, in: \.blocks, of: paperID, doneActionName(isDone), undoManager)
    }

    /// Mark as Done on a reminder. It comes from outside any window, so there is nothing to undo it
    /// with; the block, milestone or deadline can be marked not done again where it is. A deadline
    /// is ticked off only while it is still ticked off by itself, as when the reminder offered it:
    /// one the paper has come to be submitted by is not marked submitted from there. At launch it
    /// waits for the conference dates to be read.
    func markDone(_ work: Notifier.Work) {
        guard catalogLoaded else {
            Task {
                await waitForCatalog()
                markDone(work)
            }
            return
        }
        switch work {
        case let .block(id, paperID): setDone(true, ofBlock: id, in: paperID, undoManager: nil)
        case let .milestone(id, paperID): setDone(true, ofMilestone: id, in: paperID, undoManager: nil)
        case let .deadline(id, paperID):
            guard let paper = userData.papers.first(where: { $0.id == paperID }),
                let deadline = overview(for: paper).deadlines.all.first(where: { $0.id == id }),
                deadline.completion == .tick
            else { return }
            setDone(true, of: deadline, in: paperID, undoManager: nil)
        }
    }

    /// The ✓ in the menu bar window: marks the block to work on as done.
    func markCurrentBlockDone(paperID: UUID, undoManager: UndoManager?) {
        guard let paper = userData.papers.first(where: { $0.id == paperID }),
            let block = PlanMath.currentBlock(paper.blocks, today: Day(now))
        else { return }
        setDone(true, ofBlock: block.id, in: paperID, undoManager: undoManager)
    }

    func addBlock(_ block: TimeBlock, to paperID: UUID, undoManager: UndoManager?) {
        insert(block, at: .max, into: \.blocks, of: paperID, String(localized: "Add Block"), undoManager)
    }

    /// Moves a block to Recently Deleted, as the other parts of a paper go too.
    func deleteBlock(_ id: UUID, undoManager: UndoManager?) {
        trash([id], String(localized: "Delete Block"), undoManager)
    }

    /// Puts a paper's blocks in the order of `ids`, as in its list.
    func setBlockOrder(_ ids: [UUID], in paperID: UUID, undoManager: UndoManager?) {
        setOrder(ids, of: \.blocks, in: paperID, String(localized: "Reorder Blocks"), undoManager)
    }

    /// Replaces a paper's plan with the blocks counted back from `deadline`, as Plan Backwards from
    /// Deadline does. Returns whether they fit between today and the deadline.
    @discardableResult
    func planBackwards(_ paperID: UUID, to deadline: Date, undoManager: UndoManager?) -> Bool {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }) else { return false }
        let today = Day(now)
        let plan = PlanMath.backwardPlan(today: today, deadline: Day(deadline), experiments: userData.papers[p].isPaper)
        let before = userData.papers[p].blocks
        userData.papers[p].blocks = plan
        registerUndo(String(localized: "Plan Backwards"), undoManager) {
            $0.swapBlocks(taking: plan.map(\.id), giving: before, of: paperID, undoManager)
        }
        return PlanMath.fits(plan, today: today)
    }

    /// Takes the blocks with `ids` out of a paper's plan and puts `blocks` back at their places, as
    /// Undo and Redo of Plan Backwards do; blocks added meanwhile stay.
    private func swapBlocks(
        taking ids: [UUID], giving blocks: [TimeBlock], of paperID: UUID, _ undoManager: UndoManager?
    ) {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        let taken = userData.papers[p].blocks.filter { ids.contains($0.id) }
        var plan = userData.papers[p].blocks.filter { !ids.contains($0.id) }
        for (index, block) in blocks.enumerated() where !plan.contains(where: { $0.id == block.id }) {
            plan.insert(block, at: min(index, plan.count))
        }
        userData.papers[p].blocks = plan
        registerUndo(String(localized: "Plan Backwards"), undoManager) {
            $0.swapBlocks(taking: blocks.map(\.id), giving: taken, of: paperID, undoManager)
        }
    }

    // MARK: Milestones

    func addMilestone(_ milestone: Milestone, to paperID: UUID, undoManager: UndoManager?) {
        insert(milestone, at: .max, into: \.milestones, of: paperID, String(localized: "Add Milestone"), undoManager)
    }

    func deleteMilestone(_ id: UUID, undoManager: UndoManager?) {
        trash([id], String(localized: "Delete Milestone"), undoManager)
    }

    /// A milestone dragged or moved with the arrow keys to another day.
    func moveMilestone(_ id: UUID, to day: Day, in paperID: UUID, undoManager: UndoManager?) {
        guard let (p, m) = indices(of: id, in: \.milestones, of: paperID) else { return }
        let old = userData.papers[p].milestones[m].day
        guard old != day else { return }
        userData.papers[p].milestones[m].day = day
        registerUndo(String(localized: "Move Milestone"), undoManager) {
            $0.moveMilestone(id, to: old, in: paperID, undoManager: undoManager)
        }
    }

    func setDone(_ isDone: Bool, ofMilestone id: UUID, in paperID: UUID, undoManager: UndoManager?) {
        setDone(isDone, of: id, in: \.milestones, of: paperID, doneActionName(isDone), undoManager)
    }

    // MARK: To-dos

    func addTodo(_ todo: TodoItem, to paperID: UUID, undoManager: UndoManager?) {
        insert(todo, at: .max, into: \.todos, of: paperID, String(localized: "Add To-Do"), undoManager)
    }

    func deleteTodo(_ id: UUID, undoManager: UndoManager?) {
        trash([id], String(localized: "Delete To-Do"), undoManager)
    }

    func setDone(_ isDone: Bool, ofTodo id: UUID, in paperID: UUID, undoManager: UndoManager?) {
        setDone(isDone, of: id, in: \.todos, of: paperID, doneActionName(isDone), undoManager)
    }

    /// Puts a paper's to-dos in the order of `ids`.
    func setTodoOrder(_ ids: [UUID], in paperID: UUID, undoManager: UndoManager?) {
        setOrder(ids, of: \.todos, in: paperID, String(localized: "Move To-Do"), undoManager)
    }

    /// Takes the to-dos that are done off a paper's list; Undo puts each back at its place.
    func clearDoneTodos(in paperID: UUID, undoManager: UndoManager?) {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        let done = userData.papers[p].todos.enumerated().filter(\.element.isDone)
        guard !done.isEmpty else { return }
        userData.papers[p].todos.removeAll(where: \.isDone)
        registerUndo(String(localized: "Clear Done"), undoManager) { store in
            for (index, todo) in done {
                store.insert(todo, at: index, into: \.todos, of: paperID, String(localized: "Clear Done"), nil)
            }
            store.registerUndo(String(localized: "Clear Done"), undoManager) {
                $0.clearDoneTodos(in: paperID, undoManager: undoManager)
            }
        }
    }

    // MARK: A paper's lists

    /// Puts an element into one of a paper's lists, at `index` or at the end, unless it is there
    /// already.
    private func insert<Element: Identifiable<UUID>>(
        _ element: Element, at index: Int, into list: WritableKeyPath<Paper, [Element]>, of paperID: UUID,
        _ actionName: String, _ undoManager: UndoManager?
    ) {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }),
            !userData.papers[p][keyPath: list].contains(where: { $0.id == element.id })
        else { return }
        userData.papers[p][keyPath: list].insert(element, at: min(index, userData.papers[p][keyPath: list].count))
        registerUndo(actionName, undoManager) {
            $0.remove(element.id, from: list, of: paperID, actionName, undoManager)
        }
    }

    private func remove<Element: Identifiable<UUID>>(
        _ id: UUID, from list: WritableKeyPath<Paper, [Element]>, of paperID: UUID, _ actionName: String,
        _ undoManager: UndoManager?
    ) {
        guard let (p, index) = indices(of: id, in: list, of: paperID) else { return }
        let element = userData.papers[p][keyPath: list].remove(at: index)
        registerUndo(actionName, undoManager) {
            $0.insert(element, at: index, into: list, of: paperID, actionName, undoManager)
        }
    }

    /// Puts one of a paper's lists in the order of `ids`; elements not in it go last.
    private func setOrder<Element: Identifiable<UUID>>(
        _ ids: [UUID], of list: WritableKeyPath<Paper, [Element]>, in paperID: UUID, _ actionName: String,
        _ undoManager: UndoManager?
    ) {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }) else { return }
        let before = userData.papers[p][keyPath: list].map(\.id)
        guard ids != before else { return }
        var rest = userData.papers[p][keyPath: list]
        var ordered: [Element] = []
        for id in ids {
            if let index = rest.firstIndex(where: { $0.id == id }) {
                ordered.append(rest.remove(at: index))
            }
        }
        userData.papers[p][keyPath: list] = ordered + rest
        registerUndo(actionName, undoManager) { $0.setOrder(before, of: list, in: paperID, actionName, undoManager) }
    }

    private func setDone<Element: Identifiable<UUID> & Completable>(
        _ isDone: Bool, of id: UUID, in list: WritableKeyPath<Paper, [Element]>, of paperID: UUID,
        _ actionName: String, _ undoManager: UndoManager?
    ) {
        guard let (p, index) = indices(of: id, in: list, of: paperID),
            userData.papers[p][keyPath: list][index].isDone != isDone
        else { return }
        userData.papers[p][keyPath: list][index].isDone = isDone
        registerUndo(actionName, undoManager) {
            $0.setDone(!isDone, of: id, in: list, of: paperID, actionName, undoManager)
        }
    }

    /// What ticking something off or back on is called, in its undo and its redo alike.
    /// Marks an item done, or not done again: the two stages it has.
    func setDone(_ isDone: Bool, ofItem id: UUID, undoManager: UndoManager?) {
        setStage(isDone ? .decided : .idea, of: id, actionName: doneActionName(isDone), undoManager: undoManager)
    }

    private func doneActionName(_ isDone: Bool) -> String {
        isDone ? String(localized: "Mark as Done") : String(localized: "Mark as Not Done")
    }

    private func indices<Element: Identifiable<UUID>>(
        of id: UUID, in list: WritableKeyPath<Paper, [Element]>, of paperID: UUID
    ) -> (paper: Int, element: Int)? {
        guard let p = userData.papers.firstIndex(where: { $0.id == paperID }),
            let index = userData.papers[p][keyPath: list].firstIndex(where: { $0.id == id })
        else { return nil }
        return (p, index)
    }

    // MARK: Undo

    /// Registers the undo of a change that the rules made to a paper's conference, stage or main
    /// deadline: each of those it changed goes back to what it was in `before`, with the ticks and
    /// the own deadlines it let go of, and `redo` makes the change again.
    private func registerUndo(
        _ actionName: String, from before: Paper, _ undoManager: UndoManager?,
        redo: @escaping @MainActor (AppStore) -> Void
    ) {
        guard let after = userData.papers.first(where: { $0.id == before.id }) else { return }
        let dropped = before.deadlines.enumerated().filter { old in
            !after.deadlines.contains { $0.id == old.element.id }
        }
        registerUndo(actionName, undoManager) { store in
            guard let p = store.userData.papers.firstIndex(where: { $0.id == before.id }) else { return }
            var paper = store.userData.papers[p]
            if after.target != before.target { paper.target = before.target }
            if after.stage != before.stage { paper.stage = before.stage }
            if after.mainDeadline != before.mainDeadline { paper.mainDeadline = before.mainDeadline }
            if after.doneDeadlines != before.doneDeadlines { paper.doneDeadlines = before.doneDeadlines }
            for (index, deadline) in dropped {
                paper.deadlines.insert(deadline, at: min(index, paper.deadlines.count))
            }
            store.userData.papers[p] = paper
            store.registerUndo(actionName, undoManager, redo)
        }
    }

    /// Registers `undo` under `actionName`. Running it registers the opposite change in turn,
    /// which is how Redo works.
    private func registerUndo(
        _ actionName: String, _ undoManager: UndoManager?, _ undo: @escaping @MainActor (AppStore) -> Void
    ) {
        guard let undoManager else { return }
        // What Undo and Redo put back slides or fades into place.
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { withMotion(.settle) { undo(store) } }
        }
        undoManager.setActionName(actionName)
    }
}

/// Something in a paper's lists that can be ticked off.
protocol Completable {
    var isDone: Bool { get set }
}

extension TimeBlock: Completable {}
extension Milestone: Completable {}
extension TodoItem: Completable {}

extension Calendar {
    /// 23:59 on the day of `date`, the time deadlines are given for.
    func lastMinute(of date: Date) -> Date {
        self.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
    }
}
