//
//  StripesForSkillsFiller.swift
//  ROPS
//
//  iOS 16+ / PDFKit
//  Fills the "BLANK STRIPES FOR SKILLS" PDF.
//  - Top Name:  "PVT <Applicant Name>"
//  - Top Unit:  "<Recruiter Name> / DET 3 RSP"
//  - Top Date:  Second drill date
//  - All "STRM Red Phase":   First drill date + recruiter initials
//  - All "STRM White Phase": Second drill date + recruiter initials
//  - Signature lines untouched
//
//  Usage (example):
//    let input = SFSInput(applicantFullName: applicant.fullName,
//                         recruiterName: store.settings.recruiterName,
//                         recruiterInitials: store.settings.recruiterInitials,
//                         drill1: applicant.drillDate1,
//                         drill2: applicant.drillDate2)
//    let url = try StripesForSkillsFiller.fill(templateURL: bundledPDFURL, input: input)
//
import Foundation
import PDFKit
import UIKit

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

    // MARK: - Public entry point

    /// Returns a new, filled PDF file URL in the temporary directory.
    public static func fill(templateURL: URL, input: SFSInput) throws -> URL {
        guard let doc = PDFDocument(url: templateURL), doc.pageCount > 0 else {
            throw NSError(domain: "StripesForSkills", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Template PDF not found or empty"])
        }

        // Preferred: fill actual AcroForm fields (fast / crisp)
        let touched = fillAcroFormIfPossible(in: doc, input: input)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SFS_\(UUID().uuidString).pdf")

        if touched {
            doc.write(to: outURL)
            return outURL
        }

        // Fallback: render original pages and overlay text in the right places
        return try renderWithOverlays(from: doc, input: input, outURL: outURL)
    }

    // MARK: - 1) AcroForm filling (preferred)

    /// Iterates text widgets and sets values by robust name matching.
    @discardableResult
    private static func fillAcroFormIfPossible(in doc: PDFDocument, input: SFSInput) -> Bool {
        var wrote = false
        let df = DateFormatter(); df.dateStyle = .short
        let d1 = input.drill1.map { df.string(from: $0) } ?? ""
        let d2 = input.drill2.map { df.string(from: $0) } ?? ""

        let topName  = "PVT \(input.applicantFullName)"
        let topUnit  = "\(input.recruiterName) / DET 3 RSP"
        let redText  = combine(date: d1, initials: input.recruiterInitials)
        let whiteText = combine(date: d2, initials: input.recruiterInitials)

        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            for ann in page.annotations where ann.widgetFieldType == .text {
                let name = safeFieldName(ann)
                guard !name.isEmpty else { continue }

                // Top banner
                if equals(name, "NAME  RANK") || containsAny(name, ["NAME & RANK", "NAMERANK"]) {
                    ann.widgetStringValue = topName; wrote = true; continue
                }
                if equals(name, "PLATOON SGTUNIT") || containsAny(name, ["PLATOON", "UNIT"]) {
                    ann.widgetStringValue = topUnit; wrote = true; continue
                }
                // Use *exact* "Date" match for the top right field (prevents touching bottom sig dates)
                if equals(name, "Date") {
                    ann.widgetStringValue = d2; wrote = true; continue
                }

                // Phase rows (accept several naming conventions)
                let lower = name.lowercased()
                if lower.contains("strm red phase") || lower.contains("red phase") {
                    ann.widgetStringValue = redText; wrote = true; continue
                }
                if lower.contains("strm white phase") || lower.contains("white phase") {
                    ann.widgetStringValue = whiteText; wrote = true; continue
                }
            }
        }
        return wrote
    }

    // MARK: - 2) Overlay fallback (text-anchored)

    /// Draws original pages and overlays the values anchored to page text tokens.
    private static func renderWithOverlays(from doc: PDFDocument, input: SFSInput, outURL: URL) throws -> URL {
        let df = DateFormatter(); df.dateStyle = .short
        let d1 = input.drill1.map { df.string(from: $0) } ?? ""
        let d2 = input.drill2.map { df.string(from: $0) } ?? ""
        let topName  = "PVT \(input.applicantFullName)"
        let topUnit  = "\(input.recruiterName) / DET 3 RSP"
        let redText  = combine(date: d1, initials: input.recruiterInitials)
        let whiteText = combine(date: d2, initials: input.recruiterInitials)

        let pageBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: outURL) { ctx in
            for i in 0..<doc.pageCount {
                ctx.beginPage()
                guard let page = doc.page(at: i) else { continue }
                let cg = ctx.cgContext

                // Draw original PDF page
                page.draw(with: .mediaBox, to: cg)

                // Fonts
                let big = UIFont.systemFont(ofSize: 12)
                let small = UIFont.systemFont(ofSize: 10)

                // --- Top banner (anchor-based) ---
                // NAME/RANK (left top)
                overlayRight(ofAnyToken: ["NAME & RANK", "NAME", "NAME  RANK"],
                             on: page,
                             yNudge: 0,
                             draw: topName,
                             font: big,
                             cg: cg)

                // PLATOON SGT / UNIT (left top)
                overlayRight(ofAnyToken: ["PLATOON SGT/UNIT", "PLATOON", "UNIT"],
                             on: page,
                             yNudge: 0,
                             draw: topUnit,
                             font: big,
                             cg: cg)

                // Date (top right) — choose a token at top 25% of the page to avoid line dates below
                if let sel = firstToken("Date", on: page, topFraction: 0.25) {
                    let r = sel.bounds(for: page)
                    drawText(d2, at: CGPoint(x: r.maxX + 8, y: r.minY), font: big, cg: cg)
                }

                // --- Phase rows (anchor each line & draw near the right margin) ---
                fillPhaseLines(on: page,
                               contains: "STRM Red Phase",
                               value: redText,
                               font: small,
                               cg: cg)

                fillPhaseLines(on: page,
                               contains: "STRM White Phase",
                               value: whiteText,
                               font: small,
                               cg: cg)
            }
        }

        return outURL
    }

    // MARK: - Overlay helpers

    /// Find first match for a token near the top area (guards against other dates/signature regions).
    private static func firstToken(_ token: String, on page: PDFPage, topFraction: CGFloat) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        let hits = doc.findString(token, withOptions: .caseInsensitive)
        let pageH = page.bounds(for: .mediaBox).height
        return hits.first(where: { $0.pages.contains(page) && $0.bounds(for: page).minY <= pageH * topFraction })
    }

    private static func overlayRight(ofAnyToken tokens: [String], on page: PDFPage, yNudge: CGFloat, draw value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        for t in tokens {
            guard let sel = selection(in: page, token: t) else { continue }
            let r = sel.bounds(for: page)
            drawText(value, at: CGPoint(x: r.maxX + 8, y: r.minY + yNudge), font: font, cg: cg)
            return
        }
    }

    private static func fillPhaseLines(on page: PDFPage, contains marker: String, value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        let anchors = selections(in: page, token: marker)
        let pageBounds = page.bounds(for: .mediaBox)
        // Write toward the right column; tweak these X offsets if your template changes.
        let initialsX = pageBounds.maxX - 160.0
        let dateX     = pageBounds.maxX - 100.0

        for s in anchors {
            let r = s.bounds(for: page)
            let y = r.midY - 4
            // Fill as "Initials / Date of Completion" pair (initials left, date right)
            // If you store initials separate, you could split here. We keep combined 'value'.
            // Expect `value` like "05/10/25 / JS" or "05/10/25 JS", both OK.
            // For stricter separation, parse and draw pieces at the two columns.
            drawText(value, at: CGPoint(x: initialsX, y: y), font: font, cg: cg)
            _ = dateX // placeholder for separate date column if needed later
        }
    }

    private static func drawText(_ text: String, at p: CGPoint, font: UIFont, cg: CGContext) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        (text as NSString).draw(at: p, withAttributes: attrs)
    }

    private static func selection(in page: PDFPage, token: String) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        let results = doc.findString(token, withOptions: .caseInsensitive)
        return results.first { $0.pages.contains(page) }
    }

    private static func selections(in page: PDFPage, token: String) -> [PDFSelection] {
        guard let doc = page.document else { return [] }
        let results = doc.findString(token, withOptions: .caseInsensitive)
        return results.filter { $0.pages.contains(page) }
    }

    // MARK: - Field name helpers (AcroForm)

    private static func safeFieldName(_ ann: PDFAnnotation) -> String {
        if let n = ann.fieldName, !n.isEmpty { return n }
        if let n = ann.value(forAnnotationKey: PDFAnnotationKey(rawValue: "T")) as? String, !n.isEmpty { return n }
        return ""
    }

    private static func equals(_ a: String, _ b: String) -> Bool {
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    private static func containsAny(_ s: String, _ options: [String]) -> Bool {
        options.contains { s.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func combine(date: String, initials: String) -> String {
        guard !date.isEmpty, !initials.isEmpty else { return date.isEmpty ? initials : date }
        return "\(date) / \(initials)"
    }
}
