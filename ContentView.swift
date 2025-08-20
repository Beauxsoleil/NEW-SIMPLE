//
//  ROPS_ContentView.swift
//  ROPS (Recruiter Ops) — MVP Basics (ContentView only, no @main)
//  iOS 16+ baseline. No external packages.
//
//  Included:
//  - Applicant Inbox (CRUD, search, stage filter)
//  - Aging indicator (configurable thresholds)
//  - Height/Weight quick check + placeholder one-site tape prompt when overweight
//  - Checklist with synonyms (SSN/BC/DL/…)
//  - Per-applicant “Files” metadata (scan/OCR later)
//  - PDF export grouped by stage, optional logo from Settings
//  - JSON import/export (Applicants/Events/Settings merge by UUID)
//  - Settings with logo picker, theme, thresholds, recruiter info
//  - Pac-Man style “Trout Run” mini-game (trout vs. Sasquatches)
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import EventKit
import MessageUI
import UserNotifications
import Vision
import VisionKit
import QuickLook
import QuickLookThumbnailing

// MARK: - Persistence Envelope & Aging Config

struct StoreEnvelope<T: Codable>: Codable {
    var schema: Int = 3
    var payload: [T]
}

struct AgingConfig: Codable, Equatable {
    var warn: Int = 7
    var danger: Int = 14
}

// MARK: - Small Helper: Optional -> Non-optional Binding for TextField

/// Safely unwraps a `Binding<String?>` to a `Binding<String>` for use with `TextField`.
/// - Behavior: writes back `nil` when the user clears the field (empty string).
fileprivate func NonOptionalBinding(_ source: Binding<String?>, default def: String = "") -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue ?? def },
        set: { newVal in source.wrappedValue = newVal.isEmpty ? nil : newVal }
    )
}

/// Converts an optional `Int` binding to a `String` binding for numeric `TextField`s.
fileprivate func IntBinding(_ source: Binding<Int?>) -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue.map(String.init) ?? "" },
        set: { newVal in source.wrappedValue = Int(newVal) }
    )
}

fileprivate func DoubleBinding(_ source: Binding<Double?>) -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue.map { String($0) } ?? "" },
        set: { newVal in source.wrappedValue = Double(newVal) }
    )
}

fileprivate func DateBinding(_ source: Binding<Date?>, default def: Date = Date()) -> Binding<Date> {
    Binding<Date>(
        get: { source.wrappedValue ?? def },
        set: { newVal in source.wrappedValue = newVal }
    )
}

// MARK: - Constants & Helpers

fileprivate enum ROPSConst {
    static let appName = "ROPS"
    static let storeFile = "applicants_v2.json"
    static let eventsFile = "events_v1.json"
    static let settingsFile = "rops_settings.json"
    static let logoFile = "rops_logo.png"
    static let pdfDefault = "ROPS_Applicants.pdf"
}

fileprivate func appSupportDir() throws -> URL {
    let fm = FileManager.default
    let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let bundle = Bundle.main.bundleIdentifier ?? "ROPS"
    let dir = base.appendingPathComponent(bundle, isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

fileprivate func applicantFilesDir(applicantID: UUID) throws -> URL {
    let base = try appSupportDir().appendingPathComponent("Applicants", isDirectory: true)
    let dir = base.appendingPathComponent(applicantID.uuidString, isDirectory: true)
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

fileprivate enum FileStore {
    static func importFile(for applicantID: UUID, from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let destDir = try applicantFilesDir(applicantID: applicantID)
        let cleanName = sourceURL.lastPathComponent.replacingOccurrences(of: ":", with: "_")
        var dest = destDir.appendingPathComponent(cleanName)
        var idx = 1
        while fm.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            dest = destDir.appendingPathComponent("\(base)-\(idx).\(ext.isEmpty ? "dat" : ext)")
            idx += 1
        }
        do { try fm.copyItem(at: sourceURL, to: dest) }
        catch {
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: dest, options: .atomic)
        }
        return dest
    }

    static func removeFile(at relativePath: String) {
        do {
            let abs = try appSupportDir()
                .appendingPathComponent("Applicants", isDirectory: true)
                .appendingPathComponent(relativePath)
            try FileManager.default.removeItem(at: abs)
        } catch { print("Remove file error: \(error)") }
    }

    static func absoluteURL(from relativePath: String) -> URL? {
        do {
            return try appSupportDir()
                .appendingPathComponent("Applicants", isDirectory: true)
                .appendingPathComponent(relativePath)
        } catch { return nil }
    }

    static func relativePath(for url: URL) -> String? {
        guard let root = try? appSupportDir().appendingPathComponent("Applicants", isDirectory: true) else { return nil }
        let path = url.path
        guard path.hasPrefix(root.path) else { return nil }
        return String(path.dropFirst(root.path.count + (root.path.hasSuffix("/") ? 0 : 1)))
    }

    static func removeAll(for applicantID: UUID) {
        do {
            let dir = try applicantFilesDir(applicantID: applicantID)
            try FileManager.default.removeItem(at: dir)
        } catch { print("Remove applicant files error: \(error)") }
    }
}

fileprivate extension Date {
    func daysSince(_ other: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: other)
        let b = cal.startOfDay(for: self)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
    var yyyymmdd: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

fileprivate extension Color {
    static let subtleBG = Color(UIColor.secondarySystemBackground)
}

// MARK: - Theme

struct ROPSTheme: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let tintHex: String
    var tint: Color { Color(hex: tintHex) ?? .accentColor }

    static let all: [ROPSTheme] = [
        .init(id: "calm",   name: "Calm",   tintHex: "#4C86F7"),
        .init(id: "mint",   name: "Mint",   tintHex: "#2DBA2A"),
        .init(id: "plum",   name: "Plum",   tintHex: "#582CF7"),
        .init(id: "amber",  name: "Amber",  tintHex: "#F7A900"),
        .init(id: "oxide",  name: "Oxide",  tintHex: "#687280"),
    ]
    static let `default` = all.first!
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { _ = s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v & 0xFF0000) >> 16) / 255.0
            g = Double((v & 0x00FF00) >> 8) / 255.0
            b = Double(v & 0x0000FF) / 255.0
            self = Color(red: r, green: g, blue: b)
        } else {
            return nil
        }
    }

}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Models

enum Stage: String, CaseIterable, Codable, Identifiable {
    case newLead = "New Lead"
    case screening = "Screening"
    case docs = "Documents"
    case meps = "MEPS"
    case enlisted = "Enlisted"
    case shipped = "Shipped"

    var id: String { rawValue }
    var sortOrder: Int {
        switch self {
        case .newLead: return 0
        case .screening: return 1
        case .docs: return 2
        case .meps: return 3
        case .enlisted: return 4
        case .shipped: return 5
        }
    }
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var canonicalName: String
    var isCollected: Bool
    var notes: String = ""
}

struct FileNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note: String
    var filePath: String? = nil
    var addedAt: Date = Date()
}

struct ACFTEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var event: String
    var raw: Int?
    var points: Int?
}

struct RecruitEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var type: EventType
    var start: Date
    var end: Date
    var location: String?
    var relatedApplicantIDs: [UUID] = []
    var needs: [String] = []
    var notes: String?
    var notify1SG: Bool = false
    var addToCalendar: Bool = true
    var includeInMondayReport: Bool = true
    var reminders: [Int] = [60]
    var ekIdentifier: String? = nil
}

enum EventType: String, Codable, CaseIterable, Identifiable {
    case schoolVisit = "School Visit"
    case careerFair = "Career Fair"
    case mepsTrip = "MEPS Trip"
    case appAppointment = "App Appointment"
    case other = "Other"
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "DEP Function" { self = .appAppointment }
        else { self = EventType(rawValue: raw) ?? .other }
    }
}

final class CalendarService {
    enum CalendarError: LocalizedError {
        case noCalendar
        var errorDescription: String? { "No available calendar" }
    }

    let store = EKEventStore()
    func requestAccess() async throws {
        let granted = try await store.requestAccess(to: .event)
        print("Calendar access granted: \(granted)")
    }

    func calendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func createCalendar(named title: String) throws -> EKCalendar {
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = title
        cal.source = store.defaultCalendarForNewEvents?.source ?? store.sources.first { $0.sourceType == .local }!
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    func makeEvent(from e: RecruitEvent, calendarID: String?) throws -> EKEvent {
        let calendar: EKCalendar
        if let id = calendarID, let c = store.calendar(withIdentifier: id) {
            calendar = c
        } else if let c = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first {
            calendar = c
        } else {
            throw CalendarError.noCalendar
        }
        let ek: EKEvent
        if let id = e.ekIdentifier, let existing = store.event(withIdentifier: id) {
            ek = existing
            ek.calendar = calendar
        } else {
            ek = EKEvent(eventStore: store)
            ek.calendar = calendar
        }
        ek.title = e.title
        ek.startDate = e.start
        ek.endDate = e.end
        ek.location = e.location
        ek.notes = e.notes
        print("Using calendar: \(calendar.title)")
        return ek
    }

    func deleteEvent(identifier: String) {
        if let ek = store.event(withIdentifier: identifier) {
            try? store.remove(ek, span: .thisEvent)
        }
    }

    func debugCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("Calendar authorization status: \(status.rawValue)")
        let cals = calendars()
        print("Calendars available: \(cals.map { $0.title })")
        if let def = store.defaultCalendarForNewEvents {
            print("Default calendar: \(def.title)")
        }
    }

