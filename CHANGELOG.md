# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-20

The first version, for trying out. Releases are not signed through Apple's paid developer program
yet, so macOS asks once before DrBar first opens (README › Get started).

### Added

- Menu bar item in a rounded frame that keeps time: time goes round its thick outline, from when
  the work started to the deadline at the top, and the stretch still to go is the time left, in the
  color of how close it is; or one paper or item picked for it, its plan round the outline in the colors of its blocks,
  done ones solid, with a dot at today that turns orange when it falls behind and its own symbol
  inside; or one conference. With the name, the days left too, the next two deadlines in two
  frames, or the symbol alone.
- A small Gantt chart under the menu bar: papers first, then your own groups, then the starred
  conferences as thin bars, on one axis, with the last few days shown faintly.
- Deadlines from ccfddl: starring, details with both time zones and the whole conference cycle, and
  a Conferences page in the planner that lists every conference as ccfddl does: a row each with its
  full name, place with its country's flag and meeting days, its CCF, CORE and TH-CPL ranks,
  category and acceptance rate,
  and the time left over the abstract and paper deadlines. Search it, keep to the categories and
  ranks you choose with the buttons above it, show past conferences, sort it by deadline, name, CCF
  rank or acceptance rate, and switch between All and Starred; the details beside it have the
  acceptance rates of recent years. Browse Conferences… (⌘F) in the menu bar window opens it.
- Papers with time blocks, a row for each kind of work in as many rounds as it takes, backward
  planning from the deadline, status (behind, conflict), and a to-do list. Work with no blocks is
  just its deadlines: flags on the line of its group's name, named for it, until a first block is
  added. A little red flag stands on a plan's bar beside its deadline's red line. Blocks on the same days sit one
  above the other, in a bar that grows so their names and people still fit; a row of the overview
  can be made taller or shorter by its lower edge, and all rows come in three sizes. A block that
  ended without being done is edged in orange.
- Milestones for internal deadlines and the like: diamonds on the timeline, edited as blocks are,
  with reminders on their day and the next one in the email.
- Every deadline of a paper: the abstract registration, paper submission, rebuttal and notification
  of its conference's round, and any number of its own, such as a supplementary or a camera-ready,
  each named on a Deadlines row of the timeline and in a list, ticked off one by one or by the stage,
  and reminded of before it, once however many papers share it, but for the notification. The red flag marks the deadline the plan aims at, then the next one after
  it; own deadlines drag like milestones, and work is checked against the deadline it leads up to.
  Marking a paper submitted fixes the round it went to.
- Blocks can name who works on them, from the supervisors and collaborators in Settings, shown as
  monograms on the block and by name in the email.
- Editing on the timeline as in Calendar: draw a block across empty days, drag an end to change it
  or the middle to move it, a day at a time, drag with Option to copy it; click to select, double
  click to edit, and Delete, ⌘D, the arrow keys and Esc for the selected block, which the overview
  and the menu bar window select and delete too. A drag held at either end of the bars scrolls the
  timeline along. Undo for all of it.
- Dragging to reorder: groups by their headings in the sidebar, Papers too; papers and items within
  their group or into another, in the sidebar, the overview and the menu bar window; blocks and
  to-dos in their lists. Recipient groups and people move up and down in Settings.
- Swiping, scrolling or dragging sideways moves the timeline up to a year back or ahead; pinching or
  scrolling with ⌘ zooms from three days to two years, never leaving today behind, and a pinch stops
  at the chosen range with a light tap of the trackpad. Both work as soon as the pointer is over a
  timeline, also in the menu bar window. A week, a month, three or six months as the range. Weeks
  and days show as there is room, as dates, as the days from today or both; every day gets a faint
  line of its own and the weekends a faint band, and close in each day is named in its column.
- Planner window with an overview of all papers, groups and conferences on one timeline, and thin
  bars in the sidebar on one shared axis.
- Groups of your own besides Papers, for other work with deadlines such as applications, whose
  items are planned like papers, without stages or emails, each with a symbol of its choosing.
- Siri, Spotlight and Shortcuts: add a paper or an item with its deadline, add a deadline or a
  block, move a block, change when it ends or tick it off, hear the next deadline, or open a paper,
  by saying it, in English or Chinese.
- An Archive for finished work, kept with everything it had until moved back, and Recently Deleted,
  which keeps what is deleted for thirty days: papers and items, and every block, milestone,
  deadline or to-do deleted from them, which Recover puts back where it was. The Delete key takes
  only what is selected on a page and never sends a whole paper or item away. Rows swipe as in Mail
  to archive, recover or delete.
- Cards for what holds more than it shows when the pointer rests on it: who works on a block, a
  name cut short, why work is marked late or past its deadline, a paper's deadlines ahead with the
  time left, its people and open to-dos, every date of a conference's round; drawn as the system
  draws a popover, and none where the bar says it all.
- Back and Forward in the planner, with ⌘[ and ⌘] and the side buttons of a mouse.
- A paper's conference is chosen from the same list, with the details of the selected one beside
  it; a search also finds past editions. The details link to the conference's papers on DBLP.
- Reminders before deadlines, on the last day of a block, and when ccfddl changes a date; a block's
  or a milestone's reminder can mark it done, and so can that of a deadline ticked off by itself.
- Progress emails through Mail to groups of recipients (supervisors, collaborators, or groups of
  your own, with any number of people), in one thread per paper and group. The subject has the
  stage and the days left, the first line says what matters to the recipients and what has changed
  since the last update, and the image opens with a banner in the colors of the stage. With another
  mail app, a prepared email to send there.
- Visible To chooses who of your recipients may hear about a paper or an item; an update can then
  say what else you are working on, a line each and a thin bar under the timeline, only what
  everyone it goes to may see.
- Motion that answers what you do and costs nothing at rest: bars grow out of today as a timeline
  comes into view, pages fade in, the whole timeline glides together, also from one range to
  another, and Undo and Esc slide things back; with Reduce Motion, nothing moves.
- Light or dark appearance, or as the system is set; English and Simplified Chinese.
- Import, export and "Remove All Data".
- A user guide in English and Chinese (`docs/GUIDE.md`) and a website (`docs/index.html`) in light
  and dark, with films of the app in motion and how to use DrBar step by step.

[Unreleased]: https://github.com/zhiheng-yang/DrBar/compare/v0.1.0...main
[0.1.0]: https://github.com/zhiheng-yang/DrBar/releases/tag/v0.1.0
