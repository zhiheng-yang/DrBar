# Architecture

DrBar is a sandboxed menu bar app. Almost all logic lives in a local Swift package, so it can be
tested with `swift test` without launching anything.

```
Packages/DrBarKit
├── DrBarKit   models, planning, reminders, storage            Foundation only
├── CCFDDLKit   ccfddl download, cache checks, YAML parsing      DrBarKit + Yams
└── DrBarUI    the bars, rows and axis                          DrBarKit + SwiftUI

App        AppStore, menu bar popover, planner, settings, Notifier, ProgressMail, App Intents
App/Debug  sample data, screenshots, films and a run of Siri's actions; debug builds only
```

## Data flow

```
ccfddl.com/allconf.yml ─┐
ccfddl.com/allacc.yml ──┴─CCFDDLClient (actor)──► allconf.yml, allacc.yml + deadlines.json (catalog)
                                                         │
user.json ◄──UserDataStore──► AppStore (@MainActor) ◄────┘
                                  │
              ┌───────────────────┴───────────────────┐
       popover, planner                     Notifier (reminders)
```

- **Catalog.** `CCFDDLClient` asks ccfddl for new data at most every 12 hours, with `If-None-Match`
  and `If-Modified-Since`. A download replaces the cache only if it parses and lists at least half
  as many conferences with a date it can read as before. `DeadlineParser` turns the YAML into a
  `ConferenceCatalog` (series → editions → rounds) and keeps editions from last year on. Series are
  known by ccfddl's file paths and rounds by their comments, both of which ccfddl changes; after a
  download, `ConferenceCatalog.renames(in:)` finds the new key of each series that moved and what
  each round became, and `UserData.follow(_:in:)` carries the stars, targets, fixed rounds, ticks and
  dates last seen over to the new names. The acceptance rates come
  after it from a second file, asked for in the same way; `withAcceptance` gives each series those
  listed under its key, or, for an entry without a key, under its title where only one series has
  it, and a failed download leaves the rates from before, or the bundled ones. The catalog is saved as
  `deadlines.json`, which is what the app reads at launch.
- **User data.** `user.json` holds stars, papers and the items of the user's own groups (with their
  blocks, milestones, to-dos, email threads, deadlines of their own, the conference dates ticked
  off and who may hear about them), those groups, the groups progress emails go to, settings, the
  Archive, and Recently Deleted: whole papers and items (`DeletedPaper`) and the parts deleted from
  them (`DeletedPart`), which `UserData.delete` and `recover` move back and forth by id; `recover`
  returns what came back, for Undo to `putBack` as it was. An item is a `Paper` with the id of its `ItemGroup`. Every field has a
  default and is decoded leniently, so files from older versions always open; anything that cannot
  be read is reported. `UserDataStore` sets aside a file it could not read in full, copied next to
  it, or moved there if it could not be read at all, and writes what it could read in its place at
  once; one it can do neither with is never written over. Only a file read in full or written by the app becomes
  `user.json.bak`, and the store remembers which file that was, so a save reads it again only if
  something else has changed it. `AppStore` saves half a second after an edit.
- **Derived values.** Rows, a paper's deadlines, its status, what is followed, the reminders to
  schedule, what the Conferences page lists and which other work an update may mention are pure
  functions in `DrBarKit` (`DeadlineRows`, `PaperDeadlines`, `PaperOverview`, `ReminderPlanner`,
  `ChangeDetector`, `TargetChoices`, `UserData.work(visibleTo:…)`).
  `PaperDeadlines` puts together the dates of a paper's conference round, read live from the
  catalog, and its own, and works out which one the plan aims at, which one is flagged, what the
  stage has done and what each block is measured against (`Cutoffs`); nothing of it is stored.
  `AppStore` calls them with the current catalog, data and time.
- **Time.** Deadlines are instants (`Date`), parsed in the conference's own time zone and shown in
  local time. Time blocks are calendar days (`Day`), so a plan does not move when you travel.
- **Navigation.** A `Destination` (the planner, its Conferences page, a paper, a conference
  deadline, or, in notifications of earlier builds, a deadline of the old list) says what to show. Notifications carry one, so that a click opens what they are about, and the
  reminders of blocks, milestones and deadlines also carry what Mark as Done ticks off.

## The time axis