    func testEvent(calendarID: String?) {
        let start = Date().addingTimeInterval(300)
        let end = start.addingTimeInterval(60)
        let ek = EKEvent(eventStore: store)
        ek.title = "ROPS Test Event"
        ek.startDate = start
        ek.endDate = end
        if let id = calendarID, let c = store.calendar(withIdentifier: id) {
            ek.calendar = c
        } else if let c = store.defaultCalendarForNewEvents ?? calendars().first {
            ek.calendar = c
        }
        do {
            try store.save(ek, span: .thisEvent)
            if let cal = ek.calendar { print("Test event saved to \(cal.title)") }
        } catch {
            print("Test event error: \(error)")
        }
    }
}

final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            print("Notification access granted: \(granted)")
        } catch {
            print("Notification access error: \(error)")
        }
    }

    func scheduleSASReminder(for id: UUID, name: String, frequency: SASReminderFrequency, hour: Int, minute: Int) {
        cancelSASReminder(id: id)
        guard frequency != .none else { return }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        switch frequency {
        case .daily:
            break
        case .weekly:
            comps.weekday = Calendar.current.component(.weekday, from: Date())
        case .monthly:
            comps.day = Calendar.current.component(.day, from: Date())
        case .none:
            return
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "SAS Follow-up"
        content.body = "Check in with \(name)."
        let req = UNNotificationRequest(identifier: "SAS-\(id.uuidString)", content: content, trigger: trigger)
        center.add(req)
    }

    func scheduleAgingSummary(red: Int, yellow: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["AgingDaily"])
        var comps = DateComponents()
        comps.hour = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "ROPS Aging Check"
        content.body = "\u{26A0}\u{FE0F} \(red) red, \(yellow) yellow applicants need touch today"
        let req = UNNotificationRequest(identifier: "AgingDaily", content: content, trigger: trigger)
        center.add(req)
    }

    func cancelSASReminder(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["SAS-\(id.uuidString)"])
    }

    func testSASReminder() {
        let content = UNMutableNotificationContent()
        content.title = "SAS Reminder Test"
        content.body = "This is a test reminder."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let req = UNNotificationRequest(identifier: "SASTest", content: content, trigger: trigger)
        center.add(req)
    }
}

// MARK: - Body Composition

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

struct HTWTRow: Decodable {
    let heightIn: Int
    let minWeight: Int
    let male17_20: Int, male21_27: Int, male28_39: Int, male40plus: Int
    let female17_20: Int, female21_27: Int, female28_39: Int, female40plus: Int
}

struct BFStandard: Decodable {
    let minAge: Int, maxAge: Int
    let maleMaxPct: Int, femaleMaxPct: Int
}

struct OneSiteCell: Decodable {
    let waistIn: Int
    let values: [String:Int]
}
final class BodyCompService {
    static let shared = BodyCompService()
    private(set) var htwt: [HTWTRow] = []
    private(set) var bfLimits: [BFStandard] = []
    private(set) var maleChart: [OneSiteCell] = []
    private(set) var femaleChart: [OneSiteCell] = []

    func load() {
        htwt = parseHTWT(csv: BodyCompTables.embeddedHTWT)
        bfLimits = parseBFLimits(csv: BodyCompTables.embeddedBFLimits)
        maleChart = parseOneSite(csv: BodyCompTables.embeddedOneSiteMale)
        femaleChart = parseOneSite(csv: BodyCompTables.embeddedOneSiteFemale)
    }

    private func parseHTWT(csv: String) -> [HTWTRow] {
        csv
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let c = line.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                guard c.count >= 10 else { return nil }
                return HTWTRow(heightIn: c[0], minWeight: c[1], male17_20: c[2], male21_27: c[3], male28_39: c[4], male40plus: c[5], female17_20: c[6], female21_27: c[7], female28_39: c[8], female40plus: c[9])
            }
    }
    private func parseBFLimits(csv: String) -> [BFStandard] {
        csv
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let c = line.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                guard c.count >= 4 else { return nil }
                return BFStandard(minAge: c[0], maxAge: c[1], maleMaxPct: c[2], femaleMaxPct: c[3])
            }
    }

    private func parseOneSite(csv: String) -> [OneSiteCell] {
        let lines = csv.split(separator: "\n")
        guard let header = lines.first?.split(separator: ",").dropFirst().map({ String($0) }) else { return [] }
        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: ",").map { String($0) }
            guard let waist = parts.first.flatMap({ Int($0) }) else { return nil }
            var vals: [String:Int] = [:]
            for (idx, key) in header.enumerated() {
                if idx + 1 < parts.count {
                    vals[key] = Int(parts[idx+1]) ?? 0
                }
            }
            return OneSiteCell(waistIn: waist, values: vals)
        }
    }

    func allowedWeight(heightIn: Int, sex: Sex, age: Int) -> Int? {
        guard let row = htwt.first(where: { $0.heightIn == heightIn }) else { return nil }
        switch (sex, age) {
        case (.male, 17...20): return row.male17_20
        case (.male, 21...27): return row.male21_27
        case (.male, 28...39): return row.male28_39
        case (.male, 40...150): return row.male40plus
        case (.female, 17...20): return row.female17_20
        case (.female, 21...27): return row.female21_27
        case (.female, 28...39): return row.female28_39
        case (.female, 40...150): return row.female40plus
        default: return nil
        }
    }

    func maxBodyFatPercent(sex: Sex, age: Int) -> Int? {
        guard let row = bfLimits.first(where: { $0.minAge...$0.maxAge ~= age }) else { return nil }
        return sex == .male ? row.maleMaxPct : row.femaleMaxPct
    }

    func oneSitePercent(sex: Sex, waistIn: Int, bodyWeightLb: Int) -> Int? {
        let chart = (sex == .male) ? maleChart : femaleChart
        guard let row = nearest(in: chart, toWaist: waistIn) else { return nil }
        let stepped = (bodyWeightLb / 5) * 5
        let key = "w\(stepped)"
        if let exact = row.values[key] { return exact }
        return nearestValue(in: row.values, for: bodyWeightLb)
    }

    private func nearest(in chart: [OneSiteCell], toWaist waist: Int) -> OneSiteCell? {
        chart.min(by: { abs($0.waistIn - waist) < abs($1.waistIn - waist) })
    }

    private func nearestValue(in dict: [String:Int], for weight: Int) -> Int? {
        let numeric = dict.compactMap { key, val -> (Int,Int)? in
            guard let w = Int(key.dropFirst()) else { return nil }
            return (w, val)
        }
        guard var best = numeric.first else { return nil }
        for pair in numeric {
            if abs(pair.0 - weight) < abs(best.0 - weight) { best = pair }
        }
        return best.1
    }
}

struct BodyCompResult {
    enum Status { case passNoTape, needsTape, passOnSite, failOnSite }
    let status: Status
    let screeningLimit: Int?
    let measuredBF: Int?
    let maxBF: Int?
}

func evaluateBodyComp(applicant: Applicant, sex: Sex, age: Int) -> BodyCompResult {
    let svc = BodyCompService.shared
    guard let h = applicant.heightInInches, let w = applicant.weightInPounds else {
        return .init(status: .needsTape, screeningLimit: nil, measuredBF: nil, maxBF: nil)
    }
    let heightRounded = Int((h + 0.5).rounded(.down))
    let screen = svc.allowedWeight(heightIn: heightRounded, sex: sex, age: age)
    if let s = screen, Int(w) <= s {
        return .init(status: .passNoTape, screeningLimit: s, measuredBF: nil, maxBF: nil)
    }
    guard let waist = applicant.waistInInches,
          let bf = svc.oneSitePercent(sex: sex, waistIn: Int(waist.rounded()), bodyWeightLb: Int(w)),
          let maxBF = svc.maxBodyFatPercent(sex: sex, age: age) else {
        return .init(status: .needsTape, screeningLimit: screen, measuredBF: nil, maxBF: nil)
    }
    let status: BodyCompResult.Status = (bf <= maxBF) ? .passOnSite : .failOnSite
    return .init(status: status, screeningLimit: screen, measuredBF: bf, maxBF: maxBF)
}

struct Applicant: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()

    var fullName: String
    var age: Int?
    var sex: Sex = .male
    var priorService: Bool
    var physicalHealth: String
    var legalIssues: String
    var educationLevel: String
    var medicalFlags: [MedicalFlag] = []
    var legalHistory: [LegalDisqualifier] = []
    var interestLevel: Int = 0
    var maritalStatus: String
    var dependents: Int
    var hasTattoos: Bool
    var tattoosNotes: String
    var phone: String
    var address: String?   // optional; use NonOptionalBinding in UI

    var stage: Stage
    var stageStart: Date
    var enlistedDate: Date? = nil
    var drillDate1: Date? = nil
    var drillDate2: Date? = nil

    var heightInInches: Double?
    var weightInPounds: Double?
    var waistInInches: Double?

    var checklist: [ChecklistItem]
    var notes: String
    var files: [FileNote]
    var acft: [ACFTEntry] = []

    // v2 additions
    var issues: [String] = []
    var agingDays: Int? = nil
    var serviceAfterSale: Bool = false
    var lastActivityAt: Date? = nil
    var archived: Bool = false
    var sasFrequency: SASReminderFrequency = .none
}

