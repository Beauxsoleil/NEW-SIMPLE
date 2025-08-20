//
//  StripesForSkillsFiller.swift
//  ROPS
//
//  Stamps recruiter initials and dates next to "Stripes for Skills" labels by
//  searching visible text in the PDF and dropping FreeText annotations to the
//  right of each label. This avoids relying on AcroForm field names that vary
//  across templates.
//
//  Usage:
//    let input = SFSInput(applicantFullName: applicant.fullName,
//                         recruiterName: store.settings.recruiterName,
//                         recruiterInitials: store.settings.recruiterInitials,
//                         drill1: applicant.drillDate1,
//                         drill2: applicant.drillDate2)
//    let url = try StripesForSkillsFiller.fill(templateURL: bundledPDFURL, input: input)
//

import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
typealias XFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias XFont = NSFont
#endif

public struct SFSInput {
    public let applicantFullName: String
    public let recruiterName: String
    public let recruiterInitials: String
    public let drill1: Date?   // First drill
    public let drill2: Date?   // Second drill

    public init(applicantFullName: String,
                recruiterName: String,
                recruiterInitials: String,
                drill1: Date?,
                drill2: Date?) {
        self.applicantFullName = applicantFullName
        self.recruiterName = recruiterName
        self.recruiterInitials = recruiterInitials
        self.drill1 = drill1
        self.drill2 = drill2
    }
}

public enum StripesForSkillsFiller {

    private static let annotationFontSize: CGFloat = 11
    private static let maxStampWidth: CGFloat = 220
    private static let xPadding: CGFloat = 6
    private static let yNudge: CGFloat = -2

    /// Returns a new, filled PDF file URL in the temporary directory.
    public static func fill(templateURL: URL, input: SFSInput) throws -> URL {
        guard let doc = PDFDocument(url: templateURL), doc.pageCount > 0 else {
            throw NSError(domain: "StripesForSkills", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Template PDF not found or empty"])
        }

        let stamps = makeStampMap(from: input)
        stamp(doc: doc, labelsToValues: stamps)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SFS_\(UUID().uuidString).pdf")
        guard doc.write(to: outURL) else {
            throw NSError(domain: "StripesForSkills", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to write output PDF"])
        }
        return outURL
    }

    // MARK: - Core stamping engine

    private static func stamp(doc: PDFDocument, labelsToValues: [String: String]) {
        let baseFont: XFont = XFont.systemFont(ofSize: annotationFontSize)

        for (label, value) in labelsToValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let (page, labelBounds) = findFirstOccurrence(of: label, in: doc) else {
                print("⚠️ Label not found in PDF: \"\(label)\"")
                continue
            }

            let target = CGRect(
                x: labelBounds.maxX + xPadding,
                y: labelBounds.minY + yNudge,
                width: maxStampWidth,
                height: max(14, labelBounds.height)
            )

            let annotation = PDFAnnotation(bounds: target, forType: .freeText, withProperties: nil)
            annotation.contents = trimmed
            annotation.font = baseFont
            annotation.color = .clear
            annotation.fontColor = .black
            annotation.border = PDFBorder() // zero width
            page.addAnnotation(annotation)
        }
    }

    /// Search the document and return the first occurrence for a visible label.
    private static func findFirstOccurrence(of label: String,
                                            in doc: PDFDocument) -> (PDFPage, CGRect)? {
        // `findString` now returns a non-optional array on modern SDKs, so we
        // capture the result directly and verify it's not empty.
        let selections = doc.findString(label, withOptions: .caseInsensitive)
        guard !selections.isEmpty else { return nil }

        let best = selections.min { selA, selB in
            let la = selA.string?.count ?? Int.max
            let lb = selB.string?.count ?? Int.max
            let da = abs(la - label.count)
            let db = abs(lb - label.count)
            return da < db
        } ?? selections[0]

        guard let page = best.pages.first as? PDFPage else { return nil }
        let bounds = best.bounds(for: page)
        return (page, bounds)
    }

    // MARK: - Stamp map

    private static func makeStampMap(from input: SFSInput) -> [String: String] {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let d1 = input.drill1.map { df.string(from: $0) } ?? ""
        let d2 = input.drill2.map { df.string(from: $0) } ?? ""

        let topName = "PVT \(input.applicantFullName)"
        let topUnit = "\(input.recruiterName) / DET 3 RSP"
        let redText = combine(initials: input.recruiterInitials, date: d1)
        let whiteText = combine(initials: input.recruiterInitials, date: d2)

        var stamps: [String: String] = [
            // Header
            "Date:": d2,
            "NAME  RANK:": topName,
            "PLATOON SGT/UNIT:": topUnit,

            // ACFT (optional)
            "Standing Power Throw": "PTS",
            "Hand Release Push-Up": "PTS",
            "Sprint, Drag, Carry": "PTS",
            "Plank": "PTS",
            "2.0-Mile Run": "PTS",

            // Signature blocks (optional)
            "Trainer's Signature": "________________________",
            "Commander's Verification": "____________________"
        ]

        let redLabels = [
            // Required task group
            "Esatblish Bank Account:",
            "Start Direct Deposit:",
            "Set up AKO Account:",
            "Set up MyPay Account:",
            "Military Time (STRM White Phase Stripes for Skills)",

            // Drill & Ceremony – Red Phase
            "Execute the Position of Attention:",
            "Execute the Hand Salute:",
            "Know Who and When to Salute:",
            "Parade Rest:",
            "Stand at Ease:",
            "At Ease:",
            "Rest:",
            "Right Face:",
            "Left Face:",
            "About Face:",

            // Rank Structure – Red Phase
            "Enlisted Ranks:",
            "Officer Ranks:",
            "Warrant Officer Ranks:",

            // Phonetic Alphabet – Red Phase
            "Know / Recite Phonetic Alphabet:"
        ]

        let whiteLabels = [
            // Marching / White Phase
            "Forward March:",
            "Half Step:",
            "Change Step:",
            "Column Left (STRM White Phase):",
            "Column Right (STRM White Phase):",
            "Halt:",

            // General Orders – White Phase SFS
            "First General Order:",
            "Second General Order:",
            "Third General Order:",

            // First Aid/CLS – White Phase
            "Evaluate a Casualty:",
            "Perform First Aid and Prctice Individual Preventative Medicine Countermeasures:",
            "Perform First Aid for Bleeding Extremity:",
            "Perform First Aid for Splinting a Fracture:",

            // Land Nav / BLQS (APPLE-MD)
            "Identify Terrain Features on a Map:",
            "Determine Grid Coordinates on a Map:",
            "Basic Lead Qualification Skills (APPLE-MD)"
        ]

        for label in redLabels { stamps[label] = redText }
        for label in whiteLabels { stamps[label] = whiteText }

        return stamps
    }

    private static func combine(initials: String, date: String) -> String {
        switch (initials.isEmpty, date.isEmpty) {
        case (true, true): return ""
        case (true, false): return date
        case (false, true): return initials
        case (false, false): return "\(initials) / \(date)"
        }
    }
}

