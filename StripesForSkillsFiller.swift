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
//  - All "ACFT" rows:       Second drill date + recruiter initials
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
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
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
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
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

                // --- Top “Required Task” block (4 rows) → Red ---
                fillRequiredTasksTopBlock(on: page, redValue: redText, font: small, cg: cg)

                // --- Fill entire Red sections down to next marker ---
                for anchor in selections(in: page, token: "STRM Red Phase") {
                    // anchor line itself is usually already stamped by AcroForm path; we fill below it
                    fillPhaseSection(from: anchor, value: redText, on: page, font: small, cg: cg)
                }

                // --- Fill entire White sections down to next marker ---
                for anchor in selections(in: page, token: "STRM White Phase") {
                    fillPhaseSection(from: anchor, value: whiteText, on: page, font: small, cg: cg)
                }

                // --- ACFT rows always use White ---
                fillACFTRows(on: page, value: whiteText, font: small, cg: cg)
            }
        }

        return outURL
    }

    // MARK: - Overlay helpers (fixed + expanded)

    /// Draw text at a point.
    private static func drawText(_ text: String, at p: CGPoint, font: UIFont, cg: CGContext) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        (text as NSString).draw(at: p, withAttributes: attrs)
    }

    /// First matching token on page (optionally constrained to top fraction of page height).
    private static func firstToken(_ token: String, on page: PDFPage, topFraction: CGFloat? = nil) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        let hits = doc.findString(token, withOptions: .caseInsensitive)
        if let top = topFraction {
            let h = page.bounds(for: .mediaBox).height
            return hits.first(where: { $0.pages.contains(page) && $0.bounds(for: page).minY <= h * top })
        }
        return hits.first(where: { $0.pages.contains(page) })
    }

    private static func selection(in page: PDFPage, token: String) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        return doc.findString(token, withOptions: .caseInsensitive).first { $0.pages.contains(page) }
    }

    private static func selections(in page: PDFPage, token: String) -> [PDFSelection] {
        guard let doc = page.document else { return [] }
        return doc.findString(token, withOptions: .caseInsensitive).filter { $0.pages.contains(page) }
    }

    /// Find the Y (page coords) of the nearest marker **below** a given Y.
    /// We treat any following Phase header or “ACFT” label as a stop.
    private static func nextMarkerY(below y: CGFloat, on page: PDFPage) -> CGFloat? {
        let candidates = (selections(in: page, token: "STRM Red Phase")
                          + selections(in: page, token: "STRM White Phase")
                          + selections(in: page, token: "ACFT"))
            .map { $0.bounds(for: page).minY }
            .filter { $0 < y }
            .sorted(by: >)
        return candidates.first
    }

    /// Fill a vertical section starting at a phase header, stepping one row at a time
    /// until the next marker or page bottom. Each line gets the same `value`.
    private static func fillPhaseSection(from anchor: PDFSelection,
                                         value: String,
                                         on page: PDFPage,
                                         font: UIFont,
                                         cg: CGContext)
    {
        guard !value.isEmpty else { return }

        let pageBounds = page.bounds(for: .mediaBox)
        let r = anchor.bounds(for: page)

        // Tune these if your template spacing shifts slightly.
        let lineHeight: CGFloat = 16.0     // vertical distance between consecutive rows
        let startY      = r.midY - 4       // baseline around the header line
        let stopY       = nextMarkerY(below: startY, on: page) ?? (pageBounds.minY + 72)

        // Right-side columns (approx). Adjust if your template columns move.
        let rightInitX: CGFloat = pageBounds.maxX - 160.0
        // let rightDateX: CGFloat = pageBounds.maxX - 100.0  // (use if/when you separate date vs initials)

        var y = startY - lineHeight // begin one row below the header
        while y >= stopY {
            // Currently we print combined "YYYYMMDD / AB" at initials column.
            drawText(value, at: CGPoint(x: rightInitX, y: y), font: font, cg: cg)
            y -= lineHeight
        }
    }

    /// Stamp White-phase value on every ACFT row.
    private static func fillACFTRows(on page: PDFPage, value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let x = pageBounds.maxX - 160.0
        for sel in selections(in: page, token: "ACFT") {
            let r = sel.bounds(for: page)
            let y = r.midY - 4
            drawText(value, at: CGPoint(x: x, y: y), font: font, cg: cg)
        }
    }

    /// Draw `value` to the right of the first matching token (nice for top banner fields).
    private static func overlayRight(ofAnyToken tokens: [String], on page: PDFPage, yNudge: CGFloat, draw value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        for t in tokens {
            if let sel = selection(in: page, token: t) {
                let r = sel.bounds(for: page)
                drawText(value, at: CGPoint(x: r.maxX + 8, y: r.minY + yNudge), font: font, cg: cg)
                return
            }
        }
    }

    /// Stamp the 4 “Required Task” rows (top block) with the Red value.
    private static func fillRequiredTasksTopBlock(on page: PDFPage, redValue: String, font: UIFont, cg: CGContext) {
        guard !redValue.isEmpty else { return }
        let items = [
            "Esatblish Bank Account",   // (typo preserved from the form text)
            "Start Direct Deposit",
            "Set up AKO Account",
            "Set up MyPay Account"
        ]
        let pageBounds = page.bounds(for: .mediaBox)
        let x = pageBounds.maxX - 160.0
        for token in items {
            if let sel = selection(in: page, token: token) {
                let r = sel.bounds(for: page)
                let y = r.midY - 4
                drawText(redValue, at: CGPoint(x: x, y: y), font: font, cg: cg)
            }
        }
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