extension Applicant {
    var daysSinceActivity: Int {
        let base = lastActivityAt ?? updatedAt
        return Calendar.current.dateComponents([.day], from: base, to: Date()).day ?? 0
    }
}

enum SASReminderFrequency: String, Codable, CaseIterable, Identifiable {
    case none = "Off"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    var id: String { rawValue }
}

struct SettingsModel: Codable, Equatable {
    var recruiterName: String = ""
    var recruiterInitials: String = ""
    var rsid: String = ""
    var themeID: String = ROPSTheme.default.id
    var aging: AgingConfig = AgingConfig()
    var logoStored: Bool = false
    var calendarID: String? = nil
    var sasReminderHour: Int = 9
    var sasReminderMinute: Int = 0

    enum CodingKeys: String, CodingKey {
        case recruiterName, recruiterInitials, rsid, themeID, aging, logoStored, calendarID, agingWarnDays, agingAlertDays, sasReminderHour, sasReminderMinute
    }

    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recruiterName = try container.decodeIfPresent(String.self, forKey: .recruiterName) ?? ""
        recruiterInitials = try container.decodeIfPresent(String.self, forKey: .recruiterInitials) ?? ""
        rsid = try container.decodeIfPresent(String.self, forKey: .rsid) ?? ""
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? ROPSTheme.default.id
        if let cfg = try container.decodeIfPresent(AgingConfig.self, forKey: .aging) {
            aging = cfg
        } else {
            let warn = try container.decodeIfPresent(Int.self, forKey: .agingWarnDays) ?? 7
            let danger = try container.decodeIfPresent(Int.self, forKey: .agingAlertDays) ?? 14
            aging = AgingConfig(warn: warn, danger: danger)
        }
        logoStored = try container.decodeIfPresent(Bool.self, forKey: .logoStored) ?? false
        calendarID = try container.decodeIfPresent(String.self, forKey: .calendarID)
        sasReminderHour = try container.decodeIfPresent(Int.self, forKey: .sasReminderHour) ?? 9
        sasReminderMinute = try container.decodeIfPresent(Int.self, forKey: .sasReminderMinute) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recruiterName, forKey: .recruiterName)
        try container.encode(recruiterInitials, forKey: .recruiterInitials)
        try container.encode(rsid, forKey: .rsid)
        try container.encode(themeID, forKey: .themeID)
        try container.encode(aging, forKey: .aging)
        try container.encode(logoStored, forKey: .logoStored)
        try container.encode(calendarID, forKey: .calendarID)
        try container.encode(sasReminderHour, forKey: .sasReminderHour)
        try container.encode(sasReminderMinute, forKey: .sasReminderMinute)
    }
}

// MARK: - Checklist Lexicon

fileprivate enum ChecklistLexicon {
    static let aliasMap: [String:[String]] = [
        "Social Security Card": ["ssn","ss","ss card","social","social security","social security card"],
        "Birth Certificate": ["bc","birth cert","birth certificate"],
        "Driver's License": ["dl","driver license","drivers license","driver's license","license"]
    ]
    static var canonical: [String] { Array(aliasMap.keys) }

    static func canonicalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (canon, aliases) in aliasMap {
            if aliases.contains(s) || canon.lowercased() == s { return canon }
        }
        return raw
    }

    static func inferDocKey(_ text: String) -> String? {
        let s = text.lowercased()
        for (canon, aliases) in aliasMap {
            if s.contains(canon.lowercased()) { return canon }
            if aliases.first(where: { s.contains($0) }) != nil { return canon }
        }
        return nil
    }

    static func defaults() -> [ChecklistItem] {
        canonical.map { .init(canonicalName: $0, isCollected: false) }
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var applicants: [Applicant] = [] { didSet { saveApplicants() } }
    @Published var events: [RecruitEvent] = [] { didSet { saveEvents() } }
    @Published var settings: SettingsModel = .init()

    // UI (non-persisted)
    @Published var search: String = ""
    @Published var stageFilter: Stage? = nil
    @Published var hideArchived: Bool = true

    init() {
        BodyCompService.shared.load()
        loadApplicants()
        loadEvents()
        loadSettings()
    }

    // Persistence
    func saveApplicants() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.storeFile)
            let env = StoreEnvelope(schema: 3, payload: applicants.sorted { $0.createdAt > $1.createdAt })
            let data = try JSONEncoder().encode(env)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch { print("Save error: \(error)") }
    }
    func loadApplicants() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.storeFile)
            guard let data = try? Data(contentsOf: url) else { return }
            if let env = try? JSONDecoder().decode(StoreEnvelope<Applicant>.self, from: data) {
                applicants = migrateIfNeeded(env)
            } else if let old = try? JSONDecoder().decode([Applicant].self, from: data) {
                applicants = old.map { var a = $0; a.agingDays = Date().daysSince(a.createdAt); return a }
            }
        } catch { print("Load error: \(error)") }
    }

    func saveEvents() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.eventsFile)
            let data = try JSONEncoder().encode(events.sorted { $0.start < $1.start })
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch { print("Event save error: \(error)") }
    }

    func loadEvents() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.eventsFile)
            guard let data = try? Data(contentsOf: url) else { return }
            events = (try? JSONDecoder().decode([RecruitEvent].self, from: data)) ?? []
        } catch { print("Event load error: \(error)") }
    }

    private func migrateIfNeeded(_ env: StoreEnvelope<Applicant>) -> [Applicant] {
        var out = env.payload
        if env.schema < 2 {
            out = out.map { var a = $0; if a.lastActivityAt == nil { a.lastActivityAt = a.updatedAt }; return a }
        }
        if env.schema < 3 {
            // Placeholder for future migrations
        }
        return out
    }

    func saveSettings() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.settingsFile)
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
        } catch { print("Settings save error: \(error)") }
    }
    func loadSettings() {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.settingsFile)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                settings = try JSONDecoder().decode(SettingsModel.self, from: data)
            }
        } catch { print("Settings load error: \(error)") }
    }

    // Whole-app snapshot for JSON round-trips
    struct ExportEnvelope: Codable {
        var applicants: [Applicant]
        var events: [RecruitEvent]
        var settings: SettingsModel
    }

    // JSON Export/Import
    func exportJSON() throws -> URL {
        // Keep events/settings so re-import doesn't lose information
        let dump = ExportEnvelope(applicants: applicants, events: events, settings: settings)
        let data = try JSONEncoder().encode(dump)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ROPS_Full_\(Date().yyyymmdd).json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func importJSON(from url: URL) throws -> (appsAdded: Int, appsUpdated: Int, eventsAdded: Int, eventsUpdated: Int) {
        let data = try Data(contentsOf: url)
        if let dump = try? JSONDecoder().decode(ExportEnvelope.self, from: data) {
            // Applicants merge by UUID
            var aDict = Dictionary(uniqueKeysWithValues: applicants.map { ($0.id, $0) })
            var aAdded = 0, aUpdated = 0
            for a in dump.applicants {
                if aDict[a.id] == nil { aAdded += 1 } else { aUpdated += 1 }
                aDict[a.id] = a
            }
            applicants = Array(aDict.values)

            // Events merge by UUID
            var eDict = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
            var eAdded = 0, eUpdated = 0
            for e in dump.events {
                if eDict[e.id] == nil { eAdded += 1 } else { eUpdated += 1 }
                eDict[e.id] = e
            }
            events = Array(eDict.values)

            // Settings overwrite; user initiated import
            settings = dump.settings

            return (aAdded, aUpdated, eAdded, eUpdated)
        } else {
            // Backward compatibility: older exports were applicants array only
            let incoming = try JSONDecoder().decode([Applicant].self, from: data)
            var dict = Dictionary(uniqueKeysWithValues: applicants.map { ($0.id, $0) })
            var added = 0, updated = 0
            for a in incoming {
                if dict[a.id] == nil { added += 1 } else { updated += 1 }
                dict[a.id] = a
            }
            applicants = Array(dict.values)
            return (added, updated, 0, 0)
        }
    }

    // Logo
    func storeLogo(_ image: UIImage) {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.logoFile)
            if let data = image.pngData() {
                try data.write(to: url, options: .atomic)
                settings.logoStored = true
                saveSettings()
            }
        } catch { print("Logo store error: \(error)") }
    }
    func loadLogo() -> UIImage? {
        do {
            let dir = try appSupportDir()
            let url = dir.appendingPathComponent(ROPSConst.logoFile)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return UIImage(contentsOfFile: url.path)
        } catch { return nil }
    }
}

// MARK: - ContentView (Tabs)

