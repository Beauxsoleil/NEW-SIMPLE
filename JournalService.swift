//
//  JournalService.swift
//  ROPS — Journal bridge (iOS 16+; optional suggestions iOS 17.2+)
//

import Foundation
import SwiftUI

// MARK: - Composer

enum JournalScope: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case last7Days = "Last 7 Days"
    case custom = "Custom Range"
    var id: String { rawValue }
}

struct JournalComposer {
    static func makeEntry(store: Store, start: Date, end: Date) -> String {
        let cal = Calendar.current
        let inRange: (Date) -> Bool = { d in cal.compare(d, to: start, toGranularity: .minute) != .orderedAscending &&
                                         cal.compare(d, to: end,   toGranularity: .minute) == .orderedAscending }

        // 1) Events
        let events = store.events.filter { inRange($0.start) }.sorted { $0.start < $1.start }

        // 2) New Applicants (createdAt)
        let newApplicants = store.applicants
            .filter { inRange($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }

        // 3) New Enlistments
        let newEnlistments = store.applicants
            .compactMap { a -> (Applicant, Date)? in
                guard let d = a.enlistedDate else { return nil }; return (a, d)
            }
            .filter { inRange($0.1) }
            .sorted { $0.1 < $1.1 }

        // Headline + sections
        var lines: [String] = []
        let df = DateFormatter(); df.dateStyle = .medium
        lines.append("🗒️ ROPS Journal — \(df.string(from: start)) to \(df.string(from: end))")
        lines.append("")

        // Events section
        lines.append("📅 Events")
        if events.isEmpty {
            lines.append("• None")
        } else {
            for e in events {
                let date = e.start.formatted(date: .abbreviated, time: .shortened)
                let loc  = e.location.map { " @ \($0)" } ?? ""
                let names = e.relatedApplicantIDs.compactMap { id in
                    store.applicants.first(where: { $0.id == id })?.fullName
                }.joined(separator: ", ")
                var row = "• \(date) — \(e.title) (\(e.type.rawValue))\(loc)"
                if !names.isEmpty { row += " — Related: \(names)" }
                if let notes = e.notes, !notes.isEmpty { row += " — Notes: \(notes)" }
                lines.append(row)
            }
        }
        lines.append("")

        // New Applicants section
        lines.append("🆕 New Applicants")
        if newApplicants.isEmpty {
            lines.append("• None")
        } else {
            for a in newApplicants {
                let when = a.createdAt.formatted(date: .abbreviated, time: .shortened)
                lines.append("• \(a.fullName) — added \(when)")
            }
        }
        lines.append("")

        // Enlistments section
        lines.append("🎖️ New Enlistments")
        if newEnlistments.isEmpty {
            lines.append("• None")
        } else {
            for (a, d) in newEnlistments {
                let when = d.formatted(date: .abbreviated, time: .omitted)
                lines.append("• \(a.fullName) — enlisted \(when)")
            }
        }
        lines.append("")

        // Quick stats
        let warn = store.settings.aging.warn
        let danger = store.settings.aging.danger
        let red = store.applicants.filter { $0.daysSinceActivity >= danger }.count
        let yellow = store.applicants.filter { let d = $0.daysSinceActivity; return d >= warn && d < danger }.count
        lines.append("📊 Touchpoints: \(red) red, \(yellow) yellow")

        return lines.joined(separator: "\n")
    }
}

// MARK: - SwiftUI screen that hooks into existing ShareSheet

struct JournalConnectorView: View {
    @EnvironmentObject var store: Store

    @State private var scope: JournalScope = .thisWeek
    @State private var start: Date = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    @State private var end:   Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    @State private var preview: String = ""
    @State private var showShare: Bool = false
    @State private var shareItems: [Any] = []

    var body: some View {
        Form {
            Section("Range") {
                Picker("Scope", selection: $scope) {
                    ForEach(JournalScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if scope == .custom {
                    DatePicker("Start", selection: $start)
                    DatePicker("End",   selection: $end)
                } else {
                    HStack {
                        Text("Start"); Spacer(); Text(start.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("End"); Spacer(); Text(end.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Preview") {
                TextEditor(text: .constant(preview))
                    .font(.callout)
                    .frame(minHeight: 220)
                    .disabled(true)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                // Optional: Apple “Journaling Suggestions” picker (iOS 17.2+)
                #if canImport(JournalingSuggestions)
                if #available(iOS 17.2, *) {
                    JournalingSuggestionsButton { suggestionText in
                        preview.append("\n\n— Apple Suggestion —\n\(suggestionText)")
                    }
                }
                #endif
            }

            Section {
                Button {
                    shareItems = [preview]        // Share string directly (Journal appears as a share target)
                    showShare = true
                } label: {
                    Label("Share to Apple Journal", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Compose Journal")
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: shareItems)
        }
        .onAppear { recalc() }
        .onChange(of: scope) { _ in recalc() }
        .onChange(of: start) { _ in recalc() }
        .onChange(of: end)   { _ in recalc() }
    }

    private func recalc() {
        switch scope {
        case .thisWeek:
            let cal = Calendar.current
            start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
            end   = cal.date(byAdding: .day, value: 7, to: start) ?? start
        case .last7Days:
            end   = Date()
            start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        case .custom:
            break
        }
        preview = JournalComposer.makeEntry(store: store, start: start, end: end)
    }
}

// MARK: - (Optional) Apple Journaling Suggestions button

#if canImport(JournalingSuggestions)
import JournalingSuggestions

@available(iOS 17.2, *)
fileprivate struct JournalingSuggestionsButton: View {
    var onAppend: (String) -> Void
    init(_ onAppend: @escaping (String) -> Void) { self.onAppend = onAppend }

    var body: some View {
        JournalingSuggestionsPicker(label: {
            Label("Add Apple Suggestions", systemImage: "sparkles")
        }) { selection in
            // Convert the selection into plain text we can append to the preview
            // The specific assets vary (photos, locations, workouts, reflections)
            // We keep it simple and print titles + any summary available.
            var bits: [String] = []
            for suggestion in selection {
                bits.append("• " + (suggestion.title ?? "Suggestion"))
                if let summary = suggestion.summary { bits.append("   \(summary)") }
            }
            onAppend(bits.joined(separator: "\n"))
        }
        .buttonStyle(.bordered)
    }
}
#endif
