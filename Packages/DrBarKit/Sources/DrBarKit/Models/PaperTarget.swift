import Foundation

extension UserData {
    /// Points a paper or an item at a conference edition, or at another round of it. Its own
    /// deadlines stay, but a new edition is a new attempt: the ticks of the old one go, and so do
    /// the own deadlines that have passed. A paper already submitted keeps to the round nearest now;
    /// a decided one, which is to be submitted again, follows the round to come.
    public mutating func setTarget(_ target: Paper.Target, of paperID: UUID, catalog: ConferenceCatalog, now: Date) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }) else { return }
        let old = papers[p].target
        if old?.series != target.series || old?.year != target.year {
            papers[p].doneDeadlines = []
            papers[p].deadlines.removeAll { $0.date <= now }
        }
        papers[p].target = target
        papers[p].mainDeadline = nil
        if papers[p].isPaper, papers[p].stage == .submitted {
            papers[p].target = target.pinned(in: catalog, at: now)
        }
    }

    /// Takes a paper's or an item's conference away; it aims at its next own deadline ahead, or
    /// else its last, and the conference's ticks go.
    public mutating func removeConference(of paperID: UUID, now: Date) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }) else { return }
        papers[p].target = nil
        papers[p].doneDeadlines = []
        papers[p].mainDeadline = papers[p].ownDeadlineToAimAt(now: now)
    }

    /// Moves a paper to another stage. Submitting fixes the round of its conference, the one whose
    /// paper deadline is nearest now, unless one is fixed already, and so does deciding straight from
    /// before; going back before submission lets go of it, so that the paper follows the round to
    /// come, as one that is to go in again does.
    public mutating func setStage(_ stage: Paper.Stage, of paperID: UUID, catalog: ConferenceCatalog, now: Date) {
        guard let p = papers.firstIndex(where: { $0.id == paperID }) else { return }
        let old = papers[p].stage
        papers[p].stage = stage
        guard papers[p].isPaper, let target = papers[p].target else { return }
        if stage == .submitted || (stage == .decided && !old.isSubmitted) {
            papers[p].target = target.pinned(in: catalog, at: now)
        } else if old.isSubmitted, !stage.isSubmitted {
            papers[p].target?.round = nil
        }
    }

    /// Fixes the round of every submitted paper that has none fixed, as submitting now does, also
    /// in the Archive and Recently Deleted: for papers submitted in earlier builds, or while none of
    /// the rounds had a date. Returns whether any changed.
    @discardableResult
    public mutating func pinSubmittedRounds(in catalog: ConferenceCatalog, now: Date) -> Bool {
        var changed = false
        updateEveryPaper { changed = $0.pinSubmittedRound(in: catalog, at: now) || changed }
        return changed
    }
}

extension Paper {
    /// Fixes the round of a submitted paper that has none; returns whether it did. A decided one is
    /// left as it is: it went in long ago, or it is to go in again.
    mutating func pinSubmittedRound(in catalog: ConferenceCatalog, at now: Date) -> Bool {
        guard isPaper, stage == .submitted, let target, target.round == nil else { return false }
        let pinned = target.pinned(in: catalog, at: now)
        guard pinned != target else { return false }
        self.target = pinned
        return true
    }
}

extension Paper.Target {
    /// The target with its round fixed, as when the paper is submitted: the round whose paper
    /// deadline is nearest to `now`, so that a paper marked submitted a day early or a day late
    /// keeps to the round it went to, also once ccfddl adds another. Unchanged for one fixed already.
    public func pinned(in catalog: ConferenceCatalog, at now: Date) -> Paper.Target {
        guard round == nil, let (_, edition) = catalog.edition(series: series, year: year),
            let nearest = edition.round(nearest: now)
        else { return self }
        return Paper.Target(series: series, year: year, round: nearest.id)
    }
}
