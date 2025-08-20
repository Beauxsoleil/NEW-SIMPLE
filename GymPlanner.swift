//  GymPlanner.swift
//  ROPS — Additive "Gym Day" planner (iOS 16+)
//  - Evidence-based rep schemes for strength/hypertrophy/endurance
//  - ACFT-first mapping (MDL/SPT/HRP/SDC/PLK/2MR)
//  - PDF export via PDFKit
//
//  NOTE: purely additive. You can present this view from your Work Station tab.

import SwiftUI
import PDFKit
import UIKit

// MARK: - Taxonomy

enum GymGoal: String, CaseIterable, Identifiable {
    case acft = "ACFT (priority)"
    case strength = "Strength"
    case physique = "Physique/Hypertrophy"
    case endurance = "Endurance"
    var id: String { rawValue }
}

enum GymFocus: String, CaseIterable, Identifiable {
    case fullBody = "Full Body"
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case arms = "Arms"
    case conditioning = "Conditioning"
    case acftStrength = "ACFT: MDL/HRP"
    case acftPowerAgility = "ACFT: SPT/SDC"
    case acftCoreRun = "ACFT: PLK/2MR"
    var id: String { rawValue }
}

enum TrainingLevel: String, CaseIterable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    var id: String { rawValue }
}

enum Equipment: String, CaseIterable, Identifiable {
    case bodyweight = "Bodyweight"
    case barbell = "Barbell"
    case dumbbell = "Dumbbells"
    case kettlebell = "Kettlebell"
    case medball = "Med Ball"
    case cable = "Cable"
    case sled = "Sled/Straps"
    case rower = "Rower"
    case bike = "Bike"
    case track = "Track/Field"
    var id: String { rawValue }
}

enum Movement: String {
    case squat
    case hinge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case carry
    case coreAntiExt
    case sprint
    case jump
    case throwing = "throw"
    case loadedDrag
    case run
}

enum ACFTEvent: String {
    case mdl = "MDL (3RM)"
    case spt = "SPT (Throw)"
    case hrp = "HRP (Push-up)"
    case sdc = "SDC (Shuttle)"
    case plk = "PLK (Plank)"
    case twoMR = "2MR (Run)"
}

// MARK: - Exercises

struct Exercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let movement: Movement
    let equipment: Set<Equipment>
    let targets: [String]               // muscle or quality
    let acftCarryover: Set<ACFTEvent>   // which events benefit
    let coaching: String                // one-liners/cues
}

struct SetScheme: Hashable {
    let sets: Int
    let reps: ClosedRange<Int>
    let restSec: Int
    let notes: String   // RPE/%1RM or pacing info
}

struct PlanExercise: Identifiable, Hashable {
    let id = UUID()
    let exercise: Exercise
    let scheme: SetScheme
}

