import Foundation
import PDFKit
import UIKit

struct StripesForSkillsData {
    let applicantName: String       // e.g., "John Doe"
    let recruiterName: String       // e.g., from Settings.recruiterName
    let recruiterInitials: String   // e.g., from Settings.recruiterInitials
    let drill1: Date?               // First drill (Red Phase)
    let drill2: Date?               // Second drill (White Phase & top Date)
}

enum StripesForSkillsFiller {

    // MARK: - Public entry point
    static func fill(templateURL: URL, data: StripesForSkillsData) throws -> URL {
        guard let doc = PDFDocument(url: templateURL), doc.pageCount > 0 else {
            throw NSError(domain: "StripesFiller", code: -1, userInfo: [NSLocalizedDescriptionKey: "Template PDF not found or empty"])
        }

        let df = DateFormatter(); df.dateStyle = .short
        let d1 = data.drill1.map { df.string(from: $0) } ?? ""
        let d2 = data.drill2.map { df.string(from: $0) } ?? ""

        // Render each page to a new PDF, drawing the original page, then our overlays.
        let pageRect = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("STRIPES_\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: outURL) { ctx in
            for pageIndex in 0..<doc.pageCount {
                ctx.beginPage()
                guard let page = doc.page(at: pageIndex) else { continue }
                let cg = ctx.cgContext

                // Draw original page
                cg.saveGState()
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()

                // Only page 1 expected for this form, but code is safe if more pages exist.
                // Top fields (Name/Rank, Platoon SGT/Unit, Date):
                // We find anchors by text and place values to the right with a small offset.
                overlayRight(ofText: "NAME", on: page, yNudge: 0,  draw: "PVT \(data.applicantName)", font: .systemFont(ofSize: 12), into: cg)
                overlayRight(ofText: "RANK", on: page, yNudge: 0,  draw: "", font: .systemFont(ofSize: 12), into: cg) // tolerate variants
                overlayRight(ofText: "PLATOON", on: page, yNudge: 0, draw: "\(data.recruiterName) / DET 3 RSP", font: .systemFont(ofSize: 12), into: cg)
                overlayRight(ofText: "Date", on: page, yNudge: 0,   draw: d2, font: .systemFont(ofSize: 12), into: cg)

                // Red Phase → Drill1 + initials
                fillPhase(on: page,
                          contains: "STRM Red Phase",
                          initials: data.recruiterInitials,
                          date: d1,
                          into: cg)

                // White Phase → Drill2 + initials
                fillPhase(on: page,
                          contains: "STRM White Phase",
                          initials: data.recruiterInitials,
                          date: d2,
                          into: cg)

                // We *intentionally* DO NOT touch ACFT Points/ACT score fields or bottom signatures.
            }
        }

        return outURL
    }

    // MARK: - Helpers

    /// Writes two small entries ("AB" and "01/02/25") near each anchor that contains the phase text.
    /// We place them toward the right margin on the same line, with defensible default offsets.
    private static func fillPhase(on page: PDFPage, contains phaseMarker: String, initials: String, date: String, into cg: CGContext) {
        let anchors = selections(for: phaseMarker, on: page)
        let font = UIFont.systemFont(ofSize: 10)

        for sel in anchors {
            let r = sel.bounds(for: page)
            // Heuristic: the "Initials/Date of Completion" column is usually far right on same line.
            // So we draw toward the right side of the page horizontally aligned with the anchor's midY.
            let pageBounds = page.bounds(for: .mediaBox)
            let y = r.midY - 4  // center-ish vertically on the line

            // Draw initials, then date just to its right.
            drawText(initials, at: CGPoint(x: pageBounds.maxX - 160, y: y), font: font, into: cg)
            drawText(date,     at: CGPoint(x: pageBounds.maxX - 100, y: y), font: font, into: cg)
        }
    }

    /// Find anchor by a (partial) text token and place a value just to the right of its bounding box.
    private static func overlayRight(ofText token: String, on page: PDFPage, yNudge: CGFloat, draw value: String, font: UIFont, into cg: CGContext) {
        guard let sel = selections(for: token, on: page).first else { return }
        let r = sel.bounds(for: page)
        guard !value.isEmpty else { return }
        let point = CGPoint(x: r.maxX + 8, y: r.minY + yNudge)
        drawText(value, at: point, font: font, into: cg)
    }

    private static func drawText(_ text: String, at point: CGPoint, font: UIFont, into cg: CGContext) {
        let attrs: [NSAttributedString.Key:Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func selections(for token: String, on page: PDFPage) -> [PDFSelection] {
        // Try exact first
        if let sel = page.selection(for: token) {
            return [sel]
        }
        // Fallback: find by scanning attributed string for the token (case-insensitive)
        guard let full = page.attributedString?.string else { return [] }
        let lower = full.lowercased()
        let needle = token.lowercased()
        guard let range = lower.range(of: needle) else { return [] }
        let nsRange = NSRange(range, in: full)
        if let s = page.selection(for: nsRange) { return [s] }
        return []
    }
}

private extension PDFPage {
    /// Exact selection helper (PDFKit lacks a direct "selectionForString" API on iOS).
    func selection(for string: String) -> PDFSelection? {
        guard let doc = document else { return nil }
        let all = doc.findString(string, withOptions: .caseInsensitive)
        // Filter to this page only
        return all.first { $0.pages.contains(self) }
    }

    /// Build a selection from an NSRange in the page’s plain text if available.
    func selection(for range: NSRange) -> PDFSelection? {
        guard let attr = attributedString else { return nil }
        guard range.location != NSNotFound, NSMaxRange(range) <= attr.length else { return nil }
        let sel = PDFSelection(document: document!)
        sel?.add(self)
        // We cannot set the exact range directly; this is a best-effort approach using findString for substrings
        // In practice, anchorFinding above will usually succeed via selection(for: string).
        return sel
    }
}

