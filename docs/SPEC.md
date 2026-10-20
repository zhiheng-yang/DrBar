# DrBar — Design Specification

A macOS menu bar app for PhD students: conference deadlines and paper plans on one timeline.

| | |
|---|---|
| Status | v0.1 implemented; this document describes the current design |
| Platform | macOS 14 or later |
| License | MIT |
| Conference data | [ccfddl](https://github.com/ccfddl/ccf-deadlines) (MIT) |

---

## 0. About this document

### 0.1 How to read it

This spec describes what DrBar does and how it is built. It contains three kinds of statements:

- **Fixed rules** (listed in 0.2). They protect users and the project. Change them only by a
  maintainer's decision.
- **Defaults** — everything else: layouts, sizes, colors, library and API choices, file names.
  They are the best current choice. If something turns out to be awkward, wrong or not worth its
  cost, change it and update this spec in the same pull request, saying why in its description.
- **Assumptions**, marked *(V1)*, *(V2)*… Section 12 lists them with what has been checked so far.

### 0.2 Fixed rules

1. **Never present a predicted or previous-year date as an official deadline.** Only dates published
   for the current edition in ccfddl count.
2. **Never send anything on the user's behalf without an explicit click.** Progress emails go out
   only after the user presses Send. No email password is ever stored.
3. **Local-first and private.** Works fully offline, needs no account, has no analytics or
   telemetry. The app's only network traffic is downloading ccfddl data.
4. **Recipients install nothing.** Supervisors and collaborators only receive ordinary emails.
5. **User data is never lost on upgrade.** Data files from every released version keep decoding
   (see 7.2).
6. **Native and lightweight.** Swift and SwiftUI, no web views. Yams is the only third-party
   dependency.
7. **Open source.** MIT license. ccfddl data is credited, and its license ships with the app.
8. **No information by color alone.** Every state also has a length, shape, icon or text.
9. **One self-contained app.** Installing is moving one app to Applications; everything it stores
   stays in its sandbox folder and can be removed from within the app.

---

## 1. Overview

A Gantt-style timeline that shows at a glance how long you have until the next deadline, plus a
few time blocks per paper, so you can see your progress and whether you will make it.

- **Users:** PhD and master's students in computer science and AI.
- **Conference data:** downloaded automatically from ccfddl. Users never type in conference dates.
- **What users maintain themselves:** starred conferences, their papers (with time blocks), and
  groups of their own for other work with a deadline, such as applications, planned the same way.
- **Entry points:** the menu bar (a quick glance), the popover under it (a small Gantt chart of
  deadlines and papers), the planner window (editing), and Siri and Shortcuts (a sentence).
- **Lightweight:** native Swift, one third-party dependency, near-zero CPU and memory use when idle.
- **Progress for supervisors and collaborators:** groups of recipients, one email thread per paper
  with each, and one click sends the latest timeline. Recipients install nothing.
- **Out of scope:** task dependencies, kanban boards, Notion, cloud sync, accounts.

> Similar tools: [CCFBar](https://github.com/superpung/CCFBar), a SwiftBar plugin also based on
> ccfddl, and the [ccfddl Raycast extension](https://www.raycast.com/ViGeng/ccfddl). DrBar differs
> by being a native app (no SwiftBar or Python needed) and by adding paper planning.

---

## 2. Scope changes from the first design

| First design | This spec | Why |
|---|---|---|
| Menu bar countdown | Kept, in a frame whose outline goes round with the time | Core feature |
| Adding conferences by hand | ccfddl data plus deadlines of one's own | The community data covers hundreds of conferences; a paper's own deadlines cover a supplementary, a camera-ready, a workshop or a journal, and groups the rest |
| Several data sources | ccfddl only | Merging sources and resolving conflicts is the hardest part |
| Papers with 12 fields and 10 stages | Essential fields, 5 stages | Students care about where to submit, how far along they are and what comes next |
| Tasks, kanban, dependencies | Time blocks and a short to-do list | A paper is a few stretches of time that you tick off, plus the next small steps |
| Timeline with dragging | Blocks drawn and dragged on the timeline as in Calendar, everything also editable in lists | Moving a plan by hand is what a Gantt chart is for |
| Backward planning | A "plan backwards from deadline" action | One click creates default blocks; the user edits them afterwards |
| Deadline conflict detection | Flag plans that run past the deadline they lead up to, or are overdue | |
| Reminders 30 / 14 / 7 / 3 / 1 days before | 7 / 3 / 1 days by default, plus date-change alerts | |
| Notion, cloud sync, ICS export | Dropped | ccfddl already offers an iCal subscription |
| SwiftData | JSON files | The data is small; JSON needs no migrations, and a backup is a file copy |
| Dashboard window | One planner window | All editing happens there |

---

## 3. Data source: ccfddl

### 3.1 Location

- **Data file:** `https://ccfddl.com/conference/allconf.yml`. One file contains every conference.
  Each entry has a `conference_key` (for example `AI/iclr`) that serves as a stable ID for the series.
  *(V1)*
- **Acceptance rates**: `https://ccfddl.com/conference/allacc.yml`, an entry per conference
  with its title, mostly its `conference_key`, and under `accept_rates` a year each with the rate
  and, mostly, the papers submitted and accepted. A year without a rate takes it from the counts; a
  rate outside 0–1, a year that is not one and a conference without any year are skipped.
- **License:** MIT. Settings › About credits ccfddl and links to its repository, and the license
  text ships with the app.

### 3.2 Format

```yaml
- title: CVPR
  description: IEEE/CVF Conference on Computer Vision and Pattern Recognition
  sub: AI                      # CCF category: AI / CG / DB / DS / NW / SC / SE / CT / HI / MX
  rank: { ccf: A, core: A*, thcpl: A }
  conference_key: AI/cvpr
  confs:
    - year: 2027
      id: cvpr27
      link: https://cvpr.thecvf.com/Conferences/2027
      timeline:
        - abstract_deadline: '2026-11-10 23:59:59'   # optional
          deadline: '2026-11-16 23:59:59'            # required, may be TBD
          rebuttal_deadline: '2027-02-01 23:59:59'   # optional
          decision_deadline: '2027-02-25 23:59:59'   # optional
          comment: First round                       # optional
      timezone: UTC-12
      date: June 20-25, 2027
      place: Seattle, WA, United States
```

### 3.3 Cases that must be handled

1. **`deadline: TBD`** → "Not announced". Never used for the menu bar, reminders or planning.
2. **Several timeline entries in one edition** (rounds, ARR cycles, fast tracks) → one row each,
   told apart by the comment when it is short, by `#n` otherwise. Comments can be whole paragraphs
   and can repeat within an edition. A round is known by its comment, or by its place while it has
   none; ccfddl often writes or rewrites a comment along with new dates, so after a download what
   was kept by a round's old name (the round a paper is fixed to, ticked dates, the dates last seen)
   goes to the round it became: the one with the same comment, else the same paper deadline as
   written, else one closing within a day of it, else the one in the same place, while the rounds
   found so far all moved by as many places, or, with none found, while there are as many rounds as
   before. A date that moved with its round's name is still announced; a round that is gone while
   another took its name takes its ticks and the dates seen for it along. A conference whose
   `conference_key` changes, as when ccfddl moves its file to another category, keeps its star, the
   papers aiming at it and its place in the menu bar, once all its editions are found under one
   other key.
3. **Time zones:** `AoE`, `UTC`, `UTC±N` and `PT` (US Pacific, with daylight saving). Any other value
   is shown as written, marked "unrecognized time zone", and not used for bars or reminders. *(V2)*
4. **`date` and `place` may be `TBD`.**
5. **ccfddl conventions:** without a time ccfddl uses `23:59:59`, without a time zone `AoE`. Every
   deadline's details therefore show both time zones and have an "Open Website" button.
6. **Malformed entries** (a series without a title, an edition without an id, an impossible date)
   are skipped one by one; the rest of the file is used.

7. **`date` is free text** such as `June 20-25, 2027`. The usual forms are read into days to draw
   the meeting; anything else is only shown as written.

### 3.4 Data honesty

- Only dates that ccfddl lists for an edition are shown. The app never predicts dates.
- The details view shows last year's paper deadline in grey ("Last year: Nov 13, 2025") when the
  previous edition was held the year before. This value never feeds the bars, the menu bar,
  planning or reminders.
- The app never edits ccfddl data. If ccfddl is wrong, the user can remove the conference and give
  the paper a deadline of its own until ccfddl is fixed, and report the error upstream.

---

## 4. Features

### 4.1 Menu bar

- Shows the graduation cap and the conference name inside a rounded frame whose thick outline is a
  clock of its own. Time goes round the outline clockwise to the deadline in the middle of
  its top edge. One round is the time from when the work towards it started, the first day of its
  plan or else the day the paper or item was added, and the stretch from now to the top is the
  time left, whole until the work starts; a conference followed on its own goes round in 30 days.
  Its color says how close, as the bars of the timelines do: calm, orange within a week, red within
  three days. Nothing is drawn under the text: the outline goes round it, thick enough to be read
  at a glance.
- **Which deadline:** the nearest deadline ahead that is not done: any date of the conference round
  that a paper or an item of a group aims at, or one of its own, and the abstract or paper deadline
  of each round of the starred conferences that no paper speaks for. With none, only the
  graduation cap is shown, in an empty frame. With 3 days or less left, a red exclamation mark
  takes the symbol's place, which shows without color too.
- **Style (in Settings):** symbol and name (default); symbol, name and days (`35d`, or `5h12m` under
  a day, orange or red once few); two deadlines, the days of each of the next two in a frame of
  its own, each going round in its own time; or the symbol only.
- **What it shows** (in Settings, or Show in Menu Bar in a row's menu): the next deadline of
  everything followed (default), a conference series' next deadline, or one paper or item.
  A paper or item picked for it shows what it is, a page for a paper and its group's symbol for an
  item (4.3), unless 3 days or less are left; its name; and the days left until its next deadline
  (`27d`). Its plan goes round the outline from its first day to the deadline at the top, a stretch
  per block in the block's color, done ones solid and the rest light, with a bead at today, orange
  while work is overdue and red while it runs past its deadline, and a red mark across the outline
  at the deadline, so that what is done, where today is and what is left show at once; blocks that
  run past the deadline go past its mark. Work without blocks has its deadline's countdown. The
  two-deadline style shows the next two deadlines of what is picked. Something picked that is
  deleted falls back to the next deadline.
- **Color**: the item is drawn once for a light menu bar and once for a dark one, and shows
  whichever the menu bar it is on calls for, so that its text always reads, as a template image's
  would.

### 4.2 Popover

The window that opens from the menu bar item, called the popover in this spec: a small Gantt chart,
640 pt wide, laid out like the planner and framed like the system's own menu bar extras:

- **Title and sections:** "DrBar" in bold, then small grey section headers, "Papers", each group
  of the user's own and "Conferences", in the name column. The axis labels sit next to the first. A spinner or an offline
  icon appears next to the title while syncing or offline.
- **Papers** come first, then the items of each group in the sidebar's order: one row per
  paper that is not decided and per item that is not done, and per decided paper while a deadline of
  its own is ahead, such as a camera-ready. Each has one segment per block (solid = done, translucent
  = not done), its milestones as diamonds on the bar's top edge, a red tick through the bar at its
  flag, with a little red flag standing on the bar beside it where the row has room, a quiet tick
  at each of its other deadlines,
  and its conference, the name of its main deadline, when it is due or "Deadline not announced"
  under the title. As in the overview, a block that is wide enough carries its name and the
  monograms of its people, and has a card where it holds more than its bar shows. A paper
  or item carries its deadlines, so what they aim at is not repeated under Conferences.
- **Work without blocks,** which some never needs, has no row: its deadlines stand as flags
  on the line of its group's name, or, for Papers, whose title carries the axis, on a line under it.
  Each flag is named for its work, the one it is marked by in red and the others gray and also named
  by their own name; flags on nearly the same moment stand as one, named for all, or for the first
  and "+2" where there is no room for every name. A red one further ahead than the axis goes, or
  behind it, stands at that edge as an arrow with its name, as does, for work with nothing else to
  show, such as what is done but not yet marked so, its deadline nearest to the axis; work with no
  date yet has an empty gray flag at the right edge. A click on a flag opens its work, its menu is
  the row's, and VoiceOver offers the same; its card is the work's, with what its row used to say
  under the name, or tells when each is due where it stands for several. Its row comes with its
  first block.
- **Row size** (in Settings, and View › Row Size in the planner): large (default), medium or
  small, for the popover and the overview alike. Smaller rows have no line under the name, keep one
  height and share it among blocks on the same days, and leave out the names in the blocks where
  there is no room; the conferences under the work get shorter too.
- **Conferences:** the starred series, sorted by deadline so the bars grow like a staircase;
  not-announced ones last. The bar runs from today to the deadline: up to abstract registration,
  then on to paper submission in a lighter segment. Under papers and groups they are quiet,
  so as not to compete with the work: the name and year in secondary text and a thin bar (5.3).
  With no papers or items they are drawn full size, with the meeting's city and dates (or "Not
  announced") under the name. The ranks and the acceptance rate are in their cards and the details.
- **Nothing followed yet:** with no papers, items or stars, a short welcome asks the user to star the
  conferences they submit to, in the Conferences page of the planner (⌘F). With stars, no papers or
  items and nothing announced ahead, the Conferences section says "No Upcoming Deadlines". No
  conference is shown that the user did not choose.
- **The last few days:** the axis starts shortly before today, so what just happened stays in view,
  faint: a deadline that passed, a block that ended (5.1).
- **Looking back and ahead:** swiping sideways on the trackpad, scrolling sideways, or dragging
  across empty space moves the axis, up to a year either way; ⌘← and ⌘→ step by a day, a week, a
  month or a quarter, as much as what is on screen allows, and ⌘T returns. Deadlines that passed come into the
  list as their day comes into view. Once moved, the axis header shows "‹ Today" or "Today ›" on
  the side where today is, which goes back; a double click on the header does the same. While
  today is out of sight, or no month begins on screen, the header names the month at its left,
  with the year when it is not this one.
- **Zooming:** pinching, or scrolling up and down with ⌘ held, zooms around the pointer, which keeps
  showing the same moment, from three days to two years on screen. Like swiping, it works as soon as
  the pointer is over the bars, before the window has been clicked. A pinch that comes to the chosen
  range stops there for a moment with a light tap of the trackpad, as a pinch in Keynote stops at
  100 %, and goes on once it has gone a little further. ⌘+ and ⌘− zoom around today, and ⌘0
  goes back to the chosen range. Neither end of the axis goes more than a year past the chosen
  range, so however far it is zoomed out, it never leaves everything behind. The labels follow:
  quarters with the year far out, then months, the start of each week, and every day close in, its
  weekday too where there is room, with "Today" over today's own column. The popover opens
  on today and the chosen range again.
- **Editing in place:** a block can be dragged by an end to change it, or by the middle to move it,
  and a paper or item by its name to another place, past a group's title into that group too, as in
  the planner (4.3). ⌘Z undoes.
- **No numbers on rows.** Resting the pointer on a block, a milestone, a paper's or an item's name,
  or a conference shows a card with what it holds that its bar does not show: the people on
  a block, its name where the bar cuts it short, why it is marked late or past its deadline; a
  milestone's day; a paper's conference where its row says something else, what holds it up, who
  works on it, the moments of its next deadlines with the time left and its first open to-dos; a
  conference's name, ranks, latest acceptance rate and every date of its round. A block whose bar
  says it all has none. Clicking a conference opens its details: the bar again with rebuttal,
  notification and the meeting marked, the whole cycle in both time zones, the comment, place, the
  acceptance rate of each of its last six years, website, its papers on DBLP, and last edition.
- **Quick actions:** hovering a paper shows ✓ to mark its current block done. Right-click a row for
  star or unstar, website, open in planner, send progress, archive or delete.
- **Menu rows at the bottom:** Browse Conferences… (⌘F), which opens the Conferences page of the
  planner with its search field ready (4.3), Open Planner…, then Settings… (⌘,) and Quit DrBar
  (⌘Q). Nothing else competes with the bars: work is added in the planner or by asking Siri (4.8),
  the range is set in the planner or Settings, or by zooming, and syncing is automatic.
- **Pages:** a conference's details come in from the right and the list from the left, fading in
  over the last few points of the way, while the page they replace goes at once, so the window
  changes its size only once.
- **Material:** the system's translucent menu material, with no custom glass or background.

### 4.3 Planner window

A single window with a sidebar (Overview, Conferences, Papers, the user's groups) and a content
area; the page that comes in fades in, and the one it replaces goes at once. In the
sidebar, every paper and item has a thin bar under its name, all on one axis, the chosen range
from shortly before today, so whose deadline comes first shows at a glance: its plan, a segment per
block in the block's color, solid when done and translucent when not, with today and its flag
marked. A paper has a page beside its name, an item its group's symbol.

- **Groups**: besides Papers, the user can make groups for other work with a
  deadline, such as applications or reviews, with New Group at the foot of the sidebar or File › New
  Group (⇧⌘N), its name typed in place. A double click on a group's name, or Rename Group in its
  menu, changes it; Icon in its menu picks the symbol its items are shown with, in the sidebar, the
  Archive, Recently Deleted and the menu bar (a calendar to begin with, or a clipboard, magnifying
  glass, envelope, briefcase, desk, trophy, banknote, airplane, people, microphone or book, none of
  them the app's own graduation cap or the to-dos' checklist); Delete Group… sends its items to Recently Deleted, after a question when it has any; + beside
  the name adds an item. Items are planned as papers are: deadlines of their own,
  blocks, milestones, the people on them, to-dos, notes and reminders. They have no stages and send
  no progress: an item is done or not, and a done one leaves the menu bar window. Their plans have
  no row for experiments unless some are drawn, and Plan Backwards leaves them out. In the sidebar,
  a heading dragged elsewhere moves its group with its items, Papers too, and an item dragged into
  another group joins it there; Move To in an item's menu does the same.
  The deadline list of earlier versions becomes a group named Deadlines; a deadline that a paper
  targeted becomes that paper's own.

- **Overview:** one row per paper with blocks, then per item with blocks under the name of its
  group, what it aims at under the title, wide bars (32 pt) with block names inside and the ticks of
  its deadlines; the work without blocks as flags on the line of its group's name, as in the popover;
  then, under "Conferences", the starred conferences, quiet, as in the popover. A row is as tall as
  its blocks need (5.3). In large rows, dragging its lower edge makes the tracks of its bar
  taller or shorter, from 16 to 64 pt, with a resize pointer over the edge; the row keeps that height
  for each track as blocks come to share days or stop sharing them. Dragged back to where it fits the
  blocks, it snaps there with a light tap of the trackpad and fits them again from then on; a double
  click on the edge does the same, Esc puts it back mid-drag, and ⌘Z undoes ("Resize Row"). Medium
  and small rows (View › Row Size) are all one height. Toolbar: ‹ Today › (⌘←, ⌘T, ⌘→) and
  the range, which shows no selection while zoomed to something else. The axis moves and zooms as in
  the popover, and View › Zoom In, Zoom Out and Actual Size do the same. Right-click a paper or item,
  or a flag, to open it, mark an item done, plan it backwards, send a paper's progress, show it in
  the menu bar, archive or delete it.
- **Dragging blocks:** wherever a plan is drawn (the overview, a paper's page, the popover), a
  block's ends change when it starts or ends, and its middle moves it. Blocks move by whole days;
  while dragging, a label above the block shows its days and length, marked when it would run past
  the deadline it leads up to (see Status). The pointer becomes a resize arrow at the ends and a hand
  in the middle, and the trackpad taps lightly when an end lands on today, a deadline or the edge of
  another block. An
  end cut off by the edge of the axis moves the whole block. A drag held near either end of the bars
  scrolls the axis, slowly at first and faster closer to the edge, and the block keeps up, so it can
  be taken past what is on screen; drawing and moving milestones do the same.
- **Selecting elsewhere**: in the overview and the popover too, a click selects a block,
  with its ring; Delete moves it, and only it, to Recently Deleted, ← and → move it a day (with
  Shift, a week), Esc lets it go, and Return or a double click opens its paper's page with the
  block's editor open. Its menu offers Edit, Mark as Done and Delete. A click beside the blocks
  still opens the paper or item.
- **Drawing and selecting** (a paper's page): the plan has a row per kind of work, holding
  as many rounds of it as there are; experiments, writing, internal review and buffer always have a
  row, then each custom name. Dragging across empty days draws a block of the row's kind, with the
  same label, taps and Esc as a drag; a double click on empty days draws a week. Hovering a row's
  name shows +, which adds another round after its last one. A click selects a block, with a ring
  that turns gray when the timeline does not have the focus; a double click or Return opens its
  editor in a popover at the bar; the click takes the keys from the sidebar or a text field that
  had them. With a block selected, Delete or Backspace moves it to Recently Deleted, and
  nothing else, ⌘D adds a copy right after it, ← and → move it a day (with Shift, a week), and Esc
  lets it go. Dragging a block with
  Option held drags a copy. The menu of a block offers Edit, Duplicate, Mark as Done and Delete. On
  this page, dragging empty days draws; the dates above the rows still move the axis.
- **Milestones** (a paper's page): days that something is due by, set by the user, such as
  an internal deadline or a draft for the supervisor, in a row above the work. A milestone is a
  diamond, hollow while ahead, filled once done, edged in orange when its day has passed without it
  being done, with its name beside it while there is room. It is edited as blocks are: double-click
  an empty day or use the + by the row's name to add one, which opens its editor to be named; drag it
  to another day; click to select, double-click or Return to edit; Delete, ← → and Esc as for blocks.
- **Deadlines**: every date of the conference round that a paper or an item aims at
  (abstract registration, paper submission, rebuttal, notification), read live from ccfddl, and any
  number of its own, such as a supplementary, a camera-ready, a workshop or an application's letters,
  each with a free name, a moment in its own time zone, a link and a note. One is the **main
  deadline**, which the plan aims at: the round's paper submission, or else one of its own, the first
  added unless another is made the main one (Make Main Deadline, for a paper before it is submitted);
  one added to a paper already submitted is the main one only if it has passed, as the one the paper
  went in by. The **flag** marks the main deadline until it is done, then the next deadline after it
  that is neither done nor passed; countdowns follow the next deadline of any kind. A deadline is
  done once ticked off (one of its own, the abstract, the rebuttal, or any of an item's) or by the
  stage: Submitted does the main deadline and what came before it, which Not Submitted takes back;
  Decided does the conference's dates; a done item, everything. The notification is never ticked
  off. A paper follows the next round with a date ahead, or, until the conference meets, one not
  announced yet after those that have passed. Marking it Submitted, or Decided straight from before,
  fixes the round whose paper deadline is nearest, also in an edition of one round, so that a round
  ccfddl adds later does not take its place; pointing a submitted paper at another edition does the
  same, while a decided one pointed elsewhere, to be submitted again, follows the round to come
  until it is marked Submitted again. Going back before Submitted lets go of the round, so that the
  paper follows the round to come; a decided paper marked Submitted again keeps its round. A round
  chosen in the target menu stays until another is chosen, also once it has passed.
  On a paper's page they have a row under the work: a flag at each, named
  beside it where there is room ("Abstract", "Paper", or its own name), with a card on hover; the
  flag is red with a dashed line through the work, the others gray, faint once done or passed.
  Deadlines of its own are edited as milestones are: a double click on an empty day of the row adds
  one at 23:59 that day, + by the row's name or the list's adds one where a new one goes, and its
  editor opens to name it; drag it by whole days of its own time zone; click to select, double-click
  or Return to edit; Delete, ← → and Esc as for blocks. A double click on one of the conference's
  shows its details. A list under the milestones has them all in the order they come, each with a
  circle to tick it off; a paper's main deadline's circle marks it submitted.
- **Reordering:** a paper dragged by its name moves to another place, in the overview, the popover
  and the sidebar, into another group when it is dropped there; a group's heading in the sidebar
  moves the group; a block or a to-do in its list likewise. The rows it passes make room, and Esc
  cancels. VoiceOver has Move Up and Move Down.
- **Archive and Recently Deleted**: Archive puts a paper or an item away with all it
  has, out of the timelines, until Move Back; Delete in its menu, or a swipe, moves it to Recently
  Deleted for thirty days, with the days left beside it, until Recover (or a double click), or
  Delete for good, which asks first, as Delete All… does for everything. A block, milestone,
  deadline of its own or to-do that is deleted goes there too, under the name of its paper or item,
  and Recover puts it back at its place, with its paper or item if that was deleted after it; a
  deadline the paper aimed at is aimed at again; Undo of Recover returns it as it was there. The
  Delete key never sends a paper or an item to Recently Deleted: on a page it takes only the block,
  milestone or deadline selected on the timeline or in its list, and in Recently Deleted it deletes
  the selected rows for good, after asking. Both appear at the foot of
  the sidebar while they hold something. Rows swipe as in Mail: right to archive, move back or
  recover, left to delete.
- **Back and Forward:** ‹ and › at the start of the toolbar, View › Back and Forward (⌘[ and ⌘]),
  and the side buttons of a mouse go to the page shown before and back again, as in System
  Settings.
- **Undo:** Edit › Undo (⌘Z) takes back drawing, dragging, copying, reordering, ticking off,
  deleting, archiving and planning backwards, one step at a time, and only that step; what it puts
  back slides or fades into place, as what Esc puts back does. File › New Paper and New Group are
  made in the planner, which opens for them, whichever window is in front, so that its Undo takes
  them back; undoing New Group sends what came into the group meanwhile, as from Siri, to Recently
  Deleted with it, archived items too, and undoing New Paper sends a paper that has had anything
  added to it there too. Undoing Plan Backwards leaves the blocks added since, and undoing Move To
  leaves an item where it is if its group has gone. Importing data clears what Undo and Redo would
  do.
- **Paper:** a large editable title, selected when the paper is new; the target and the stage (Idea
  → Experiments → Writing → Submitted → Decided) as compact menus; the plan, a row per kind of work
  (see Drawing and selecting), with Plan Backwards from Deadline under the empty rows of a paper
  without blocks; the lists of blocks, milestones and deadlines; the to-dos; and folded-away details
  (notes, Overleaf and GitHub links).
- **Target:** a compact menu that shows the conference edition, with its round once one is fixed, or
  else the main deadline's name, or when it is due ("Due Tue 10 Nov"), or "No deadline". It offers
  Choose or Change Conference… (papers only), Round for editions of several rounds, Edit Deadline…
  for the main deadline when there is no conference, Add Deadline… (Set Deadline… while there is
  none) and Remove Conference. A deadline of its own is edited in a popover: name, time zone (local,
  AoE, UTC, UTC±N, PT), date and time, link, note, done, Make Main Deadline and Delete Deadline;
  changing the time zone keeps the wall-clock time. A new one is at 23:59 a week after the main
  deadline while that is ahead, or else thirty days ahead, in the main deadline's time zone, or else
  AoE for a paper and local time for an item. Choosing another edition keeps the deadlines of its own
  that are ahead and lets go of those that have passed and of the old edition's ticks; another round
  keeps everything; Remove Conference aims at the next deadline of its own. Each is one step of Undo.
- **Conferences**: a page of the sidebar with every conference to
  come as ccfddl lists them, a row per edition: the conference, the year, the round of an edition of
  several and the star; the full name; where and when it meets, the place followed by the flag of
  its country where the place makes that clear; the CCF, CORE and TH-CPL ranks, the
  CCF category and the latest acceptance rate as small tags, the papers accepted of those submitted
  on hover; and ccfddl's note on the round. On the right, the time left in large type, orange or red
  as it comes close, over the abstract and paper deadlines in local time, each with the
  conference's own time on hover; "Deadline passed" once they are, or "Not announced" with last
  year's date, also for an edition whose next round is still to be announced after those that have
  passed. They come soonest first, and the sort menu orders them by name, by CCF rank (A
  first, the unranked last) or by acceptance rate (the lowest first, those without one last)
  instead. Above the list, a search, which looks through every conference and also finds past
  editions, All or Starred, where a starred conference with nothing coming shows its last edition,
  and Show past conferences, back to last year's editions; under them, a button for each category
  and for each rank of the three lists, tinted while it is kept to, with Show Everything while they
  leave something out. At first Artificial intelligence and CCF A and B are tinted, with every CORE
  and TH-CPL rank. A list with none tinted keeps nothing out; the buttons are dimmed for Starred and
  a search, which look past them. The buttons are kept with the user's data; the order, Show past
  conferences and the details stay as they were left. Beside the list, the selected edition's
  details: its whole cycle in both time zones, the comment, the acceptance rate of each of its last
  six years as a bar with the papers accepted of those submitted, the website and DBLP; the button
  in the toolbar hides and shows them while the window has room for them beside the list. ↓ and ↑ go through the list from the search field, Return or
  a double click opens the website, and Esc clears the search. A row's menu stars or unstars the
  series, opens its website or its papers on DBLP. Stars apply to a series, so next year's edition
  is followed automatically.
- **Choosing a conference:** Choose Conference… opens the same list in a sheet, with the paper's
  target selected and its details beside it; Return, a double click or Choose takes the selected
  row, and Esc cancels. Only papers choose a conference; an item has deadlines of its own.
- **Blocks:** each row shows the color, name, dates, length and a done circle. Clicking a row opens
  a popover to change the kind or name, the dates (the end can never be before the start), done, the
  order, or to delete, and selects the block on the timeline; the block selected there is marked in
  the list. A new block from + opens its editor at once. Blocks may overlap: wherever a plan is
  drawn, blocks on the same days share the bar's height, one above the other, their names in a
  smaller size (5.3). A block that ended without being done keeps its color, edged in orange, and
  its dates in the list are orange.
- **Who works on a block**: a block can name people from the recipient groups, such as the
  supervisor on the internal review or a co-author on a round of experiments, in its editor (With)
  or its menu. They show as small monograms in the block's own color at the end of the block, in the
  popover, the overview, on a paper's page and in the email image, where there is room, beside its
  name in the list, in its card, and in the email. A block without people is the user's own
  work.
- **Visible To**: in the toolbar of a paper's or an item's page, and in its menu in the
  sidebar, the people of the recipient groups who have an address, under their groups, each ticked
  on their own. Nobody is ticked at first, which keeps the work to the user; `person.2` turns into
  `person.2.fill` once someone may see it. The updates of the other papers can then tell everyone
  they go to about it, if all of them are ticked (4.7). ⌘Z undoes ("Change Visibility").
- **Milestones:** in the order of their days, each with its diamond, name, day and a done circle;
  clicking one opens its editor (name, date, done, delete) and selects it on the timeline.
- **Plan backwards from the deadline:** counting back from the main deadline: buffer 2 days, internal
  review 7 days, writing 14 days, experiments from today until writing starts. If the first block
  would start before today, the paper's page says "Not enough time — please adjust by hand.", and
  opens to say so when the plan was made from the overview. Replacing an existing
  plan asks first. Blocks are never moved automatically afterwards; if ccfddl moves the deadline,
  the paper shows a conflict.
- **To-dos:** a short checklist per paper. Tick the circle when done, click a to-do to edit it in
  place, with the caret where the click was, drag it to another place, type into the last line to
  add one; a to-do left empty is removed, and Clear Done removes the finished ones. The first open
  to-dos appear in the hover card of the paper's name.
- **Status:** "behind" (a block or milestone that is not done is overdue) and "conflict" (work runs
  past the deadline it leads up to) appear as icons and text. Each block leads up to
  the first deadline on or after its start among those the plan is measured against: while the main
  deadline is open, it and the open deadlines of its own after it, and work after the last of them
  runs past too; once it is done, the open deadlines after it but the notification, the rebuttal
  among them, and only work across one of them runs past it.
- **Send Progress** is in a paper's toolbar, with "Last sent 3 days ago". See 4.7.

### 4.4 Automatic updates

- **When:** at launch, every 12 hours, on Sync Now, and after waking or reconnecting if the last sync
  is more than 12 hours old. After a failure, the app waits 15 minutes before trying on its own,
  unless the network has just come back.
- Requests send `If-None-Match` and `If-Modified-Since`; `304 Not Modified` downloads nothing. *(V1)*
- The acceptance rates are asked for after the conferences, in the same way. When they cannot be
  had, the conferences come with the rates from before, or the bundled ones.
- Requests identify the app with a `User-Agent` such as `DrBar/0.1.0 (+https://github.com/zhiheng-yang/DrBar)`.
- **Validate before replacing:** a download replaces the cache only if it parses and lists at least
  half as many conferences with a date it can read as before; the acceptance rates replace theirs if they parse and list
  any.
- First launch without network: the snapshot bundled with the app, conferences and acceptance rates,
  is used (refreshed weekly by CI).
- Everything keeps working offline.

### 4.5 Reminders

- **For:** every deadline of the papers and items that is ahead and not done, except the
  notification, once each, and the abstract and paper deadlines of the starred conferences' rounds
  that no paper speaks for. A reminder of a deadline that one paper or item has open opens
  it, and offers Mark as Done when the deadline is ticked off by itself.
- **Lead times:** 7, 3 and 1 days by default; 30 and 14 can be added. They are days on the
  calendar: a week before comes at the deadline's time of day, also across a change of the clocks.
- **Block reminders:** at 9:00 on the last day of a block that is not done, and on the day of a
  milestone that is not done. These notifications offer Mark as Done, as Reminders does, which ticks
  the block or the milestone off without opening anything.
- **Date-change alerts:** after each sync, the raw text of every followed date is compared with what
  was seen before; any change is announced, e.g. "ICLR 2027: Paper submission changed" with
  "09-25 → 10-01 (AoE)".
  TBD → a date counts too. A change the alert would show as no change, such as of the seconds, is
  recorded without one, and so are the dates of what is followed anew.
- macOS keeps at most 64 pending notifications per app, so after every sync or edit the app replaces
  all pending ones with the next 60, whenever one of them would fire at another moment, read
  otherwise or offer something else. IDs are the object plus the fire time. Mark as Done on a
  deadline's notification ticks it off only while it is still ticked off by itself. *(V11)*
- Permission is asked when the user first turns reminders on, never at launch, unless reminders
  are on in data from elsewhere (an import, another Mac) and this Mac has never been asked; refused,
  reminders are turned off. Reminders that could not be added, as while notifications are off, are
  added again on the next pass, and coming back to the app makes one.

### 4.6 Settings

- General: appearance (System, Light or Dark), the default range, what the axis is labelled with
  (dates, the days from today or both, as two checkboxes, 5.1) and the row size (large, medium or
  small, 4.2), the menu bar style and what it shows, open at login. The conference filters are on the Conferences page itself.
- Reminders: on/off (asks for permission), lead times, block reminders, date-change alerts; a link to
  System Settings when notifications are off.
- Email: your name (signature) and the address to send from; then the groups of recipients,
  Supervisors and Collaborators to begin with and any of your own, each with its people (a name and
  an address, as many as needed), its email language and whether buffer blocks are left out. A
  group of your own has a name; any group can be deleted from its ⋯ menu, after a question when it
  has people or threads, also of archived or deleted work, which all forget it. Rows left empty are removed. The same people can be put on blocks and may
  see other work; someone removed here leaves the blocks and what they could see too.
- Data: sync status and Sync Now; show the data folder; export and import `user.json`; Remove All
  Data, which quits; if the data folder cannot be removed in full, what is open is written back and
  the app keeps running.
- About: version, links, ccfddl credit, third-party notices.

### 4.7 Progress for supervisors and collaborators

The people who follow a paper are in groups: Supervisors and Collaborators to begin with, and any
group of the user's own (4.6). A paper has one email thread with each group it has written to; Send
Progress replies in the thread with the chosen group, with a short message and the paper's latest
timeline as an image. Only papers send progress; the items of other groups do not.

1. The send sheet starts with the group it goes to (the one the paper last wrote to, otherwise the
   first with an address) and its people's names, then shows the image that will be sent, the
   subject, the email's first line, a message field (may stay empty), "Include progress summary" (on
   by default, previewed in grey), "Include other work" while some other paper or item is visible to
   everyone it goes to (off until it is ticked, then as the thread's last update had it, previewed in
   grey), Cancel and Send. On a small screen the middle scrolls. A group without an address says so
   and opens Settings › Email. While it sends, the sheet can be neither cancelled nor sent again,
   and stays on the planner whatever page it goes to.
2. The first time for a paper and a group there is a subject field (default `Progress: <title>`);
   every later update to that group is a reply (`Re: Progress: …`), so each group sees one thread.
3. Every subject ends with the stage under way and the time left until the paper's next deadline,
   in whole days rounded down, so it never reads as more time than there is: `Progress: Efficient
   Video Diffusion (Writing · 29 days to the CVPR 2027 abstract deadline)`. Mail keeps the thread by
   its headers; clients that also compare subjects, such as Gmail, may show an update with a new
   count as a new conversation.
5. The first line says what the update is about, so that the inbox's preview tells it before it is
   opened: first what the recipients take part in, while it is under way or starts within
   two weeks ("Internal review with you starts on 31 Oct."); then how the plan stands, when it is
   behind or past the deadline, or else the stage under way ("On track: Writing until 30 Oct.");
   then what has changed since the group's last update ("Since 10 Oct: Experiments done, Writing
   started.").
4. The recipients are always the group's people as they are now, even though a reply to your own
   email would be addressed to you; someone added to a group gets the next update in its thread.
   The sender is the address set in Settings, or Mail's default account.

**Email content** (plain text and one image):

```
On track: Writing until 7 Nov. Since 20 Oct: Experiments done, Writing started.

<your message>

Target: CVPR 2027 — paper deadline 16 Nov, 23:59 (UTC-12)
Done: Experiments (12 Oct – 24 Oct)
Now: Writing (25 Oct – 7 Nov)
Next: Internal review (8 Nov – 14 Nov, with Prof. Jane Doe)
Due: Full draft to Jane (1 Nov)

Also working on:
RL Benchmark Suite (ICAPS 2027) — Experiments until 5 Nov · abstract deadline 7 Dec
Doctoral Fellowship — Research proposal until 28 Oct · deadline 9 Nov

<your name>

[image: banner and timeline]
```

- The summary lists the target, the last finished block, the blocks in progress, the next one and
  the next milestone (`Due:`), each block with the people on it (`Internal review (31 Oct – 7 Nov,
  with Prof. Jane Doe)`). The target line runs from the next deadline to the main one, each in its
  own time zone; after submission it says "submitted" and names the flag, such as the supplementary
  or the rebuttal.
- The image, 560 pt wide on a light background, opens with a banner: the days left in large type
  with what they count down to, the paper's title, the stage under way or next, a chip with how the
  plan stands (on track, behind, past the deadline) and the share of the plan done. The banner takes
  the color of the stage, and orange in the last week and red in the last three days, so that each
  update looks different from the one before at first glance. Below it, the plan: one row per kind
  of work, the milestones above them, the deadlines below them and today. The flag is named with its
  venue ("CVPR 2027 paper deadline"), and the flags too close to leave it room are left out. Buffer
  blocks are left out for supervisors by default and kept for collaborators, and how the plan stands
  is judged without them.
- **Other work**, when included: the papers and items still under way that every recipient
  is ticked for, in the sidebar's order, never the paper itself, untitled work, the Archive or
  Recently Deleted. A line each: the title with its conference, the block under way ("until") or the
  next one ("from"), or "submitted" and "decided", and the next deadline on its day in its own time
  zone. In the image, under the plan, "Also working on" and a quiet 30 pt row each with an 8 pt bar
  of its blocks and its flag, without names, for the work that is on the image's axis. Nothing else
  of it goes out: its notes, to-dos, milestones, links and the people on its blocks stay on the Mac.
- **Language:** English (default) or Chinese per group, for the summary and the image only.
  Deadlines are written in their own time zone, because the recipients' is unknown.
- **Record:** each paper stores, per group, the thread subject, the Message-ID of the first email,
  the time of the last update and whether it told of other work. Deleting a group forgets its
  threads.
- **Not included:** calendar invitations, scheduled sending, Cc and Bcc.

### 4.8 Siri and Shortcuts

DrBar's actions are App Intents, so Siri, Spotlight and the Shortcuts app offer them
without any setting up, and Siri with Apple Intelligence understands them said in a sentence. Each
phrase names the app, in English or Chinese, and Siri asks for what it leaves out:

| Action | Phrase, for example | What it does |
|---|---|---|
| Add a paper or item | "Add to Reviews in DrBar", "Add a new item in DrBar" | A paper, or an item of a group, with its title and the day it is due, at 23:59 local time; it is not opened |
| Add a deadline | "Add a deadline to JCC in DrBar" | A deadline of its own on a day, with a name if one is given |
| Add a block | "Add a block to Video Diffusion in DrBar", "Plan writing in DrBar" | A block of a kind of work, or of a name of the user's own, from a day for some days (a week unless told) |
| Move a block | "Move a block of Video Diffusion in DrBar", "Postpone…", "Bring forward…" | To start on another day, keeping its length |
| Change when a block ends | "Extend a block of Video Diffusion in DrBar", "Shorten…" | To end on another day, not before it starts |
| Mark a block as done | "Mark a block of Video Diffusion as done in DrBar" | Ticks it off |
| Next deadline | "What's next in DrBar" | Says the next deadline, its moment and the time left |
| Open | "Open JCC in DrBar" | Opens the paper or item in the planner |

Papers and items are known by their titles and groups by their names; Siri hears the new ones after
each save, and also takes "Dr Bar" and "Doctor Bar" for the app. Every plan has blocks of the same names, so a
phrase names the paper or item, and Siri then asks which of its blocks not done yet is meant,
unless only one is. What Siri leaves out it asks for in a question of its own, such as "When is it
due?". What is done this way cannot be undone with ⌘Z, as there is no window to undo it in, but is
plain on the timelines at once. Archived and deleted work is not offered, and nothing is deleted
this way. Remove All Data also makes the system forget what it learned from these actions.

---

## 5. Visual design: time as bars

### 5.1 One shared time axis

- On the timelines, time is shown one way: **the length of a bar**. There are no countdown numbers
  next to bars; only the Conferences page, which reads as ccfddl's site does, writes the time left.
- All rows of a list share one axis, from shortly before today to a week or 1, 3 or 6 months after
  today (3 months by default), so bars can be compared:
  - **Conference rows:** the bar runs from today to the deadline; shorter means sooner.
  - **Paper rows:** the plan, with a red tick at its flag and quiet ones at its other deadlines.
    Together a small Gantt chart.
  - **The last few days:** 1 in the week view, 2 in the 1-month view, 7 in the 3-month view, 14 in
    the 6-month view, about a fourteenth of the axis. A deadline that passed shows as a faint bar of that length
    ending at it, and blocks that have ended are faint, so you see the step you just took. Lists
    include such rows while they are on the axis.
- The axis can be moved by up to a year either way to look back or ahead, and zoomed to show from
  three days to two years (4.2); every row of the list moves and zooms with it. Zoomed out, it stays
  within that year, so today stays on screen.
- The planner's sidebar draws its small bars on the same axis, unmoved and unzoomed, so they can
  be compared too.
- **Days from today**: in Settings, or from the menu of the dates above any timeline, the
  axes can be labelled with how far each line is from today instead of its date: "Today", then "+7",
  "+14", "+21"…, and "−7" behind; the sign tells them from the days of the month without a unit to
  read. The labels come every day, week or few weeks as there is room, always on the same day of the
  week as today, every fourth week a little less quiet, and the lines of weeks and months count from
  today too; dragging a block or a milestone shows its days the same way. Every label tells its date
  on hover. Dates and days are two checkboxes, either or both: with both, each date has its days
  from today on a second line under it, and a drag shows both. One of them always stays on. The
  email image always shows dates, since the recipients read it on another day.
- **Days, as the work counts them**: as days get wider, each gets a faint line of its own
  and the weekends a faint band, a little stronger as there is room, so the days left can be counted
  on the bars; close in, each day is labelled with its weekday and number in the middle of its
  column, and "Today" stands over today's.
- Exact dates and times appear in the hover cards, the details view and VoiceOver; the days
  of blocks and milestones are read off the axis, and show exactly while one is dragged and in a
  paper's lists. An AoE deadline may be the next afternoon in local time, so the details always show
  both.
- Users who want numbers can switch the menu bar to the style with the days.

> **Limits of a linear axis:** in the 3-month view a day is about 4 pt wide in the popover, so two
> deadlines a day apart look almost the same. Deadlines within 7 days are therefore also orange or
> red, and there are a 1-month and a week view. There is no logarithmic scale: bar length would stop being
> proportional to time. *(V4)*

### 5.2 Principles

1. **The bars are the hero.** They are the largest, calmest element on screen; controls stay behind
   one menu or in the planner and Settings.
2. **Each surface answers one question.** Menu bar: how long? Popover: what's next? Planner: will I
   make it?
3. **Color carries meaning, never decoration.** Mostly grey, the accent follows the system, red and
   orange mean "urgent" or "conflict".
4. **Native first.** System materials, SF Symbols, system controls. The bars are the one custom
   control, but for the filter buttons of the Conferences page, which are tinted while chosen, as
   tags are.

### 5.3 Design tokens

| Area | Rule |
|---|---|
| Popover | 640 pt wide, 18 pt margins, the list up to 600 pt tall, then it scrolls |
| Popover rows | 44 pt high with no spacing: a 168 pt name column (body, medium weight; year and round secondary; the meeting or the state below in tertiary caption) and the bar beside it; hover shows a rounded `.fill.quaternary` highlight; a row being dragged lifts onto the window background with a soft shadow. A group's name has an 18 pt line, which holds the flags of its work without blocks, here and in the overview |
| Row sizes | Large: popover rows 44 pt with 24 pt bars, overview rows 64 pt with 32 pt bars, quiet conferences 30 pt with 8 pt bars. Medium: 30/14, 40/20 and 24/7 pt. Small: 20/8, 24/10 and 20/6 pt. Medium and small rows have no line under the name, and their blocks on the same days share the bar's height in thinner tracks, 2 pt apart while each keeps 6 pt, then 1 pt, then touching, and never thinner than 0.5 pt |
| Popover chrome | Bold title, 11 pt semibold grey section headers in the name column, menu rows 24 pt high with the shortcut in tertiary on the right, inset separators |
| Bar shape | Every bar and block is a rounded rectangle with a corner radius of 40 % of its height, the same at every length; never a capsule. A block taller than its bar's usual height, standing for several tracks, keeps the corners of a bar of that height, and a block narrower than it is high takes 40 % of its width |
| Conference bars | 24 pt, or 8 pt in 30 pt rows under papers and groups, without the chevron: today → registration, then a lighter one → submission; minimum 20 pt; a white `›` when the deadline is beyond the range; in the details, a ring, a dot and a faint segment for rebuttal, notification and the meeting; a dashed outline from today when not announced |
| Plan bars | 24 pt in the popover and the email image, 30 pt on a paper's page, 32 pt with names in the overview; 2 pt between blocks; a tick at each deadline on the axis, the flag's red, 2 pt wide and 8 pt longer than the bar, the others 1.5 pt and 4 pt longer in the secondary color (primary at 60 % with Increase Contrast), faint once done or passed; of ticks closer than 3 pt only the strongest shows, ticks are cut 1.5 pt around milestone diamonds, and names and people keep 3 pt clear of them. Where the row leaves 7 pt or more above the bar, a red flag stands on the bar's top edge beside the flag's tick, up to 9 pt tall (1 pt less than the room), its cloth waving a little as in the Deadlines rows: just before the tick, the cloth toward it, 1.5 pt away, or just after it, turned round, at the start of the bar or where a diamond stands, so that the tick and the flag's pole never make one long pole; it has the deadline's card. Without the room the tick stands alone. On a paper's page and in the email image, a row per kind of work. Blocks on the same days share the bar, a track each with 2 pt between them, as events at the same time share a day in Calendar, and the bar and its row grow so that each track keeps 22 pt, enough for its name and people; a block that overlaps nothing keeps the whole height. In the overview, the user can set each paper's tracks from 16 to 64 pt. Names inside are 10 pt, and smaller with a thinner track, down to 9 pt; below that, or where a name is cut short, its card names it. A block that ended without being done keeps its translucent fill with a 1.5 pt orange edge. A selected block has a 2 pt ring 3 pt outside it, in the accent color while the timeline has the focus and gray otherwise |
| People | Monograms (initials, one character for Chinese, Japanese and Korean names) in white on circles of the block's own color, with a thin ring of the window's background, overlapping by a quarter, at most three with "+N" in the last. Inside the end of the block, as tall as the bar less 9 pt and at most 16 pt, only where that is at least 13 pt and the block is wide enough: in the popover, the overview, on a paper's page and in the email image; 16 pt beside the name in the block list |
| Milestones | Diamonds in the color of the work they fall in (the block on their day, else the last one before, else the first after; buffers passed over; without any work, blue, indigo, teal, mint, cyan and purple in the order of their days): translucent with a solid edge while ahead, solid once done (faint once over), an orange edge when overdue; 11 pt in the milestone row with the name in a secondary caption beside it, up to the next diamond; half the bar's height on a paper's bar in the popover and the overview, with a hover card |
| Sidebar bars | 5 pt on the shared axis, overlapping blocks in tracks 1 pt apart; today an accent tick and the flag a red tick, 1.5 pt wide, standing 2 pt out of the bar |
| Deadlines | On a paper's page and in the email image, a 30 pt row under the work: a 9 pt `flag.fill` at each deadline with its name in a caption beside it, after it or else before it, shortened with "…" down to 36 pt or left out, never touching another name or flag. The flag's name is placed first, in red, and may come within 3 pt of the next flag; the others keep 6 pt. Flags closer than a flag is wide stand as one, named for all; at the right edge a flag faces back. A dashed red line (1.5 pt, 75 %) runs through the work at the flag, ending with the work as today's line does, so that the flag below stands clear of it, and block names keep clear of it; a hovered deadline shows a gray one. In the image, flags in the way of the flag's name are left out. On a group's line, a flag is named by the title of each piece of work on it, followed by the names of its other deadlines there; a flag of several pieces of work without room for every name takes the first one's, shortened if need be, and "+N", which is never cut; a red flag beyond either end of the axis stands at that edge as a 9 pt `chevron.right` or `chevron.left`, named as a flag, work with nothing else on the axis by its deadline nearest to it, the same way, and work with no date as a tertiary `flag` at the right edge |
| The past | Deadlines that have passed and blocks that ended done, at 25 % opacity |
| Today | A continuous 1.5 pt accent line through each list, labelled "Today"; a bar shown on its own (details) gets a short tick |
| Ticks | Chosen by how wide a day is drawn. Months get secondary labels and faint lines; past about 1 pt a day, quarters do, with the year at January. Weeks get fainter lines from 10 pt a week and the day they start on as a tertiary label from 26 pt. Days get lines that come in from 8 pt a day and are full from 20 pt, and weekends a band that comes in from 6 pt and is full from 10 pt, everywhere a timeline is drawn; from 20 pt a day each day's number is centered in its column, with its weekday where the widest weekday fits with room to spare, and "Today" is centered over today's column. In the days view, the lines of weeks and months count from today. With both dates and days, each date label has its days from today under it in the tertiary color, and the header is 26 pt tall instead of 14. While today is out of sight, or no month begins on screen, the month at the left is named, with the year when it is not this one |
| Hover cards | Drawn as the system draws a popover, without its arrow: thick material, 10 pt continuous corners, a hairline edge (35 % with Increase Contrast) and the lifted-row shadow; 12 × 9 pt padding, as wide as its content up to 340 pt. The name in body semibold over subheadline lines: times in primary, the rest secondary, the least important tertiary, orange and red only where the bars use them. Several dates line up in columns (name, moment, time left), where only the name is cut short. A card comes after 0.7 s of rest, at once within 0.5 s of the last one, fades in over 0.12 s (not with Reduce Motion), and goes with a click, a key, a scroll or a pinch, never taking the focus or a click |
| Dragging | The label above a dragged or drawn block: caption, monospaced digits, on a material capsule; the resize arrow at a block's ends, the open and closed hand in its middle and on the flag of a deadline of its own, the copy arrow with Option; a light haptic tap at today, the deadlines and the edges of other blocks |
| Type | System font, text styles rather than fixed sizes; primary, secondary, tertiary |

**Conference bar colors** (by time left)

| Time left | Color | In the menu bar frame |
|---|---|---|
| More than 30 days | Calm color at 50 % | `graduationcap.fill`, or the symbol of the picked work |
| 8 – 30 days | Calm color | The same |
| 4 – 7 days | Orange | The same |
| 3 days or less | Red | `exclamationmark`, red |

The calm color is the system accent, or blue when the user's accent is red or orange.

**Block colors** (system colors, adapting to dark mode; red and orange are never used for blocks)

| Block kind | Color |
|---|---|
| Experiments | `.blue` |
| Writing | `.indigo` |
| Internal review | `.teal` |
| Buffer | `.gray` |
| Custom | One of `.mint`, `.cyan`, `.purple`, `.brown`, fixed per name |

Finished blocks are solid; unfinished blocks are translucent (42 %). With Increase Contrast,
unfinished blocks also get an outline.

**Motion** (with Reduce Motion, nothing moves and pages only fade): every animation plays
once, in answer to the user or to a new day, and is one of five: glide, settle, make room, drop and
page.

- **Bars grow in:** whenever a timeline comes into view (the menu bar window opening, its list
  coming back, a conference's details, the planner's sidebar, the overview, a paper's page and a
  plan made backwards on it), its bars grow out of today's line, all together and in proportion, so they can be
  compared at every moment, with the glide of going back to today. What marks a moment stays where
  it is: the grid, the labels, today, the ticks and flags of deadlines, milestones, and a
  conference's rebuttal, notification and meeting.
- **Glide:** going back to today, ⌘← and ⌘→, zooming, the range and a new day move the whole
  timeline together, frame by frame, so that the bars, ticks, flags, diamonds and the flag's dashed
  line slide across the edges with the grid; a change of range or zoom goes evenly in scale around
  today, as much at its start as at its end; a selected block, milestone or deadline slides a day
  with the arrow keys.
- **Pages** fade in, in the menu bar window over the last 12 pt from the side they come from; the
  page they replace goes at once.
- **Settle:** rows that come or go (archive, delete, recover, star or unstar, a new paper, group or
  to-do, the conferences a filter button or Show Everything lets through), blocks, milestones and
  deadlines deleted or duplicated, the details beside the conference list, and what Undo, Redo and
  Esc put back.
- **Make room** and **drop:** rows step aside for a dragged row, and it drops into its place.
- **Ticking off** fades the fill to solid and the check mark bounces once.
- Never animated: drags, drawing, swipes and pinches, which follow the pointer; the menu bar item and
  the email image; hover highlights and the selection ring; search filtering and the minute tick.

**Liquid Glass:** built with Xcode 26, toolbars, sidebars and system buttons adopt it automatically.
No glass on bars or lists.

### 5.4 Menu bar

```
[🎓 CVPR]            symbol and name; the brackets are the frame
[🎓 CVPR · 12d]      symbol, name and days
[12d] [26d]          two deadlines
[🎓]                 symbol only
[📄 Effici… 27d]     a picked paper or item, its plan round the outline
```

- The frame is 22 pt tall and as wide as what it holds: a rounded rectangle with continuous
  corners of 40 % of its height, as the bars have, its outline 3.5 pt wide, the track the text
  color at 16 % (30 % with Increase Contrast). Inside, 4 pt clear of the outline (3.5 pt around the
  symbol alone, which makes it at least 22 pt wide), the symbol at 11 pt semibold and the name and
  days at 12 pt medium, in the text color. Stretches have round ends; the way round starts and ends
  in the middle of the top edge, where the deadline is.
- A deadline's stretch runs from now to the top, its length the share left of the time from when
  its work started (`FollowedDeadline.shareLeft`), whole until then and of 30 days for a
  conference followed on its own, in the color of how close it is (`Urgency`). Two frames stand
  4 pt apart.
- A plan runs round from its first day to its deadline, or to its last block when that is later: a
  stretch per block, in the block's color, solid when done and at 40 % when not, its ends drawn in
  by its round cap and a little gap, so that blocks stay apart. The outline holds one block at a
  time: on days that blocks share, the one that starts later takes the earlier one's place, which
  shows again where it outlasts it (`PlanMath.visibleParts`); a 1.8 pt red mark across the
  outline at the deadline; and at today a bead, 0.4 pt wider than the outline, in the text color,
  orange while behind or red on a conflict, set off by a clear gap.
- `MenuBarExtra` labels only take text and images, so the frame and what it holds are rendered into
  one image, once with the light and once with the dark scheme, re-rendered only when something
  visible changes, as the stretches are kept to 1/720 of the way round and today to the hour. The
  image draws the one that matches the appearance it is drawn in. *(V3)*
- Names longer than 7 characters are shortened, to keep the item narrow next to the notch.

### 5.5 Popover

```
┌──────────────────────────────────────────────────────────────┐
│ DrBar                                                       │
│ Papers              Today  25  Nov  8  15  Dec  13  20  Jan  │
│ Efficient Video Di…░░│▓▓▓▓▓▓▓▓░░░░░▒▒|                       │
│ CVPR 2027            │                                       │
│ Applications                      Visiting Researcher ⚑      │
│ Doctoral Fellowship  │▒▒▒▒▒▒ ▒▒▒ ░░|                         │
│ Due Tue, Nov 10      │                                       │
│ Reviews                 ICLR 2027 reviews +1 ⚑  ⚑ TPAMI      │
│ Conferences          │                                       │
│ ALT 2027           ━ │                                       │
│ CVPR 2027            │━━━━━━━━━━━━───                        │
│ COLT 2027            │┄┄                                     │
│ ──────────────────────────────────────────────────────────── │
│ Browse Conferences…                                      ⌘F  │
│ Open Planner…                                                │
│ ──────────────────────────────────────────────────────────── │
│ Settings…                                                ⌘,  │
│ Quit DrBar                                              ⌘Q  │
└──────────────────────────────────────────────────────────────┘
```

Without papers or items, the list starts with Conferences, full size. With nothing in the list, a
short welcome invites the user to star the conferences they submit to (4.2).

### 5.6 Planner window

Default size 1100 × 720, minimum 760 × 480. The sidebar uses the system material, with a thin bar
under each paper and item on the shared axis (4.3), and New Group and Settings at its foot.
Empty states use `ContentUnavailableView`.
The paper page puts the plan in a card at the top, then the blocks, milestones, deadlines and to-dos;
the details are folded away.

### 5.7 SF Symbols

| Where | Symbol |
|---|---|
| App / menu bar | `graduationcap.fill`, in the menu bar frame |
| Urgent (3 days or less) | `exclamationmark.circle.fill`; in the menu bar frame, a red `exclamationmark` |
| Overview | `chart.bar.xaxis` |
| Conferences | `list.star` |
| Visible To | `person.2` / `person.2.fill` |
| Papers | `doc.text` |
| Item of a group | Its group's symbol (4.3), `calendar` to begin with |
| New Group | `plus.circle` |
| Star | `star` / `star.fill` |
| Done | `circle` / `checkmark.circle.fill` |
| Behind | `tortoise.fill` |
| Conflict | `exclamationmark.triangle.fill` |
| Deadline | `flag.fill` |
| Send Progress | `paperplane` |

### 5.8 What to avoid

Gradients and large areas of saturated color, shadows or borders on every row, a countdown
number next to each bar, thin bars, capsules that turn into balls when short, mixed corner shapes,
emoji as icons (a country's flag after a conference's place excepted), more than three accent colors on one screen, hard-coded RGB colors, hand-made
buttons or switches, rows of controls above the content (the filters of the Conferences page
excepted), and captions that explain what the interface already shows.

---

## 6. macOS requirements

| # | Item | Requirement |
|---|---|---|
| 1 | Menu bar app | `LSUIElement = YES`; Quit is the last menu row and ⌘Q. |
| 2 | Bring windows to the front | `NSApp.activate()` after opening the planner, settings or a deadline. |
| 3 | Dock icon while a window is open | `.regular` activation policy while the planner, settings or deadline window is open, `.accessory` otherwise. *(V12)* |
| 4 | Window types | The planner and the deadline window are single `Window`s; Settings is a `Settings` scene. |
| 5 | Light and dark mode | System semantic colors only; no hard-coded RGB. Settings can keep the app light or dark (`NSApp.appearance`); the menu bar item follows the menu bar. |
| 6 | Menu bar image | Rendered with `ImageRenderer` at the scale of the sharpest screen, once with the light and once with the dark scheme, and drawn as the one that matches the appearance it is drawn in. |
| 7 | Accessibility settings | Reduce Motion and Increase Contrast are respected; no state by color alone. |
| 8 | Time zone changes | `NSSystemTimeZoneDidChange` resets the cached zone and recomputes everything. |
| 9 | New day, sleep and wake | `NSCalendarDayChanged` and `didWakeNotification` refresh the bars and sync if due. |
| 10 | Date formats | Displayed with `Date.FormatStyle`; fixed formats only for parsing ccfddl. |
| 11 | Network recovery | `NWPathMonitor` triggers a sync when the network returns; 30 s request timeout. |
| 12 | Background parsing | Parsing runs in the `CCFDDLClient` actor; launch reads `deadlines.json`. |
| 13 | Timer | One 60 s timer with 10 s tolerance. |
| 14 | Notification permission | Asked when reminders are first turned on. |
| 15 | Permission denied | Settings says notifications are off and links to System Settings. |
| 16 | Clicking a notification | Opens the paper or item, or the deadline window; banners also show while the app is in front. Block and milestone reminders, and those of a deadline that one paper or item has open and that is ticked off by itself, carry a Mark as Done action (a notification category), handled without bringing the app forward. |
| 17 | Launch at login | `SMAppService.mainApp`; the toggle follows the system state; pending approval is explained. Remove All Data unregisters it, also while it awaits approval. |
| 18 | App Sandbox | `network.client`, `files.user-selected.read-write`, `files.downloads.read-write`, Apple events to Mail. Paths always come from `FileManager`. |
| 19 | Stable bundle ID | `BUNDLE_ID_PREFIX` in `Config/Base.xcconfig`, e.g. `io.github.<owner>`, set once before the first release and never changed; contributors use their own in `Config/Local.xcconfig`. |
| 20 | Signing | Releases are signed to run locally, with no developer team (`scripts/release.sh`), and shipped as a zip of the app; macOS asks once before it first opens each version, as for any app not signed through Apple's paid developer program. With such a team, `DEVELOPER_ID=1` signs with Developer ID and notarizes instead. *(V13, V14)* |
| 21 | Keyboard | ⌘F, ⌘, and ⌘Q in the popover; ⌘N new paper and ⇧⌘N new group in the planner; ⌘← ⌘→ ⌘T to move the axis in the popover and the overview; ⌘+ ⌘− ⌘0 to zoom in the popover and from the View menu in the planner; on a paper's timeline, with a block, a milestone or a deadline of its own selected, ⌫ to move it to Recently Deleted (also from the lists under it), ↩ edit, ← → move (⇧ a week) and Esc to let go, and ⌘D to duplicate a block; ⌫ in Recently Deleted to delete the selected rows for good (with confirmation); papers and items are never deleted with ⌫; on the Conferences page and in the chooser, ⌘F to the search field, ↓ ↑ from it, ↩ to open the website or to choose, and Esc to clear the search or cancel; ⌘Z and ⇧⌘Z everywhere. Everything saves automatically. |
| 22 | VoiceOver | Every row has a complete spoken label, e.g. "CVPR 2027, Paper submission November 17, 35 days left", a paper's ends with its next deadline, and a deadline in a paper's list says whether it is the main one. Bars are hidden from VoiceOver. |
| 23 | Saving | About 0.5 s after an edit and on quit; atomic writes; `user.json.bak` before each overwrite of a file read in full or written by the app, which is read again only if something else has changed it. Copies are never locked, even of a file locked in the Finder. |
| 26 | Undo | Each window's `UndoManager`; every undo reverses only its own change, by id, so edits made in between stay. Action names in the Edit menu ("Undo Move Block"). |
| 27 | Pointer and trackpad | Sideways scroll and pinch events are read with a local monitor while the pointer is over a timeline, so vertical scrolling still reaches the list and the window need not be clicked first; a pinch zooms by what each event adds. Cursors from `NSCursor` (frame resize on macOS 15); haptics from `NSHapticFeedbackManager`. |
| 24 | Automation permission | `NSAppleEventsUsageDescription`, `automation.apple-events`, a temporary exception for `com.apple.mail`; a denied permission is explained with a link to System Settings. *(V8)* |
| 25 | Main thread | The Mail script runs one handler at a time on a queue of its own (`OSAScript`; AppleScript is thread-safe), so however long Mail takes to answer, the interface never waits; each call gives up on Mail after 30 s. *(V7)* |

---

## 7. Architecture

- Swift 6 language mode with SwiftUI, macOS 14 or later.
- `MenuBarExtra` with the `.window` style for the popover.
- One `@MainActor @Observable` `AppStore` owns the state, timers and system observers; views read
  it directly. Downloading and parsing run in an actor.
- Deadlines are instants (`Date`), parsed in the conference's time zone. Time blocks are calendar
  days (`Day`).
- The current time, the calendar and file locations are passed in, so the logic is testable.
- The project is generated by XcodeGen from `project.yml`; the generated project is not committed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the data flow.

### 7.1 Modules

```
Packages/DrBarKit  (local Swift package)
├── DrBarKit    models, planning, reminders, local JSON files    Foundation only
├── CCFDDLKit    ccfddl client: download, cache checks, YAML      DrBarKit + Yams
└── DrBarUI     SwiftUI bars, rows and axis                      DrBarKit

App target       AppStore, popover, planner, settings, notifications, Mail, App Intents
```

### 7.2 Storage

All files live in `Application Support/DrBar/` inside the sandbox container:

| File | Content | If it is lost |
|---|---|---|
| `allconf.yml` | ccfddl's conferences as downloaded | Downloaded again |
| `allacc.yml` | ccfddl's acceptance rates as downloaded | Downloaded again; the bundled ones until then |
| `deadlines.json` | The parsed catalog with the acceptance rates, read at launch | Rebuilt from `allconf.yml` and `allacc.yml` |
| `sync.json` | ETag and Last-Modified of both files, sync times, conference count, the bundled snapshot's date | Harmless |
| `user.json` | Stars, papers and the items of groups (blocks with the people on them, milestones, to-dos, deadlines of their own, the conference's dates ticked off, who may hear about each), the groups, recipient groups, settings, the Archive and Recently Deleted | **User data** — atomic writes, `user.json.bak` |

> **Backward compatibility (fixed rule 5):** every field of `user.json` has a default and is decoded
> leniently; a field added later must never be required. Unknown block kinds become custom blocks
> that keep their name. If anything cannot be read, the original file is copied next to it
> (`user.json.unreadable-<time>`, once however often it is read), or moved there when it cannot be
> read at all, and what could be read takes its place at once; a file that can be neither copied nor
> moved is never written over. If the file cannot be read at all, or is missing, the backup is used,
> and set aside too when any of it cannot be read. Only a file read in full becomes the backup. The
> items of a group that cannot be read join the papers. A paper, an item or a part of one there twice with the same id is
> read once; another with an id already taken is left out as unreadable. Each release adds a
> `user.json` fixture to the tests.

### 7.3 Repository layout

```
drbar/
├── README.md, README.zh-CN.md, LICENSE, THIRD_PARTY_NOTICES.md, CHANGELOG.md
├── CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
├── project.yml                      XcodeGen: the app target
├── Config/                          Base.xcconfig, Local.xcconfig.example (personal values)
├── Packages/DrBarKit/              the package and its tests
├── App/                             the app target
├── scripts/                         bootstrap, run, release, snapshot refresh, string sync, icon
├── docs/                            this spec, ARCHITECTURE.md, images/, the user guide
│                                    (GUIDE.md, GUIDE.zh-CN.md) and the website (index.html, with
│                                    its films in media/)
└── .github/                         CI, weekly snapshot refresh, issue templates, Dependabot
```

### 7.4 Lightweight budget

| Item | Target |
|---|---|
| Download size | Under 15 MB, including the data snapshot (measured on 2026-10-13: a universal app under 9 MB, a 3.7 MB zip) |
| Launch | Menu bar icon within 0.5 s; launch reads `deadlines.json` only |
| Memory | Under 50 MB with the popover closed *(V9)* |
| CPU and energy | About 0 % when idle; one 60 s timer; the menu bar image is cached; animations play once, in answer to the user or a new day, and none runs while idle |
| Network | At most two requests per 12 hours, the conferences and then their acceptance rates, usually answered with `304` |
| Background | No helper processes |

### 7.5 Sending progress through Mail

- Mail's own "reply" is the only way to get `In-Reply-To` and `References`, which keep a thread
  together; the share service and `mailto:` cannot set them. So DrBar drives Mail through
  AppleScript handlers in `MailBridge.applescript`, called with parameters.
- **First email:** compose to the group's people with the subject, body and image, from the account
  whose address is set in Settings (Mail's default otherwise); send; then look up its Message-ID
  in the Sent mailbox after 5 and 30 seconds.
- **Later emails:** reply to the first email, replace the recipients with the group's people, set the
  subject with the new count, the body and the image, send.
- **First email gone** (deleted, another Mac): the sheet offers to start a new thread.
- **Another default mail app** (Outlook, Gmail in a browser…): the button reads Open Draft. A
  `mailto:` link opens a new email there with the subject (`Re: …` for later updates) and the text
  filled in; the image is copied to the clipboard to paste, and the user presses Send there. The
  paper keeps the thread's subject but no "Last sent", since DrBar cannot know whether it went
  out. Outlook and Apple Mail group the updates by subject, Gmail may not; the sheet says so.
- No SMTP: it would need the user's password, and many university accounts forbid it.

---

## 8. Implementation notes

The code is the reference; these are the places worth reading first:

| Topic | File |
|---|---|
| Parsing and flattening ccfddl | `Packages/DrBarKit/Sources/CCFDDLKit/DeadlineParser.swift` |
| Download and cache checks | `Packages/DrBarKit/Sources/CCFDDLKit/CCFDDLClient.swift` |
| Time zones | `Packages/DrBarKit/Sources/DrBarKit/Time/DeadlineTimeZone.swift` |
| Calendar days and the axis | `Packages/DrBarKit/Sources/DrBarKit/Time/Day.swift`, `TimeAxis.swift` |
| Rows, menu bar choice | `Packages/DrBarKit/Sources/DrBarKit/Planning/DeadlineRows.swift` |
| Progress, status, backward planning | `Packages/DrBarKit/Sources/DrBarKit/Planning/PlanMath.swift` |
| A paper's deadlines, the flag and what work leads up to | `Packages/DrBarKit/Sources/DrBarKit/Planning/PaperDeadlines.swift`, `PaperOverview.swift`, `PlanMath.swift` (`Cutoffs`) |
| Editing rules for deadlines | `Packages/DrBarKit/Sources/DrBarKit/Models/CustomDeadline.swift` |
| Targets, stages and the rounds fixed at submission | `Packages/DrBarKit/Sources/DrBarKit/Models/PaperTarget.swift`, `ConferenceCatalog.swift` (`round(id:now:)`) |
| Renamed conferences and rounds | `Packages/DrBarKit/Sources/DrBarKit/Models/CatalogRenames.swift` |
| Names beside flags | `Packages/DrBarKit/Sources/DrBarKit/Support/LabelPlacement.swift`, `DrBarUI/Deadlines.swift` |
| A group's line of work without blocks | `Packages/DrBarKit/Sources/DrBarUI/DueLane.swift`, `App/Support/ItemSections.swift` |
| A conference's country | `Packages/DrBarKit/Sources/DrBarKit/Support/CountryFlags.swift` |
| Reminders and date changes | `Packages/DrBarKit/Sources/DrBarKit/Planning/Reminders.swift`, `ChangeDetector.swift` |
| Email summary | `Packages/DrBarKit/Sources/DrBarKit/Planning/ProgressSummary.swift` |
| Saving without losing data | `Packages/DrBarKit/Sources/DrBarKit/Storage/FileStore.swift` |
| The bars, the row sizes | `Packages/DrBarKit/Sources/DrBarUI/Bars.swift`, `Rows.swift`, `AxisHeader.swift`, `Theme.swift` (`RowMetrics`) |
| The menu bar item | `App/MenuBar/MenuBarLabel.swift` |
| Dragging blocks and rows | `Packages/DrBarKit/Sources/DrBarUI/BlockEditing.swift`, `DrBarKit/Support/RowMove.swift` |
| Edits that can be undone | `App/AppStore+Editing.swift` |
| Moving and zooming the axis | `Packages/DrBarKit/Sources/DrBarKit/Time/AxisPosition.swift`, `App/Support/TimelineGestures.swift` |
| State and system events | `App/AppStore.swift` |
| Rows of a plan, milestones, recipient groups | `Packages/DrBarKit/Sources/DrBarKit/Models/TimeBlock.swift` (`BlockLane`), `Milestone.swift`, `Recipients.swift`; `DrBarUI/Milestones.swift` |
| Mail | `App/Services/ProgressMail.swift`, `App/Resources/MailBridge.applescript` |

---

## 9. Roadmap

| Version | Content |
|---|---|
| 0.1 | Everything above, as a zip of the app, in English and Chinese |
| Later (optional) | A desktop widget; more interface languages |

New ideas go to "Later" first and must fit the budget in 7.4.

---

## 10. Testing

- `swift test --package-path Packages/DrBarKit` covers time zones, date parsing, flattening and
  round ids (with `Fixtures/sample.yml`) and what renamed series and rounds carry over, the download client
  against a stubbed server (200, 304, error pages, too few conferences, editions it cannot read),
  rows and the menu bar choice, a paper's deadlines with the flag, what is done by the stage, the
  round followed, the rounds fixed at submission and let go before it, what work leads up to, the names
  placed beside flags and the flags of a group's line, the countries of conference places, plan
  math, the share of a plan due by today and
  backward planning, dragging blocks and reordering rows of different heights, the rows and rounds
  of a plan, overlapping blocks in tracks, milestones in the status, the summary and the reminders,
  the moved and zoomed axis (also by pinches that report nothing usable, and the stop at the chosen
  range), lines every few days from today, the week range and the days and weekends of the axis,
  what the Conferences page lists, past editions included, the acceptance rates read and joined to
  their conferences, arriving with them, on their own or from the bundle, the email summary in both
  languages, which other work an update may mention and how, when a hover card has something to add,
  recipient groups and their threads, reminders, date-change detection, the Archive and Recently
  Deleted with the parts of papers, lenient decoding of `user.json` with fixtures from every release,
  what is there twice, and recovery from unreadable files and backups.
- A test parses the bundled snapshot and checks that every time zone in it is understood, and that
  the bundled acceptance rates parse and fit its conferences.
- Debug builds render every main view in light and dark mode with sample data, at rest, including
  the popover moved back in time, the hover cards and the send sheet with other work:
  `scripts/run.sh --demo --snapshots`. The views also have Xcode
  previews on the same data. Use them to look at visual changes. The same run carries out each of
  Siri's actions on the sample data, as Siri would with everything said, and writes what it
  answered and whether it did it to `intents.txt`; opening a paper is only looked up, as it would
  bring the planner to the front.
- Dragging, drawing, selecting, swiping and zooming are tried by hand: they depend on the trackpad,
  the pointer and the keyboard.
- Sending email is tested by hand with a real Mail account before each release.

---

## 11. Open source

- **License:** MIT; the ccfddl, Yams and LibYAML notices ship in the app and in
  `THIRD_PARTY_NOTICES.md`.
- **Personal values** (team ID, a contributor's own bundle ID prefix) stay in
  `Config/Local.xcconfig`, which is not committed.
- **Localization:** String Catalogs; English is the source language, Simplified Chinese is complete.
  `scripts/sync-strings.sh` adds new keys.
- **CI:** lint with `swift-format`, package tests, and an unsigned build of the app on every pull
  request; a weekly job proposes a refreshed ccfddl snapshot.
- **Releases:** `scripts/release.sh` builds the app as a zip for GitHub Releases, signed to run
  locally, or with Developer ID and notarized once there is a paid team; unzipping it gives
  `DrBar.app`, with nothing to install.
- **Wrong data:** issue templates point deadline errors to ccfddl.

---

## 12. Assumptions

| # | Assumption | Status |
|---|---|---|
| V1 | `allconf.yml` is one file with a `conference_key` per series, and it and `allacc.yml` answer conditional requests | Confirmed on 2026-10-12: 375 series, all with a key; `304` for both ETag and Last-Modified. `allacc.yml`: `304` for both on 2026-10-14 |
| V2 | Time zones are only AoE, UTC, UTC±N and PT | Confirmed for the 2026-10-12 data; a test checks every snapshot |
| V3 | A rendered image works as a `MenuBarExtra` label and is drawn in the appearance of the menu bar it is on, whatever the app's own Appearance setting | Confirmed on macOS 26.6, also with the app set to the other appearance: the status item draws the image with each appearance it takes. To check on macOS 14 and 15, and on each new macOS |
| V4 | A linear axis plus orange and red is readable enough | Check with users |
| V5 | Mail's `reply` without a window can be edited and sent | Test by hand with real accounts |
| V6 | Mail reports the Message-ID of a sent email within 30 seconds | Test by hand; the thread still works by subject otherwise |
| V7 | Short AppleScript calls on the main thread do not stall the interface noticeably | Test by hand |
| V8 | The temporary Apple-event exception is accepted for Developer ID builds | Check at the first notarized release |
| V9 | Under 50 MB of memory with the popover closed | Measured 20 MB (physical footprint) for a Release build on 2026-10-13 |
| V10 | Block names fit inside planner bars often enough to be useful | Yes for blocks of about a week or longer in the 3-month view |
| V11 | Replacing all pending notifications on every change stays within the 64 limit | By construction (60) |
| V12 | Switching the activation policy keeps windows in front | To check on each new macOS |
| V13 | Notarization accepts the app as built by `scripts/release.sh` | Check at the first notarized release |
| V14 | An app signed to run locally, downloaded and allowed once, keeps everything working: Siri and Shortcuts, reminders, open at login, and sending through Mail after an update | Check at the first release |