struct GymDayPlan {
    let date: Date
    let title: String
    let warmup: [String]
    let mainBlocks: [(blockTitle: String, items: [PlanExercise])]
    let conditioning: [String]          // intervals/shuttles/runs
    let cooldown: [String]
    let notes: [String]
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Exercise DB (compact but useful)

private let EX: [Exercise] = [
    // Hinge / MDL
    Exercise(name: "Barbell Deadlift", movement: .hinge,
             equipment: [.barbell], targets: ["posterior chain","grip"],
             acftCarryover: [.mdl, .sdc], coaching: "Brace, bar close, push floor."),
    Exercise(name: "Romanian Deadlift", movement: .hinge,
             equipment: [.barbell, .dumbbell, .kettlebell], targets: ["hamstrings","glutes"],
             acftCarryover: [.mdl], coaching: "Hinge, slight knee bend, long hamstrings."),
    Exercise(name: "Trap Bar Deadlift", movement: .hinge,
             equipment: [.barbell], targets: ["total-body hinge","grip"],
             acftCarryover: [.mdl, .sdc], coaching: "Neutral grip, drive up with legs."),
    // Squat / Legs
    Exercise(name: "Back Squat", movement: .squat,
             equipment: [.barbell], targets: ["quads","glutes","core"],
             acftCarryover: [.mdl, .sdc], coaching: "Depth, knees over toes, brace."),
    Exercise(name: "Goblet Squat", movement: .squat,
             equipment: [.dumbbell, .kettlebell], targets: ["quads","bracing"],
             acftCarryover: [.mdl, .sdc], coaching: "Elbows in, sit between hips."),
    // Push
    Exercise(name: "Hand‑Release Push‑Up", movement: .horizontalPush,
             equipment: [.bodyweight], targets: ["pecs","triceps","core"],
             acftCarryover: [.hrp], coaching: "Chest to ground, hands release, tight plank."),
    Exercise(name: "Barbell Bench Press", movement: .horizontalPush,
             equipment: [.barbell], targets: ["pecs","triceps"],
             acftCarryover: [.hrp], coaching: "Scapular set, controlled touch and go."),
    Exercise(name: "DB Overhead Press", movement: .verticalPush,
             equipment: [.dumbbell], targets: ["delts","triceps","core"],
             acftCarryover: [.hrp, .plk], coaching: "Ribs down, press under load."),
    // Pull
    Exercise(name: "Pull‑Ups/Assisted", movement: .verticalPull,
             equipment: [.bodyweight, .cable], targets: ["lats","grip","scap"],
             acftCarryover: [.sdc], coaching: "Full hang to chest-to-bar or chin."),
    Exercise(name: "DB Row (Bench)", movement: .horizontalPull,
             equipment: [.dumbbell], targets: ["lats","mid‑back"],
             acftCarryover: [.sdc, .mdl], coaching: "Elbow path to hip, pause at top."),
    // Carries / Sled / Shuttle
    Exercise(name: "Farmer Carry", movement: .carry,
             equipment: [.dumbbell, .kettlebell], targets: ["grip","trunk"],
             acftCarryover: [.sdc, .mdl], coaching: "Tall walk, quick steps."),
    Exercise(name: "Sled Drag", movement: .loadedDrag,
             equipment: [.sled], targets: ["posterior chain","anaerobic"],
             acftCarryover: [.sdc], coaching: "Forward lean, rapid turnover."),
    // Throw / Power
    Exercise(name: "Med‑Ball Overhead Throw", movement: .throwing,
             equipment: [.medball], targets: ["triple extension","power"],
             acftCarryover: [.spt], coaching: "Dip, drive, long arc."),
    Exercise(name: "Broad Jump (standing)", movement: .jump,
             equipment: [.bodyweight], targets: ["elastic power"],
             acftCarryover: [.spt], coaching: "Load hips, swing arms, stick landing."),
    // Core (Plank bias)
    Exercise(name: "Plank RKC", movement: .coreAntiExt,
             equipment: [.bodyweight], targets: ["anti‑extension","bracing"],
             acftCarryover: [.plk, .hrp], coaching: "Glutes + lats on, hollow body."),
    Exercise(name: "Dead Bug", movement: .coreAntiExt,
             equipment: [.bodyweight], targets: ["lumbopelvic control"],
             acftCarryover: [.plk], coaching: "Low back down, slow reach."),
    // Running / Conditioning
    Exercise(name: "400m Repeats", movement: .run,
             equipment: [.track], targets: ["2MR pacing","VO2"],
             acftCarryover: [.twoMR], coaching: "Run 400m @ 1‑mile pace, jog 200m."),
    Exercise(name: "Shuttle 5‑10‑5", movement: .sprint,
             equipment: [.track], targets: ["COD","anaerobic"],
             acftCarryover: [.sdc], coaching: "Low center, plant hard, accelerate."),
    Exercise(name: "Bike Intervals", movement: .sprint,
             equipment: [.bike], targets: ["anaerobic power"],
             acftCarryover: [.sdc], coaching: "60s hard / 60‑120s easy x 6‑10.")
]

// MARK: - Schemes (evidence‑grounded defaults)

struct SchemeLibrary {
    static func mainLift(level: TrainingLevel, goal: GymGoal) -> SetScheme {
        switch goal {
        case .strength, .acft:
            // Strength: 3–5 sets, 3–5 reps, RPE 7–9, rest 120–180s
            return SetScheme(sets: level == .advanced ? 5 : 4,
                             reps: 3...5, restSec: 150, notes: "RPE 7–9 (~80–90% 1RM)")
        case .physique:
            return SetScheme(sets: level == .advanced ? 5 : 4,
                             reps: 6...12, restSec: 90, notes: "RPE 7–8; controlled tempo")
        case .endurance:
            return SetScheme(sets: 3, reps: 12...20, restSec: 60, notes: "RPE 6–7; minimal rest")
        }
    }
    static func assistance(goal: GymGoal) -> SetScheme {
        switch goal {
        case .strength, .acft:
            return SetScheme(sets: 3, reps: 5...8, restSec: 90, notes: "RPE 7–8")
        case .physique:
            return SetScheme(sets: 3, reps: 10...15, restSec: 60, notes: "Focus on pump / control")
        case .endurance:
            return SetScheme(sets: 2, reps: 15...20, restSec: 45, notes: "Circuit pace")
        }
    }
    static let plankScheme = SetScheme(sets: 3, reps: 30...60, restSec: 60, notes: "Hold seconds; hollow brace")
}

// MARK: - Generator

struct GymPlanGenerator {