struct ContentView: View {
    @StateObject private var store = Store()
    private let notif = NotificationService()

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "speedometer") }
            ApplicantInboxView()
                .tabItem { Label("Inbox", systemImage: "tray.full") }
            SASView()
                .tabItem { Label("SAS", systemImage: "checkmark.seal") }
            WorkStationView()
                .tabItem { Label("Work Station", systemImage: "wrench.and.screwdriver") }
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
            ReportsView()
                .tabItem { Label("Reports", systemImage: "doc.richtext") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(theme.tint)
        .environmentObject(store)
        .onAppear {
            Task { await notif.requestAuthorization() }
            scheduleAgingNotification()
        }
    }

    var theme: ROPSTheme {
        ROPSTheme.all.first(where: { $0.id == store.settings.themeID }) ?? .default
    }

    func scheduleAgingNotification() {
        let warn = store.settings.aging.warn
        let danger = store.settings.aging.danger
        let red = store.applicants.filter { $0.daysSinceActivity >= danger }.count
        let yellow = store.applicants.filter { let d = $0.daysSinceActivity; return d >= warn && d < danger }.count
        notif.scheduleAgingSummary(red: red, yellow: yellow)
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    gauges
                    thisWeek
                    quickLinks
                }
                .padding()
            }
            .navigationTitle("Dashboard")
        }
    }

    var gauges: some View {
        VStack(alignment: .leading) {
            let goal = 3.0
            let count = Double(store.applicants.filter { $0.stage == .enlisted && Calendar.current.isDate($0.stageStart, equalTo: Date(), toGranularity: .month) }.count)
            Gauge(value: count, in: 0...goal) {
                Text("Enlistments")
            } currentValueLabel: {
                Text("\(Int(count))")
            }
        }
    }

    var thisWeek: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week").font(.headline)
            let range = weekRange()
            let events = store.events.filter { range.contains($0.start) }
            if events.isEmpty {
                Text("No events").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(events) { e in
                    HStack {
                        Text(e.start, style: .date)
                        Text(e.title)
                    }
                    .font(.caption)
                }
            }
            let applicants = store.applicants.filter { a in
                if let d = a.lastActivityAt { return range.contains(d) } else { return false }
            }
            if !applicants.isEmpty {
                Divider()
                ForEach(applicants) { a in
                    Text(a.fullName).font(.caption)
                }
            }
        }
    }

    func weekRange(anchor: Date = Date()) -> Range<Date> {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        return start..<end
    }

    var quickLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts").font(.headline)
            HStack {
                NavigationLink(destination: WorkStationView()) {
                    Label("Snippets", systemImage: "text.badge.plus")
                }
                NavigationLink(destination: EventsView()) {
                    Label("Events", systemImage: "calendar")
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Applicant Inbox

struct ApplicantInboxView: View {
    @EnvironmentObject var store: Store

    var filtered: [Applicant] {
        var list = store.applicants.sorted {
            if $0.stage.sortOrder != $1.stage.sortOrder { return $0.stage.sortOrder < $1.stage.sortOrder }
            return $0.createdAt > $1.createdAt
        }
        if store.hideArchived { list = list.filter { !$0.archived } }
        if let f = store.stageFilter { list = list.filter { $0.stage == f } }
        if !store.search.isEmpty {
            let q = store.search.lowercased()
            list = list.filter {
                $0.fullName.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q) ||
                $0.phone.lowercased().contains(q) ||
                ($0.address?.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Toggle("Hide archived", isOn: $store.hideArchived)
                    .padding(.horizontal)
                List {
                    ForEach(filtered) { a in
                        NavigationLink {
                            ApplicantEditor(applicant: a)
                        } label: {
                            ApplicantRow(applicant: a)
                        }
                        .swipeActions {
                            Button(a.archived ? "Unarchive" : "Archive") {
                                if let idx = store.applicants.firstIndex(where: { $0.id == a.id }) {
                                    store.applicants[idx].archived.toggle()
                                }
                            }.tint(.gray)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Applicant Inbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let new = Applicant(
                            fullName: "New Applicant",
                            age: nil,
                            sex: .male,
                            priorService: false,
                            physicalHealth: "",
                            legalIssues: "",
                            educationLevel: "",
                            maritalStatus: "",
                            dependents: 0,
                            hasTattoos: false,
                            tattoosNotes: "",
                            phone: "",
                            address: nil,
                            stage: .newLead,
                            stageStart: Date(),
                            heightInInches: nil,
                            weightInPounds: nil,
                            waistInInches: nil,
                            checklist: ChecklistLexicon.defaults(),
                            notes: "",
                            files: []
                        )
                        store.applicants.insert(new, at: 0)
                    } label: {
                        Label("New", systemImage: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Filter by Stage", selection: $store.stageFilter) {
                            Text("All Stages").tag(Stage?.none)
                            ForEach(Stage.allCases) { s in
                                Text(s.rawValue).tag(Stage?.some(s))
                            }
                        }
                        if store.stageFilter != nil {
                            Button("Clear Filter", role: .destructive) { store.stageFilter = nil }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $store.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name, phone, notes")
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { filtered[$0].id }
        for id in ids {
            FileStore.removeAll(for: id)
            NotificationService().cancelSASReminder(id: id)
        }
        store.applicants.removeAll { ids.contains($0.id) }
    }

}

struct ApplicantRow: View {
    @EnvironmentObject var store: Store
    let applicant: Applicant

    var days: Int { applicant.daysSinceActivity }
    var chip: Color {
        let w = store.settings.aging.warn
        let a = store.settings.aging.danger
        if days >= a { return .red }
        if days >= w { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(chip).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(applicant.fullName).font(.headline)
                Text("\(applicant.stage.rawValue) • \(days) day\(days == 1 ? "" : "s") since activity")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !applicant.notes.isEmpty {
                    Text(applicant.notes).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !applicant.phone.isEmpty {
                let digits = applicant.phone.filter(\.isNumber)
                if let tel = URL(string: "tel://\(digits)") {
                    Link(destination: tel) { Image(systemName: "phone.fill") }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Applicant Editor

struct ApplicantEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State var applicant: Applicant
    @State private var showAddChecklist = false
    @State private var newChecklistText = ""
    @State private var showAddFile = false
    @State private var newFileTitle = ""
    @State private var newFileNote = ""
    @State private var showScanner = false
    @State private var showDocPicker = false
    @State private var showQuickLookURL: URL?
    @State private var editFile: FileNote?
    @State private var pickPhotos: [PhotosPickerItem] = []
    @State private var confirmStage = false
    @State private var targetStage: Stage = .newLead
    @State private var ocrSuggestion: String? = nil
    @State private var showEligibilityDetails = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Full Name", text: $applicant.fullName)
                TextField("Age", text: IntBinding($applicant.age)).keyboardType(.numberPad)
                Picker("Sex", selection: $applicant.sex) {
                    ForEach(Sex.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }.pickerStyle(.segmented)
                Toggle("Prior Service", isOn: $applicant.priorService)
                TextField("Phone", text: $applicant.phone).keyboardType(.phonePad)
                // FIX: safe optional binding for address
                TextField("Address (optional)", text: NonOptionalBinding($applicant.address))
            } header: { Text("Identity") }

            Section {
                HStack {
                    Text("Current")
                    Spacer()
                    Menu(applicant.stage.rawValue) {
                        ForEach(Stage.allCases) { s in
                            Button(s.rawValue) { targetStage = s; confirmStage = true }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("In this stage for \(Date().daysSince(applicant.stageStart)) day(s).")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Stage") }

            Section {
                TextField("Physical Health Notes", text: $applicant.physicalHealth, axis: .vertical)
                TextField("Legal Issues (if any)", text: $applicant.legalIssues, axis: .vertical)
                TextField("Education Level", text: $applicant.educationLevel)
                TextField("Marital Status", text: $applicant.maritalStatus)
                Stepper("Dependents: \(applicant.dependents)", value: $applicant.dependents, in: 0...20)

                Toggle("Tattoos/Brandings/Piercings", isOn: $applicant.hasTattoos)
                if applicant.hasTattoos {
                    TextField("Tattoos/Brandings/Piercings Notes", text: $applicant.tattoosNotes, axis: .vertical)
                }

                HStack {
                    TextField("Height (in)", value: $applicant.heightInInches, format: .number).keyboardType(.decimalPad)
                    TextField("Weight (lb)", value: $applicant.weightInPounds, format: .number).keyboardType(.decimalPad)
                }
                if needsWaist {
                    TextField("Waist (in)", value: $applicant.waistInInches, format: .number).keyboardType(.decimalPad)
                }
                if let screen = bodyComp.screeningLimit {
                    Text("Screening: \(screen) lb").font(.caption).foregroundStyle(.secondary)
                }
                switch bodyComp.status {
                case .passNoTape:
                    Text("Pass (no tape)").font(.caption).foregroundStyle(.secondary)
                case .needsTape:
                    Text("Tape required").font(.caption).foregroundStyle(.secondary)
                case .passOnSite:
                    Text("Pass (one-site \(bodyComp.measuredBF ?? 0)% ≤ \(bodyComp.maxBF ?? 0)%)").font(.caption).foregroundStyle(.secondary)
                case .failOnSite:
                    Text("Fail (one-site \(bodyComp.measuredBF ?? 0)% > \(bodyComp.maxBF ?? 0)%)").font(.caption).foregroundStyle(.red)
                }
                if let s = bodyComp.screeningLimit, let max = bodyComp.maxBF, let measured = bodyComp.measuredBF {
                    Text("Why: Screen \(s) lb • Measured \(measured)% • Max \(max)%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } header: { Text("Health & Body") }

            Section {
                let outcome = store.evaluateEligibility(for: applicant)
                VStack(alignment: .leading, spacing: 8) {
                    Text(outcome.headline.rawValue)
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(outcome.chips, id: \.self) { chip in
                                Text(chip)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.subtleBG)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    if showEligibilityDetails {
                        ForEach(outcome.actions, id: \.self) { act in
                            Button("Add to Checklist: \(act)") {
                                applicant.checklist.append(ChecklistItem(canonicalName: act, isCollected: false))
                            }
                            .font(.caption)
                        }
                    }
                }
                .onTapGesture { showEligibilityDetails.toggle() }
            } header: { Text("Eligibility (preliminary)") }

            // *** FIXED: Use Section { } header: { } and Toggle(isOn:){ Text(...) }
            Section {
                ForEach($applicant.checklist) { $item in
                    Toggle(isOn: $item.isCollected) {
                        Text(item.canonicalName)
                    }
                    if !item.notes.isEmpty || item.isCollected {
                        TextField("Notes", text: $item.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in applicant.checklist.remove(atOffsets: idx) }

                Button {
                    showAddChecklist = true
                } label: {
                    Label("Add Checklist Item (synonyms ok)", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Checklist")
            } footer: {
                Text("Hints: SSN → Social Security Card, BC → Birth Certificate, DL → Driver’s License")
            }

            Section {
                if applicant.files.isEmpty {
                    Text("No files added yet").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(applicant.files) { f in
                        Button {
                            if let path = f.filePath, let url = FileStore.absoluteURL(from: path) {
                                showQuickLookURL = url
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if let path = f.filePath, let url = FileStore.absoluteURL(from: path) {
                                    FileThumbView(url: url)
                                } else {
                                    Image(systemName: "doc.text").frame(width: 44, height: 44)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.subheadline.bold()).lineLimit(1)
                                    if !f.note.isEmpty {
                                        Text(f.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    } else if let path = f.filePath {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if f.filePath != nil {
                                    Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel("Open \(f.title) in Quick Look")
                        .contextMenu {
                            Button("Rename") { editFile = f }
                            if let path = f.filePath, let url = FileStore.absoluteURL(from: path) {
                                ShareLink("Export", item: url)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if let p = f.filePath { FileStore.removeFile(at: p) }
                                if let idx = applicant.files.firstIndex(where: { $0.id == f.id }) {
                                    applicant.files.remove(at: idx)
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                Button {
                    showAddFile = true
                } label: { Label("Add File Note", systemImage: "doc.badge.plus") }

                Button {
                    showDocPicker = true
                } label: { Label("Pick from Files", systemImage: "folder.badge.plus") }

                PhotosPicker(selection: $pickPhotos, maxSelectionCount: 10, matching: .images) {
                    Label("Add from Photos", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: pickPhotos) { items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                                try? data.write(to: tmp)
                                do {
                                    let saved = try FileStore.importFile(for: applicant.id, from: tmp)
                                    if let rel = FileStore.relativePath(for: saved) {
                                        applicant.files.append(.init(
                                            title: saved.deletingPathExtension().lastPathComponent,
                                            note: "Imported from Photos",
                                            filePath: rel
                                        ))
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                } catch { print("Photo import error: \(error)") }
                            }
                        }
                        pickPhotos.removeAll()
                    }
                }

                Button {
                    showScanner = true
                } label: { Label("Scan Document", systemImage: "doc.viewfinder") }

            } header: {
                Text("Files")
            }
            .sheet(isPresented: $showDocPicker) {
                DocumentPickerView { urls in
                    for url in urls {
                        do {
                            let saved = try FileStore.importFile(for: applicant.id, from: url)
                            if let rel = FileStore.relativePath(for: saved) {
                                applicant.files.append(.init(
                                    title: saved.deletingPathExtension().lastPathComponent,
                                    note: "",
                                    filePath: rel
                                ))
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } catch { print("Import error: \(error)") }
                    }
                }
            }
            .sheet(item: $showQuickLookURL) { url in
                QuickLookPreview(url: url)
            }
            .sheet(item: $editFile) { file in
                if let binding = binding(for: file) {
                    NavigationStack {
                        Form {
                            TextField("Title", text: binding.title)
                            TextField("Note", text: binding.note, axis: .vertical)
                            if let path = binding.wrappedValue.filePath,
                               let url = FileStore.absoluteURL(from: path) {
                                ShareLink("Export File", item: url)
                            }
                        }
                        .navigationTitle("Edit File")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { editFile = nil } } }
                    }
                }
            }

            Section {
                Button {
                    save()
                    dismiss()
                } label: {
                    Label("Save Applicant", systemImage: "square.and.arrow.down.fill")
                }.buttonStyle(.borderedProminent)
            }
            Section {
                Button("Delete Applicant", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(applicant.fullName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Move to Enlisted") { targetStage = .enlisted; confirmStage = true }
                    Button("Move to MEPS") { targetStage = .meps; confirmStage = true }
                    Button("Move to Documents") { targetStage = .docs; confirmStage = true }
                    Button("Move to Screening") { targetStage = .screening; confirmStage = true }
                    Button("Move to New Lead") { targetStage = .newLead; confirmStage = true }
                } label: { Label("Quick Move", systemImage: "arrowshape.turn.up.right.circle") }
            }
        }
        .alert("Change Stage to \(targetStage.rawValue)?", isPresented: $confirmStage) {
            Button("Change", role: .destructive) {
                applicant.stage = targetStage
                applicant.stageStart = Date()
                applicant.updatedAt = Date()
                applicant.lastActivityAt = Date()
                if targetStage == .enlisted {
                    applicant.enlistedDate = Date()
                    applicant.serviceAfterSale = true
                } else {
                    applicant.serviceAfterSale = false
                    applicant.enlistedDate = nil
                }
                save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This resets the Days-in-Stage timer.")
        }
        .alert("Delete Applicant?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                NotificationService().cancelSASReminder(id: applicant.id)
                FileStore.removeAll(for: applicant.id)
                store.applicants.removeAll { $0.id == applicant.id }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showAddChecklist) {
            NavigationStack {
                VStack(alignment: .leading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(ChecklistLexicon.canonical, id: \.self) { key in
                                Button(key) {
                                    applicant.checklist.append(.init(canonicalName: key, isCollected: false))
                                    showAddChecklist = false
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal)
                    }
                    TextField("Type item or synonym (SSN, BC, DL…)", text: $newChecklistText)
                        .textFieldStyle(.roundedBorder)
                        .padding()
                    Spacer()
                }
                .navigationTitle("Add Checklist Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddChecklist = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let canon = ChecklistLexicon.canonicalize(newChecklistText)
                            applicant.checklist.append(.init(canonicalName: canon, isCollected: false))
                            newChecklistText = ""
                            showAddChecklist = false
                        }.disabled(newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddFile) {
            NavigationStack {
                Form {
                    TextField("Title", text: $newFileTitle)
                        .onChange(of: newFileTitle) { text in
                            ocrSuggestion = ChecklistLexicon.inferDocKey(text)
                        }
                    TextField("Note", text: $newFileNote, axis: .vertical)
                    if let suggestion = ocrSuggestion {
                        Section {
                            Text("Suggested: \(suggestion)")
                                .font(.caption)
                            Button("Add \(suggestion) to Checklist") {
                                applicant.checklist.append(.init(canonicalName: suggestion, isCollected: false))
                                ocrSuggestion = nil
                            }
                        }
                    }
                }
                .navigationTitle("Add File Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddFile = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            applicant.files.append(.init(title: newFileTitle, note: newFileNote))
                            newFileTitle = ""; newFileNote = ""
                            showAddFile = false
                        }.disabled(newFileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(completion: { image, text in
                let filename = "scan_\(UUID().uuidString).jpg"
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    try? data.write(to: tmp)
                    let suggestion = ChecklistLexicon.inferDocKey(text) ?? "Scanned Document"
                    do {
                        let saved = try FileStore.importFile(for: applicant.id, from: tmp)
                        if let rel = FileStore.relativePath(for: saved) {
                            applicant.files.append(.init(title: suggestion, note: "", filePath: rel))
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        if let key = ChecklistLexicon.inferDocKey(text), !applicant.checklist.contains(where: { $0.canonicalName == key }) {
                            applicant.checklist.append(.init(canonicalName: key, isCollected: true))
                        }
                    } catch { print("Scan import error: \(error)") }
                }
            })
        }
        .onDisappear { save() }
    }

    // Body composition
    var bodyComp: BodyCompResult {
        evaluateBodyComp(applicant: applicant, sex: applicant.sex, age: applicant.age ?? 0)
    }
    var needsWaist: Bool {
        switch bodyComp.status {
        case .passNoTape: return false
        default: return true
        }
    }

    func binding(for file: FileNote) -> Binding<FileNote>? {
        guard let idx = applicant.files.firstIndex(where: { $0.id == file.id }) else { return nil }
        return $applicant.files[idx]
    }

    func save() {
        applicant.updatedAt = Date()
        applicant.lastActivityAt = Date()
        if bodyComp.status != .passNoTape {
            if !applicant.checklist.contains(where: { $0.canonicalName == "One-Site Tape" }) {
                applicant.checklist.append(ChecklistItem(canonicalName: "One-Site Tape", isCollected: false, notes: "Auto-added by system"))
            }
        }
        if let i = store.applicants.firstIndex(where: { $0.id == applicant.id }) {
            store.applicants[i] = applicant
        } else {
            store.applicants.insert(applicant, at: 0)
        }
    }
}

// MARK: - Events

struct EventsView: View {
    @EnvironmentObject var store: Store
    @State private var filter: EventType? = nil

    var filtered: [RecruitEvent] {
        var list = store.events.sorted { $0.start < $1.start }
        if let f = filter { list = list.filter { $0.type == f } }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Type", selection: $filter) {
                    Text("All").tag(EventType?.none)
                    ForEach(EventType.allCases) { t in Text(t.rawValue).tag(EventType?.some(t)) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                List {
                    ForEach(filtered) { e in
                        NavigationLink { EventEditor(event: e) } label: { EventRow(event: e) }
                    }
                    .onDelete { idx in
                        let cal = CalendarService()
                        for i in idx {
                            let ev = filtered[i]
                            if let id = ev.ekIdentifier { cal.deleteEvent(identifier: id) }
                            NotificationService().cancelEventReminders(for: ev)
                            if let j = store.events.firstIndex(where: { $0.id == ev.id }) {
                                store.events.remove(at: j)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let new = RecruitEvent(title: "New Event", type: .other, start: Date(), end: Date().addingTimeInterval(3600))
                        store.events.insert(new, at: 0)
                    } label: { Label("New", systemImage: "plus.circle.fill") }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: RecruitEvent
    var body: some View {
        VStack(alignment: .leading) {
            Text(event.title)
            Text(event.start, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct EventEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var event: RecruitEvent
    @State private var showPicker = false
    @State private var showCalError = false
    @State private var calError = ""
    @State private var showMessage = false
    @State private var showMessageUnavailable = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $event.title)
                Picker("Type", selection: $event.type) {
                    ForEach(EventType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                DatePicker("Start", selection: $event.start)
                DatePicker("End", selection: $event.end)
                TextField("Location", text: NonOptionalBinding($event.location))
            } header: { Text("Details") }

            Section("Options") {
                Toggle("Include in Monday Report", isOn: $event.includeInMondayReport)
                Button("Add to Calendar") { addToCalendar() }
                Button("Notify 1SG") { notify1SG() }
                Button("Insert Template for Type") {
                    let body = TemplateService.messageBody(for: event)
                    event.notes = (event.notes ?? "").isEmpty ? body : (event.notes! + "\n\n" + body)
                }
                .font(.caption)
            }

            Section("Related Applicants") {
                ForEach(event.relatedApplicantIDs, id: \.self) { id in
                    if let a = store.applicants.first(where: { $0.id == id }) {
                        Text(a.fullName)
                    }
                }
                Button("Select Applicants") { showPicker = true }
            }

            Section {
                TextField("Notes", text: NonOptionalBinding($event.notes), axis: .vertical)
            }
            Section {
                Button("Save Event") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Edit Event")
        .sheet(isPresented: $showPicker) { ApplicantPicker(selected: $event.relatedApplicantIDs) }
        .sheet(isPresented: $showMessage, onDismiss: { dismiss() }) {
            MessageComposeView(body: "Event: \(event.title) on \(event.start.formatted(date: .abbreviated, time: .shortened))")
        }
        .alert("Calendar Error", isPresented: $showCalError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(calError)
        }
        .alert("Messaging Not Available", isPresented: $showMessageUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This device is not configured to send text messages.")
        }
    }

    func save() {
        if Calendar.current.compare(event.start, to: event.end, toGranularity: .minute) != .orderedAscending {
            event.end = event.start.addingTimeInterval(3600)
        }
        if let idx = store.events.firstIndex(where: { $0.id == event.id }) {
            store.events[idx] = event
        } else {
            store.events.append(event)
        }
        NotificationService().scheduleEventReminders(for: event)
    }

    func addToCalendar() {
        save()
        let cal = CalendarService()
        Task {
            do {
                try await cal.requestAccess()
                let ek = try cal.makeEvent(from: event, calendarID: store.settings.calendarID)
                try cal.store.save(ek, span: .thisEvent)
                await MainActor.run {
                    if let idx = store.events.firstIndex(where: { $0.id == event.id }) {
                        store.events[idx].ekIdentifier = ek.eventIdentifier
                    }
                }
            } catch {
                await MainActor.run {
                    calError = error.localizedDescription
                    showCalError = true
                }
            }
        }
    }

    func notify1SG() {
        save()
        if MFMessageComposeViewController.canSendText() {
            showMessage = true
        } else {
            showMessageUnavailable = true
        }
    }
}

struct MessageComposeView: UIViewControllerRepresentable {
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) { }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            dismiss()
        }
    }
}

struct ApplicantPicker: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: [UUID]

    var body: some View {
        NavigationStack {
            List(store.applicants) { a in
                Button {
                    if let i = selected.firstIndex(of: a.id) {
                        selected.remove(at: i)
                    } else {
                        selected.append(a.id)
                    }
                } label: {
                    HStack {
                        Text(a.fullName)
                        Spacer()
                        if selected.contains(a.id) { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("Applicants")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Service After Sale

struct SASView: View {
    @EnvironmentObject var store: Store
    private let notif = NotificationService()

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.applicants.filter { $0.serviceAfterSale }) { a in
                    NavigationLink {
                        SASDetailView(applicant: binding(for: a))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(a.fullName)
                            if let d = a.enlistedDate {
                                Text(d, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Service After Sale")
        }
        .onAppear { Task { await notif.requestAuthorization() } }
    }

    func binding(for applicant: Applicant) -> Binding<Applicant> {
        guard let idx = store.applicants.firstIndex(where: { $0.id == applicant.id }) else {
            fatalError("Applicant not found")
        }
        return $store.applicants[idx]
    }
}

struct SASDetailView: View {
    @EnvironmentObject var store: Store
    @Binding var applicant: Applicant
    private let notif = NotificationService()
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Reminder") {
                Picker("Notify frequency", selection: $applicant.sasFrequency) {
                    ForEach(SASReminderFrequency.allCases) { f in Text(f.rawValue).tag(f) }
                }
                Button("Test Reminder") { notif.testSASReminder() }
                    .font(.caption)
            }
            Section("Drill Dates") {
                DatePicker("Drill 1", selection: DateBinding($applicant.drillDate1), displayedComponents: .date)
                DatePicker("Drill 2", selection: DateBinding($applicant.drillDate2), displayedComponents: .date)
            }
            Section("ACFT Scores") {
                ForEach($applicant.acft) { $e in
                    HStack {
                        TextField("Event", text: $e.event)
                        TextField("Raw", text: IntBinding($e.raw)).keyboardType(.numberPad)
                        TextField("Pts", text: IntBinding($e.points)).keyboardType(.numberPad)
                    }
                }
                .onDelete { applicant.acft.remove(atOffsets: $0) }
                Button { applicant.acft.append(.init(event: "", raw: nil, points: nil)) } label: {
                    Label("Add Event", systemImage: "plus.circle")
                }
            }
            Section {
                Button("Delete Applicant", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(applicant.fullName)
        .onChange(of: applicant.sasFrequency) { value in
            if value != .none {
                notif.scheduleSASReminder(for: applicant.id, name: applicant.fullName, frequency: value, hour: store.settings.sasReminderHour, minute: store.settings.sasReminderMinute)
            } else {
                notif.cancelSASReminder(id: applicant.id)
            }
        }
        .onChange(of: applicant.drillDate2) { newValue in
            let svc = NotificationService()
            svc.cancelSubmitSASPDF(applicantName: applicant.fullName)
            guard let when = newValue else { return }
            let fire = (when < Date()) ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() : when
            svc.scheduleSubmitSASPDF(on: fire, applicantName: applicant.fullName)
        }
        .alert("Delete Applicant?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                NotificationService().cancelSASReminder(id: applicant.id)
                FileStore.removeAll(for: applicant.id)
                store.applicants.removeAll { $0.id == applicant.id }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Reports

struct ReportsView: View {
    @EnvironmentObject var store: Store
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var grouped: [(Stage,[Applicant])] {
        let g = Dictionary(grouping: store.applicants, by: { $0.stage })
        return Stage.allCases.map { ($0, (g[$0] ?? []).sorted { $0.fullName < $1.fullName }) }
    }

    func weekRange(anchor: Date = .now) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        do {
                            let url = try makePDF()
                            shareURL = url; showShare = true
                        } catch {
                            importMessage = "PDF export failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: { Label("Export Applicants PDF", systemImage: "printer") }

                    Button {
                        do {
                            let url = try store.exportJSON()
                            shareURL = url; showShare = true
                        } catch {
                            importMessage = "JSON export failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: { Label("Export Data JSON", systemImage: "square.and.arrow.up.on.square") }

                    Button {
                        do {
                            let url = try makeCSV()
                            shareURL = url; showShare = true
                        } catch {
                            importMessage = "CSV export failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: { Label("Export Applicants CSV", systemImage: "tablecells") }

                    Button {
                        do {
                            let url = try makeCustomReport()
                            shareURL = url; showShare = true
                        } catch {
                            importMessage = "Custom report failed: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    } label: { Label("Export Custom Report", systemImage: "doc.badge.gearshape") }

                    Button { showImporter = true } label: {
                        Label("Import Data JSON (merge)", systemImage: "square.and.arrow.down.on.square")
                    }
                } footer: {
                    Text("PDF grouped by stage; JSON import merges Applicants/Events and updates Settings by UUID.")
                }

                Section("Snapshot") {
                    ForEach(grouped, id: \.0) { (stage, items) in
                        HStack {
                            Text(stage.rawValue); Spacer()
                            Text("\(items.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Reports & Export")
            .sheet(isPresented: $showShare) {
                if let url = shareURL { ShareSheet(activityItems: [url]) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { res in
                switch res {
                case .success(let url):
                    do {
                        let r = try store.importJSON(from: url)
                        importMessage = "Imported: \(r.appsAdded) applicants added, \(r.appsUpdated) updated; \(r.eventsAdded) events added, \(r.eventsUpdated) updated."
                        showImportAlert = true
                    } catch {
                        importMessage = "Import failed: \(error.localizedDescription)"
                        showImportAlert = true
                    }
                case .failure(let err):
                    importMessage = "Import canceled: \(err.localizedDescription)"
                    showImportAlert = true
                }
            }
            .alert("Import Result", isPresented: $showImportAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text(importMessage ?? "") }
        }
    }

    // PDF
    func makePDF() throws -> URL {
        let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 36
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ROPSConst.pdfDefault)

        let logo = store.loadLogo()
        var cursorY: CGFloat = margin
        let (weekStart, weekEnd) = weekRange()
        let events = store.events.filter { $0.includeInMondayReport && $0.start >= weekStart && $0.start < weekEnd }

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            if let logo = logo {
                logo.draw(in: CGRect(x: margin, y: margin, width: 64, height: 64))
            }
            draw("ROPS — Applicants Report", at: CGPoint(x: margin + (logo == nil ? 0 : 72), y: margin), font: .boldSystemFont(ofSize: 20))
            draw("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))",
                 at: CGPoint(x: margin + (logo == nil ? 0 : 72), y: margin + 26),
                 font: .systemFont(ofSize: 12), color: .darkGray)
            cursorY = margin + 80

            for (stage, list) in grouped {
                if cursorY > pageH - 100 { ctx.beginPage(); cursorY = margin }
                draw(stage.rawValue, at: CGPoint(x: margin, y: cursorY), font: .boldSystemFont(ofSize: 16))
                cursorY += 22
                if list.isEmpty {
                    draw("— None —", at: CGPoint(x: margin + 12, y: cursorY), font: .italicSystemFont(ofSize: 12), color: .gray)
                    cursorY += 20
                    continue
                }
                for a in list {
                    if cursorY > pageH - 100 { ctx.beginPage(); cursorY = margin }
                    let days = Date().daysSince(a.stageStart)
                    let outcome = store.evaluateEligibility(for: a).headline.rawValue
                    draw("• \(a.fullName) — Days in stage: \(days) — \(outcome)", at: CGPoint(x: margin + 8, y: cursorY), font: .systemFont(ofSize: 13))
                    cursorY += 16
                    if !a.notes.isEmpty {
                        cursorY += drawWrapped("   Notes: \(a.notes)", x: margin + 8, y: cursorY, width: pageW - margin*2 - 8, font: .systemFont(ofSize: 12)) + 4
                    }
                    let fileCount = a.files.filter { $0.filePath != nil }.count
                    if fileCount > 0 {
                        cursorY += drawWrapped("   📎 \(fileCount) file\(fileCount == 1 ? "" : "s")", x: margin + 8, y: cursorY, width: pageW - margin*2 - 8, font: .systemFont(ofSize: 11)) + 2
                    }
                }
                cursorY += 10
            }

            if cursorY > pageH - 100 { ctx.beginPage(); cursorY = margin }
            draw("This Week's Events", at: CGPoint(x: margin, y: cursorY), font: .boldSystemFont(ofSize: 16))
            cursorY += 22
            if events.isEmpty {
                draw("— None —", at: CGPoint(x: margin + 12, y: cursorY), font: .italicSystemFont(ofSize: 12), color: .gray)
                cursorY += 20
            } else {
                for e in events {
                    if cursorY > pageH - 100 { ctx.beginPage(); cursorY = margin }
                    let date = e.start.formatted(date: .abbreviated, time: .omitted)
                    let loc = e.location.map { " @ \($0)" } ?? ""
                    draw("• \(date) \(e.title) — \(e.type.rawValue)\(loc)", at: CGPoint(x: margin + 8, y: cursorY), font: .systemFont(ofSize: 13))
                    cursorY += 16
                    let names = e.relatedApplicantIDs.compactMap { id in store.applicants.first(where: { $0.id == id })?.fullName }.joined(separator: ", ")
                    if !names.isEmpty {
                        cursorY += drawWrapped("   Related: \(names)", x: margin + 8, y: cursorY, width: pageW - margin*2 - 8, font: .systemFont(ofSize: 12)) + 4
                    }
                }
                cursorY += 10
            }
        }

        try data.write(to: url, options: [.atomic])
        return url
    }

    func makeCSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Applicants.csv")
        var rows = ["Name,Stage"]
        for a in store.applicants {
            rows.append("\(a.fullName),\(a.stage.rawValue)")
        }
        try rows.joined(separator: "\n").data(using: .utf8)?.write(to: url)
        return url
    }

    func makeCustomReport() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomReport.txt")
        var lines: [String] = []
        let grouped = Dictionary(grouping: store.applicants, by: { $0.stage })
        for (stage, items) in grouped {
            lines.append("\(stage.rawValue): \(items.count)")
        }
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
        return url
    }

    func draw(_ text: String, at: CGPoint, font: UIFont, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        text.draw(at: at, withAttributes: attrs)
    }
    @discardableResult
    func drawWrapped(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: UIFont) -> CGFloat {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
        let rect = CGRect(x: x, y: y, width: width, height: .greatestFiniteMagnitude)
        let bound = (text as NSString).boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: ceil(bound.height)), withAttributes: attrs)
        return ceil(bound.height)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiVC: UIActivityViewController, context: Context) {}
}

struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct FileThumbView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                let ext = url.pathExtension.lowercased()
                let sys = ["pdf":"doc.richtext","jpg":"photo","jpeg":"photo","png":"photo"][ext] ?? "doc"
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.subtleBG)
                    Image(systemName: sys + ".fill").imageScale(.large).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task { await makeThumb() }
    }

    @MainActor
    private func makeThumb() async {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 100, height: 100),
                                               scale: UIScreen.main.scale, representationTypes: .all)
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
            self.image = rep.uiImage
        } catch {
            self.image = nil
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    var completion: (UIImage, String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                let image = scan.imageOfPage(at: 0)
                var text = ""
                if let cg = image.cgImage {
                    let request = VNRecognizeTextRequest()
                    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                    try? handler.perform([request])
                    text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
                }
                parent.completion(image, text)
            }
            controller.dismiss(animated: true)
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            parent.dismiss()
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            parent.dismiss()
        }
    }
}

// MARK: - Work Station

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var body: String
}

struct PackItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var checked: Bool = false
}

final class WorkStationStore: ObservableObject, Codable {
    @Published var snippets: [Snippet]
    @Published var pack: [PackItem]

    private enum CodingKeys: String, CodingKey { case snippets, pack }
    private let key = "WorkStationStore_v2"

    init() {
        snippets = TemplateService.defaultSnippets()
        pack = [
            .init(name: "Laptop/Charger"), .init(name: "Business Cards"),
            .init(name: "Table Cloth/Banner"), .init(name: "Swag/Handouts")
        ]
        load()
    }

    // MARK: - Codable

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snippets = try c.decode([Snippet].self, forKey: .snippets)
        pack = try c.decode([PackItem].self, forKey: .pack)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snippets, forKey: .snippets)
        try c.encode(pack, forKey: .pack)
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let me = try? JSONDecoder().decode(WorkStationStore.self, from: data) {
            snippets = me.snippets
            pack = me.pack
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct WorkStationView: View {
    @StateObject private var ws = WorkStationStore()

    var body: some View {
        NavigationStack {
            List {
                snippetsSection
                packSection
            }
            .navigationTitle("Work Station")
        }
        .onChange(of: ws.snippets) { _ in ws.persist() }
        .onChange(of: ws.pack) { _ in ws.persist() }
    }

    var snippetsSection: some View {
        Section("Snippets Library") {
            ForEach($ws.snippets) { $s in
                NavigationLink(s.name) {
                    Form {
                        TextField("Title", text: $s.name)
                        TextEditor(text: $s.body)
                            .frame(minHeight: 200)
                        ShareLink("Share Snippet", item: s.body)
                    }
                    .navigationTitle("Edit Snippet")
                }
            }
            .onDelete { ws.snippets.remove(atOffsets: $0) }
            Button { ws.snippets.append(.init(name: "New Snippet", body: "")) } label: {
                Label("Add Snippet", systemImage: "text.badge.plus")
            }
        }
    }

    var packSection: some View {
        Section("Recruiter Pack List") {
            ForEach($ws.pack) { $p in
                Toggle(p.name, isOn: $p.checked)
            }
            .onDelete { ws.pack.remove(atOffsets: $0) }
            Button { ws.pack.append(.init(name: "New Item")) } label: {
                Label("Add Item", systemImage: "bag.badge.plus")
            }
            Button {
                for i in ws.pack.indices { ws.pack[i].checked = false }
            } label: { Label("Uncheck All", systemImage: "arrow.uturn.backward") }
            .font(.caption)
        }
    }
}

// MARK: - Settings (iOS 16-safe onChange)

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var pickLogo: PhotosPickerItem?
    @State private var showGame = false
    @State private var calendars: [EKCalendar] = []
    @State private var newCalName: String = ""
    private let calService = CalendarService()
    @State private var reminderTime: Date = Date()
    private let notifService = NotificationService()

    var body: some View {
        NavigationStack {
            Form {
                DisclosureGroup("Recruiter Profile") {
                    TextField("Recruiter Name", text: $store.settings.recruiterName)
                    TextField("Initials", text: $store.settings.recruiterInitials)
                    TextField("RSID", text: $store.settings.rsid)
                }

                DisclosureGroup("Theme") {
                    Picker("Accent", selection: $store.settings.themeID) {
                        ForEach(ROPSTheme.all) { t in
                            HStack { Circle().fill(t.tint).frame(width: 14, height: 14); Text(t.name) }.tag(t.id)
                        }
                    }
                }

                DisclosureGroup("Stage Aging Thresholds") {
                    Stepper("Warn after \(store.settings.aging.warn) day(s)", value: $store.settings.aging.warn, in: 1...60)
                    Stepper("Alert after \(store.settings.aging.danger) day(s)", value: $store.settings.aging.danger, in: 2...120)
                    Text("Green/Yellow/Red dots use these thresholds.").font(.caption).foregroundStyle(.secondary)
                }

                DisclosureGroup("Eligibility Rules") {
                    Button("Write Starter Rules to Disk") {
                        store.writeStarterRulesToDisk()
                    }
                    .font(.caption)
                }

                DisclosureGroup("Calendar") {
                    if calendars.isEmpty {
                        Text("No calendars available").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Default Calendar", selection: $store.settings.calendarID) {
                            Text("System Default").tag(String?.none)
                            ForEach(calendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(Optional(cal.calendarIdentifier))
                            }
                        }
                    }
                    HStack {
                        TextField("New Calendar Name", text: $newCalName)
                        Button("Create") { createCalendar() }
                    }
                    .font(.caption)
                    Button("Test Calendar Connection") {
                        calService.debugCalendar()
                        calService.testEvent(calendarID: store.settings.calendarID)
                    }
                    .font(.caption)
                }

                DisclosureGroup("SAS Reminder") {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    Button("Test SAS Reminder") { notifService.testSASReminder() }
                        .font(.caption)
                }

                DisclosureGroup("Export Logo") {
                    PhotosPicker(selection: $pickLogo, matching: .images) {
                        Label(store.settings.logoStored ? "Replace Logo" : "Pick Logo", systemImage: "photo.fill.on.rectangle.fill")
                    }
                    if store.settings.logoStored, let img = store.loadLogo() {
                        Image(uiImage: img).resizable().scaledToFit().frame(height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section {
                    Button { showGame = true } label: {
                        VStack {
                            Text("Built, updated, and maintained by Joel “Beaux” Viola")
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        .navigationTitle("Settings")
        .onChange(of: store.settings) { _ in store.saveSettings() }  // iOS16-safe
        .onChange(of: pickLogo) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        store.storeLogo(img)
                    }
                }
        }
        .onAppear {
            loadCalendars()
            var comps = DateComponents()
            comps.hour = store.settings.sasReminderHour
            comps.minute = store.settings.sasReminderMinute
            reminderTime = Calendar.current.date(from: comps) ?? Date()
            Task { await notifService.requestAuthorization() }
        }
        .onChange(of: reminderTime) { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            store.settings.sasReminderHour = comps.hour ?? 9
            store.settings.sasReminderMinute = comps.minute ?? 0
            for a in store.applicants where a.sasFrequency != .none {
                notifService.scheduleSASReminder(for: a.id, name: a.fullName, frequency: a.sasFrequency, hour: store.settings.sasReminderHour, minute: store.settings.sasReminderMinute)
            }
        }
        .sheet(isPresented: $showGame) { TroutRunGameView() }
    }
    }

    func loadCalendars() {
        Task {
            do {
                try await calService.requestAccess()
                calendars = calService.calendars()
            } catch {
                print("Calendar access error: \(error)")
            }
        }
    }

    func createCalendar() {
        guard !newCalName.isEmpty else { return }
        do {
            let cal = try calService.createCalendar(named: newCalName)
            calendars = calService.calendars()
            store.settings.calendarID = cal.calendarIdentifier
            newCalName = ""
        } catch {
            print("Create calendar error: \(error)")
        }
    }
}

// MARK: - Easter Egg Game (Trout Run)

struct TroutRunGameView: View {
    @Environment(\.dismiss) private var dismiss

    struct Point: Hashable { var x: Int; var y: Int }
    struct Sasquatch: Identifiable { let id = UUID(); var pos: Point }

    @State private var player = Point(x: 0, y: 0)
    @State private var sasquatches: [Sasquatch] = []
    @State private var pellets: Set<Point> = []
    @State private var powers: Set<Point> = []
    @State private var poweredTicks = 0
    @State private var message: String?

    let cols = 10, rows = 12
    let moveTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Text("Trout Run").font(.headline)
                    Spacer()
                    Button("Close") { dismiss() }
                }.padding(.horizontal)

                if let msg = message { Text(msg).foregroundStyle(.secondary) }

                GeometryReader { geo in
                    let cell = min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows))
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(pellets), id: \.self) { p in
                            Circle().fill(Color.white)
                                .frame(width: 4, height: 4)
                                .position(x: CGFloat(p.x) * cell + 0.5 * cell,
                                          y: CGFloat(p.y) * cell + 0.5 * cell)
                        }
                        ForEach(Array(powers), id: \.self) { p in
                            Circle().fill(Color.yellow)
                                .frame(width: 8, height: 8)
                                .position(x: CGFloat(p.x) * cell + 0.5 * cell,
                                          y: CGFloat(p.y) * cell + 0.5 * cell)
                        }
                        ForEach(sasquatches) { s in
                            Text("🦧")
                                .position(x: CGFloat(s.pos.x) * cell + 0.5 * cell,
                                          y: CGFloat(s.pos.y) * cell + 0.5 * cell)
                        }
                        Text("🐟")
                            .position(x: CGFloat(player.x) * cell + 0.5 * cell,
                                      y: CGFloat(player.y) * cell + 0.5 * cell)
                    }
                    .frame(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
                    .background(Color.subtleBG)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear { reset() }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in move(to: value.location, cellSize: cell) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 420)
            }
            Spacer()
        }
        .onReceive(moveTimer) { _ in tick() }
    }

    func reset() {
        player = Point(x: cols/2, y: rows/2)
        pellets = []
        for x in 0..<cols { for y in 0..<rows { pellets.insert(Point(x: x, y: y)) } }
        powers = [Point(x: 1, y: 1), Point(x: cols-2, y: rows-2)]
        pellets.subtract(powers)
        sasquatches = [Sasquatch(pos: Point(x: 0, y: 0)), Sasquatch(pos: Point(x: cols-1, y: rows-1))]
        message = nil
        poweredTicks = 0
    }

    func move(to location: CGPoint, cellSize: CGFloat) {
        guard message == nil else { return }
        let x = min(max(Int(location.x / cellSize), 0), cols - 1)
        let y = min(max(Int(location.y / cellSize), 0), rows - 1)
        if x == player.x && y == player.y { return }
        player = Point(x: x, y: y)
        if powers.remove(player) != nil { poweredTicks = 20 }
        pellets.remove(player)
        checkWin()
        checkCollisions()
    }

    func tick() {
        guard message == nil else { return }
        if poweredTicks > 0 { poweredTicks -= 1 }
        for i in sasquatches.indices {
            let dir = Int.random(in: 0..<4)
            switch dir {
            case 0: sasquatches[i].pos.x = (sasquatches[i].pos.x + 1) % cols
            case 1: sasquatches[i].pos.x = (sasquatches[i].pos.x - 1 + cols) % cols
            case 2: sasquatches[i].pos.y = (sasquatches[i].pos.y + 1) % rows
            default: sasquatches[i].pos.y = (sasquatches[i].pos.y - 1 + rows) % rows
            }
        }
        checkCollisions()
    }

    func checkCollisions() {
        for i in sasquatches.indices.reversed() {
            if sasquatches[i].pos == player {
                if poweredTicks > 0 {
                    sasquatches.remove(at: i)
                } else {
                    message = "Caught!"
                }
            }
        }
    }

    func checkWin() {
        if pellets.isEmpty { message = "You Win!" }
    }
}
