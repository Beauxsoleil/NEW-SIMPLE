Title: ROPS (Recruiter Ops) — Engineering Agent Guide
Owner: Joel “Beaux” Viola
Goal: Build a fast, stable iOS app for military recruiting workflows with zero external deps, iOS 16+.
1) Non-Negotiables
Builds first try on a fresh Xcode project, SwiftUI, iOS 16+.
Additive changes only. Do not remove features unless it fixes a bug or compile error.
On-device only. No network calls, no external packages.
Respect privacy. Documents and logos live under Application Support; atomic writes.
2) Modules (Expected Files)
CoreTypes.swift — enums (Stage, Sex, EventType), models (Applicant, RecruitEvent, ACFTEntry), theme, helpers (bindings, Color hex, date utils).
BodyCompService.swift — HT/WT table, BF% caps, one-site tape charts, evaluator (evaluateBodyComp).
ACFTService.swift — Raw→points equations per event; scoreACFT(raw:) -> perEvent + total; pure and testable.
Persistence.swift — StoreEnvelope, Store (applicants/events/settings), logo I/O, JSON import/export.
FilesAndOCR.swift — FileStore, scanner (Vision), QuickLook, thumbnails, checklist lexicon + OCR inference.
CalendarAndNotifications.swift — EventKit access, calendar creation, event save/edit, local notifications helpers.
UI_Tabs.swift — ContentView TabView, theme, global lifecycle hooks.
UI_Applicants.swift — Inbox + Editor + ACFT editor sheet; rows, pickers.
UI_Events_Reports_SAS.swift — Events list/editor; Reports PDF; SAS view/detail and SAS PDF.
UI_Workstation_Settings_Extras.swift — Workstation (FY drills, snippets, pack list, trip planner), Settings, Easter egg game.
Widget & Shortcuts targets are optional extensions added later; keep core app independent.
3) Coding Standards
Swift 5.9+, SwiftUI first.
Threading: UI on main, I/O on background. Use @MainActor when returning to views.
Error handling: never crash for user content; log and continue.
Persistence: temp write + replace (replaceItemAt) for durability.
Accessibility: tappable sizes ≥44pt; Dynamic Type friendly where possible.
4) UX Guidelines
Clean, modern, “OpenAI-ish”. Rounded rectangles, subtle system background tints, sparse separators.
Avoid modals stacking; prefer sheets with presentationDetents([.medium]).
Forms: group with clear headers; show subtle captions for hints.
Status chips: green/yellow/red based on configured thresholds.
5) Data & Migrations
StoreEnvelope.schema handles migrations. New fields are optional with defaults.
All computed fields derive at render time when possible (e.g., days in stage).
6) ACFT Policy
Score with equations derived from official tables.
Clamp to 0–100 per event; sum to 0–600.
Keep a tiny override dictionary for edge corrections without shipping updates.
7) Security & Privacy
Files stored at: Application Support/<bundle>/Applicants/<UUID>/...
JSON exports are user-initiated to the temp directory; never auto-export.
8) Performance Budget
Cold launch under 2s on mid-range device.
Lists diffable; images thumbnailed; large PDFs generated off main where feasible.
Avoid excessive state in root views; prefer small view structs.
9) Testing Guidance
Unit tests (if target added):
ACFT event equations (golden cases).
Body comp evaluator (pass/fail & edge).
JSON round-trip for Applicants + Events + Settings.
Manual QA checklist:
New Applicant -> Save -> Reopen.
Overweight -> Waist -> One-site pass/fail.
Scan doc -> OCR suggests “SSN/BC/DL” -> adds to checklist.
Event -> Add to Calendar -> Edit in EventKit UI.
Report PDF with logo -> share sheet.
SAS weekly reminder toggle + SAS PDF.
10) Shipping Discipline
Every change compiles.
No dead code.
Comments are purposeful (// Why, not // What).
Use // TODO(ROPS): for backlog items matching the roadmap below.
11) Roadmap (in order)
ACFT equations + inline editor + SAS PDF enrichment.
Recruiter Workstation (FY drills, snippets, pack list, trip planner).
Event “Needs”, reminder offsets, message summary.
Dashboard cards (Overdue, Next Events, MTD vs Goal, ACFT highlights).
EOY CSV pack (Applicants/Events/Outcomes/Geo tallies).
Widgets (Overdue / Next Event / Quick Actions via App Group snapshot).
Shortcuts (Send Monday PDF; Log ACFT).
Apple-Intelligence style rewrite & weekly summary (safe fallback).
Perf/QA pass and micro-optimizations.
12) How to Run (fresh Mac)
Xcode → New SwiftUI App “ROPS”; iOS Deployment Target 16.0.
Add files in the order above; build after each module.
Capabilities: Calendars (on), Notifications (local), Photos/Camera usage descriptions in Info.plist.
Run on device/simulator; test Scanner on device.
Feature backlog snapshot (next up)
ACFT raw→points equations + UI; improve SAS PDF (drills + ACFT + logo).
Recruiter Workstation (FY drills, snippets, pack list, trip planner).
Event Needs + reminder offsets + message summary.
Dashboard cards polish.
EOY CSV export pack.
Widgets (App Group snapshot).
Shortcuts (auto-send Monday PDF).
AI-style rewrite/weekly summary (fallback path).
Perf/QA pass.
If you want, I can also generate a ready-to-paste “files separated by markers” skeleton on your next message—just say “Go – 10-file split” or “Go – 2 halves.”





ChatGPT can make mistakes. Check important info.