    static func generate(
        date: Date = Date(),
        focus: GymFocus,
        goal: GymGoal,
        level: TrainingLevel,
        equipment: Set<Equipment>,
        minutes: Int
    ) -> GymDayPlan {

        // Warm‑up defaults (5–8 min)
        let warmup = [
            "5 min easy bike/row/jog",
            "Dynamic: Leg swings, arm circles",
            "Prep: Hip hinge drill + scap push‑ups"
        ]

        var blocks: [(String, [PlanExercise])] = []
        var conditioning: [String] = []
        var cooldown = [
            "Easy walk 3–5 min",
            "Breathing: 3x (4s inhale / 6s exhale)"
        ]
        var notes: [String] = [
            "Keep 1–3 reps in reserve (RIR) on strength sets.",
            "Stop a set if technique degrades.",
            "Hydrate; respect quiet hours if scheduling notifications."
        ]

        func pick(_ filter: (Exercise) -> Bool, max: Int) -> [Exercise] {
            EX.filter(filter).filter { $0.equipment.isSubset(of: equipment) || $0.equipment.contains(.bodyweight) }.prefix(max).map { $0 }
        }
        func plan(_ exs: [Exercise], scheme: SetScheme, title: String) {
            let items = exs.map { PlanExercise(exercise: $0, scheme: scheme) }
            if !items.isEmpty { blocks.append((title, items)) }
        }

        let mainScheme = SchemeLibrary.mainLift(level: level, goal: goal)
        let assistScheme = SchemeLibrary.assistance(goal: goal)

        switch focus {
        case .acftStrength:
            // MDL + HRP day
            plan(pick({ $0.acftCarryover.contains(.mdl) && $0.movement == .hinge }, max: 1), scheme: mainScheme, title: "Main — MDL Focus")
            plan(pick({ $0.acftCarryover.contains(.hrp) && ($0.movement == .horizontalPush || $0.movement == .verticalPush) }, max: 2), scheme: assistScheme, title: "Assistance — HRP Support")
            conditioning.append("Farmer Carry: 4 x 40m (heavy, 90s rest)")
        case .acftPowerAgility:
            // SPT + SDC day
            plan(pick({ $0.acftCarryover.contains(.spt) && ($0.movement == .throwing || $0.movement == .jump) }, max: 2), scheme: assistScheme, title: "Power — SPT Drills")
            plan(pick({ $0.acftCarryover.contains(.sdc) && ($0.movement == .loadedDrag || $0.movement == .sprint) }, max: 2), scheme: assistScheme, title: "Agility — SDC Prep")
            conditioning.append("Sled Drag: 6 x 20m (moderate‑heavy, 90s rest)")
            conditioning.append("Shuttle 5‑10‑5: 4–6 reps (full recovery)")
        case .acftCoreRun:
            // PLK + 2MR day
            plan([Exercise(name:"Plank (RKC)", movement: .coreAntiExt, equipment: [.bodyweight], targets: ["anti‑extension"], acftCarryover: [.plk], coaching: "Glutes/lats on, hollow body.")],
                 scheme: SchemeLibrary.plankScheme, title: "Core — PLK")
            conditioning.append("400m Repeats: 6–8 x 400m @ 1‑mile pace, 200m jog rest")
            notes.append("If no track, do Bike Intervals 10x(60s hard / 60–120s easy).")
        case .fullBody:
            plan(pick({ $0.movement == .hinge }, max: 1), scheme: mainScheme, title: "Main — Hinge")
            plan(pick({ $0.movement == .squat }, max: 1), scheme: assistScheme, title: "Assistance — Squat")
            plan(pick({ $0.movement == .horizontalPush || $0.movement == .verticalPush }, max: 1), scheme: assistScheme, title: "Assistance — Push")
            plan(pick({ $0.movement == .horizontalPull || $0.movement == .verticalPull }, max: 1), scheme: assistScheme, title: "Assistance — Pull")
            conditioning.append("Carry Medley: 3 rounds (farmer 30m + plank 45s)")
        case .push:
            plan(pick({ $0.movement == .horizontalPush }, max: 1), scheme: mainScheme, title: "Main — Push")
            plan(pick({ $0.movement == .verticalPush }, max: 1), scheme: assistScheme, title: "Assistance — Overhead")
            plan(pick({ $0.movement == .horizontalPull }, max: 1), scheme: assistScheme, title: "Balance — Row")
            conditioning.append("HRP EMOM: 10 min — 5–12 reps each minute")
        case .pull:
            plan(pick({ $0.movement == .horizontalPull || $0.movement == .verticalPull }, max: 1), scheme: mainScheme, title: "Main — Pull")
            plan(pick({ $0.movement == .hinge }, max: 1), scheme: assistScheme, title: "Assistance — Hinge")
            conditioning.append("Farmer Carry: 5 x 40m (heavy, 90s rest)")
        case .legs:
            plan(pick({ $0.movement == .squat }, max: 1), scheme: mainScheme, title: "Main — Squat")
            plan(pick({ $0.movement == .hinge }, max: 1), scheme: assistScheme, title: "Assistance — Hinge")
            conditioning.append("SDC Prep: 6 x 20m shuttle @ fast pace, full rest")
        case .arms:
            plan(pick({ $0.movement == .horizontalPush || $0.movement == .verticalPush }, max: 1), scheme: assistScheme, title: "Push Accessory")
            plan(pick({ $0.movement == .horizontalPull || $0.movement == .verticalPull }, max: 1), scheme: assistScheme, title: "Pull Accessory")
            conditioning.append("HRP Practice: 4 sets max‑quality reps, 90s rest")
        case .conditioning:
            conditioning.append("EMOM 12: min1 HRP 10–15, min2 Farmer 30m, min3 Plank 45s")
            conditioning.append("Bike Intervals: 8 x (60s hard / 90s easy)")
        }

        // Trim for time
        if minutes < 45 {
            if blocks.count > 2 { blocks.removeLast() }
            if conditioning.count > 1 { conditioning.removeLast() }
        }

        let title = "\(focus.rawValue) — \(goal.rawValue)"
        return GymDayPlan(date: date, title: title, warmup: warmup, mainBlocks: blocks, conditioning: conditioning, cooldown: cooldown, notes: notes)
    }
}

// MARK: - PDF Export

final class GymPDFRenderer {
    static func render(plan: GymDayPlan) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GymDay_\(Int(plan.date.timeIntervalSince1970)).pdf")
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)) // US Letter
        try pdf.writePDF(to: url) { ctx in
            ctx.beginPage()
            let margin: CGFloat = 36
            var y: CGFloat = margin

            func draw(_ text: String, font: UIFont, color: UIColor = .label, indent: CGFloat = 0) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let maxRect = CGRect(x: margin + indent, y: y, width: 612 - margin*2 - indent, height: .greatestFiniteMagnitude)
                let h = (text as NSString).boundingRect(with: CGSize(width: maxRect.width, height: .greatestFiniteMagnitude),
                                                         options: [.usesLineFragmentOrigin,.usesFontLeading],
                                                         attributes: attrs, context: nil).height
                (text as NSString).draw(in: CGRect(x: maxRect.minX, y: y, width: maxRect.width, height: h), withAttributes: attrs)
                y += h + 8
            }

            draw("GYM DAY PLAN", font: .boldSystemFont(ofSize: 20))
            draw(plan.title, font: .systemFont(ofSize: 14))
            draw(DateFormatter.localizedString(from: plan.date, dateStyle: .medium, timeStyle: .none),
                 font: .systemFont(ofSize: 12), color: .secondaryLabel)

            // Warmup
            y += 6; draw("Warm‑Up", font: .boldSystemFont(ofSize: 16))
            for w in plan.warmup { draw("• \(w)", font: .systemFont(ofSize: 12), indent: 10) }

            // Blocks
            for (idx, block) in plan.mainBlocks.enumerated() {
                y += 6
                draw("\(idx+1). \(block.blockTitle)", font: .boldSystemFont(ofSize: 16))
                for item in block.items {
                    let ex = item.exercise
                    let s = item.scheme
                    let line = "• \(ex.name) — \(s.sets)x\(s.reps.lowerBound)–\(s.reps.upperBound), Rest \(s.restSec)s, \(s.notes)"
                    draw(line, font: .systemFont(ofSize: 12), indent: 10)
                    draw("  \(ex.coaching)", font: .italicSystemFont(ofSize: 11), color: .secondaryLabel, indent: 10)
                }
            }

            // Conditioning
            if !plan.conditioning.isEmpty {
                y += 6; draw("Conditioning", font: .boldSystemFont(ofSize: 16))
                for c in plan.conditioning { draw("• \(c)", font: .systemFont(ofSize: 12), indent: 10) }
            }

            // Cooldown
            y += 6; draw("Cool‑Down", font: .boldSystemFont(ofSize: 16))
            for c in plan.cooldown { draw("• \(c)", font: .systemFont(ofSize: 12), indent: 10) }

            // Notes
            if !plan.notes.isEmpty {
                y += 6; draw("Notes", font: .boldSystemFont(ofSize: 16))
                for n in plan.notes { draw("• \(n)", font: .systemFont(ofSize: 12), indent: 10) }
            }
        }
        return url
    }
}