Every bar uses a `TimeAxis`: from a few days before today (about a fourteenth of the range) to a
week or 1, 3 or 6 months after it (`AxisRange`), zoomed and shifted as the user pinches and swipes.
All rows in a list share one axis, so bar lengths can be compared, and what has passed is drawn
faint. `DrBarUI` draws deadline bars (`DeadlineBar`), plans (`PlanBar`), the rows that put a name
column next to them, and the axis labels and grid, whose days and weekends come in with the width of
a day (`TickScale`); the popover and the planner use the same rows, sized by the row size in the
settings (`RowMetrics`). Work without blocks has no row: `DueLane` draws its deadlines on the line
of its group's name, through the same `DeadlineTrack` as a paper's Deadlines row, which then opens
the work on a click and takes its menu and card from the app. The axis is labelled with dates,
with the days from today or with both, as the `axisLabels` environment value says; the app sets
it, with the people on blocks, in `TimelineEnvironment`. Views drawn from the axis in one pass, the grid and the
deadline ticks, interpolate the axis while it glides, so they move with the bars.

The menu bar item (`MenuBarLabel`) is a rounded frame around a symbol, a name and days, whose
thick outline is drawn in a `Canvas` as a clock from the middle of its top edge, by shares of the
way round (`ProgressFrame`, `PlanLoop`): a SwiftUI view rendered twice, with the light and the dark
color scheme, into an `NSImage` whose drawing handler draws the one that matches the appearance it
is drawn in, so that it can have color and still read on any menu bar.

`Motion.swift` names the app's animations and holds `barsGrowIn()`, which grows the bars inside a
view out of today's line when it appears through one environment value, `barGrowth`; the bars
place their ends by it and SwiftUI interpolates their geometry. Hover cards are built from the
model by `HoverCard`'s builders, which return nothing when a card would add nothing, and drawn by
the host of the window (`hoverCardHost()`).

## Editing

Changes to papers and items, groups, blocks and deadlines go through `AppStore+Editing.swift`, where
each one registers its own inverse with the window's `UndoManager`, found by id, so undoing one
change never reverts another; what Undo puts back is animated there, and what Esc puts back in
`DragCancellation`. The rules of a paper's deadlines and stages (choosing a conference,
fixing a round at submission, handing the main deadline over) are in `UserData`, where they are
tested; `AppStore` adds their Undo, turns ticking off a paper's main deadline into marking the paper
submitted, and picks where a new deadline goes. A `PlanBar` given a `BlockEditing` lets its blocks
be dragged and selected, and reports the result, and the view that keeps the selection takes the
keys with `takeKeys()`, as SwiftUI's own focus leaves them with a list or a text field of AppKit;
on a paper's page it also copies and draws blocks, a row per kind of work (`BlockLane`), and `MilestoneEditing` and `DeadlineEditing` do the same for the milestones and
the deadlines in their own rows. `LabelPlacement` puts the deadlines' names beside their flags, so
that none touches another. A drag
held near either end of the bars scrolls the axis (`EdgeScroll`); drags are measured in moments
under the pointer rather than points, so they keep up with it. The arithmetic behind dragging and
reordering is in `DrBarKit` (`TimeBlock.dragged`, `RowMove`, for rows of any height). How far each
timeline is zoomed and moved is an `AxisPosition`, which keeps a zoomed-out axis within a year of
today and ignores a zoom by anything but a positive number; sideways swipes, dragging across empty
space, pinching and scrolling with ⌘ are read in `TimelineGestures.swift`, from the window's events,
and change it there.

## Mail

Threads only stay together when Mail itself replies, because only then are `In-Reply-To` and
`References` set. `ProgressMail` therefore drives Mail through the handlers in
`MailBridge.applescript`, passing everything as parameters, the recipients as lists, one at a
time on a queue of their own so that Mail's answers never hold up the interface. Each paper
keeps one thread per group of recipients, which remembers whether its updates tell of the other work
everyone in the group may see. When the default mail app is not Mail, it opens a prepared draft
instead. Nothing is sent without the user pressing Send.

## Siri and Shortcuts

`App/Intents` holds the App Intents: entities for papers and items, groups and blocks,
whose queries read `AppStore.shared` on the main actor, and intents that change the data through
the store's own methods, without an undo manager. An intent about a block takes its paper or item,
and asks which block in `perform`, so that the block comes after the work in what Siri says; the
blocks' query offers only that work's blocks through parameter dependencies. `DrBarShortcuts`
lists the App Shortcuts with their phrases, translated in `AppShortcuts.xcstrings`; after a save
that changes a title or a name, the store tells Siri the new ones. An intent that needs the
conference dates waits a moment for them when Siri has just launched the app.

## Files

Everything lives in the app's sandbox container: `~/Library/Containers/<bundle ID>/Data/Library/
Application Support/DrBar/` holds `user.json`, `user.json.bak`, `deadlines.json`, `allconf.yml`,
`allacc.yml` and `sync.json`. The progress email's image waits in a hidden folder in Downloads for the moment
Mail needs it and is then removed.
Settings › Data › Remove All Data deletes all of it.