// MARK: - SwiftUI UI

struct GymPlannerView: View {
    @Environment(\.dismiss) private var dismiss

    // Inputs
    @State private var goal: GymGoal = .acft
    @State private var focus: GymFocus = .acftStrength
    @State private var level: TrainingLevel = .intermediate
    @State private var minutes: Double = 60
    @State private var equipment: Set<Equipment> = [.bodyweight, .barbell, .dumbbell, .kettlebell, .medball, .sled, .track]

    // Output
    @State private var plan: GymDayPlan? = nil
    @State private var exportURL: URL? = nil
    @State private var showShare = false
    @State private var alert: AlertItem? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal & Focus") {
                    Picker("Primary Goal", selection: $goal) {
                        ForEach(GymGoal.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Day Focus", selection: $focus) {
                        ForEach(GymFocus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Training Level", selection: $level) {
                        ForEach(TrainingLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    HStack {
                        Text("Time (min)")
                        Slider(value: $minutes, in: 30...90, step: 5)
                        Text("\(Int(minutes))")
                            .monospacedDigit()
                    }
                }

                Section("Available Equipment") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(Equipment.allCases) { eq in
                            Toggle(eq.rawValue, isOn: Binding(
                                get: { equipment.contains(eq) },
                                set: { newVal in
                                    if newVal { equipment.insert(eq) } else { equipment.remove(eq) }
                                })
                            )
                        }
                    }
                }

                Section {
                    Button {
                        plan = GymPlanGenerator.generate(
                            focus: focus,
                            goal: goal,
                            level: level,
                            equipment: equipment,
                            minutes: Int(minutes)
                        )
                    } label: {
                        Label("Generate Plan", systemImage: "dumbbell")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let plan {
                    Section("Preview") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.title).font(.headline)
                            Text(plan.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            Divider()
                            Text("Warm‑Up").bold()
                            ForEach(plan.warmup, id: \.self) { Text("• \($0)") }
                            ForEach(plan.mainBlocks.indices, id: \.self) { i in
                                let block = plan.mainBlocks[i]
                                Text("\(i+1). \(block.blockTitle)").bold().padding(.top, 4)
                                ForEach(block.items) { item in
                                    Text("• \(item.exercise.name) — \(item.scheme.sets)x\(item.scheme.reps.lowerBound)–\(item.scheme.reps.upperBound)")
                                        .font(.callout)
                                }
                            }
                            if !plan.conditioning.isEmpty {
                                Text("Conditioning").bold().padding(.top, 4)
                                ForEach(plan.conditioning, id: \.self) { Text("• \($0)") }
                            }
                        }
                    }

                    Section {
                        Button {
                            do {
                                exportURL = try GymPDFRenderer.render(plan: plan)
                                showShare = true
                            } catch {
                                alert = AlertItem(message: "PDF export failed: \(error.localizedDescription)")
                            }
                        } label: { Label("Export PDF", systemImage: "doc.richtext") }
                    }
                }
            }
            .navigationTitle("Gym Day Planner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(item: $alert) { item in
                Alert(title: Text("Notice"), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showShare) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
}


