import Foundation
import PDFKit
import UIKit

public struct SFSInput {
    public let applicantFullName: String
    public let recruiterName: String
    public let recruiterInitials: String
    public let drill1: Date?
    public let drill2: Date?
}

public enum StripesForSkillsFiller {

    public static func fill(templateURL: URL, input: SFSInput) throws -> URL {
        guard let doc = PDFDocument(url: templateURL), doc.pageCount > 0 else {
            throw NSError(domain: "StripesForSkills", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Template PDF not found or empty"])
        }
        let touched = fillAcroFormIfPossible(in: doc, input: input)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SFS_\(UUID().uuidString).pdf")
        if touched {
            doc.write(to: outURL)
            return outURL
        }
        return try renderWithOverlays(from: doc, input: input, outURL: outURL)
    }

    @discardableResult
    private static func fillAcroFormIfPossible(in doc: PDFDocument, input: SFSInput) -> Bool {
        var wrote = false
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        let d1 = input.drill1.map { df.string(from: $0) } ?? ""
        let d2 = input.drill2.map { df.string(from: $0) } ?? ""
        let topName   = "PVT \(input.applicantFullName)"
        let topUnit   = "\(input.recruiterName) / DET 3 RSP"
        let redText   = combine(date: d1, initials: input.recruiterInitials)
        let whiteText = combine(date: d2, initials: input.recruiterInitials)
        for p in 0 ..< doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            for ann in page.annotations where ann.widgetFieldType == .text {
                let name = safeFieldName(ann)
                guard !name.isEmpty else { continue }
                if equals(name, "NAME  RANK") { ann.widgetStringValue = topName;   wrote = true; continue }
                if equals(name, "PLATOON SGTUNIT") { ann.widgetStringValue = topUnit; wrote = true; continue }
                if equals(name, "Date") { ann.widgetStringValue = d2; wrote = true; continue }
                let lower = name.lowercased()
                if lower.contains("strm red phase") { ann.widgetStringValue = redText; wrote = true; continue }
                if lower.contains("strm white phase") { ann.widgetStringValue = whiteText; wrote = true; continue }
                if lower.contains("acft") { ann.widgetStringValue = whiteText; wrote = true; continue }
            }
        }
        return wrote
    }

    private static func renderWithOverlays(from doc: PDFDocument, input: SFSInput, outURL: URL) throws -> URL {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        let d1 = input.drill1.map { df.string(from: $0) } ?? ""
        let d2 = input.drill2.map { df.string(from: $0) } ?? ""
        let topName   = "PVT \(input.applicantFullName)"
        let topUnit   = "\(input.recruiterName) / DET 3 RSP"
        let redText   = combine(date: d1, initials: input.recruiterInitials)
        let whiteText = combine(date: d2, initials: input.recruiterInitials)
        let pageBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        try renderer.writePDF(to: outURL) { ctx in
            for i in 0 ..< doc.pageCount {
                ctx.beginPage()
                guard let page = doc.page(at: i) else { continue }
                let cg = ctx.cgContext
                page.draw(with: .mediaBox, to: cg)
                let big   = UIFont.systemFont(ofSize: 12)
                let small = UIFont.systemFont(ofSize: 10)

                // top banner (anchor-based)
                overlayRight(ofAnyToken: ["NAME & RANK", "NAME", "NAME  RANK"],
                             on: page, yNudge: 0,
                             draw: topName, font: big, cg: cg)
                overlayRight(ofAnyToken: ["PLATOON SGT/UNIT", "PLATOON", "UNIT"],
                             on: page, yNudge: 0,
                             draw: topUnit, font: big, cg: cg)
                if let sel = firstToken("Date", on: page, topFraction: 0.25) {
                    let r = sel.bounds(for: page)
                    drawText(d2, at: CGPoint(x: r.maxX + 8, y: r.minY), font: big, cg: cg)
                }

                // top Required Task block → red
                stampTokenList(on: page,
                    tokens: [
                        "Esatblish Bank Account",
                        "Start Direct Deposit",
                        "Set up AKO Account",
                        "Set up MyPay Account"
                    ],
                    value: redText, font: small, cg: cg)

                // red phase headers + bullets
                stampTokenList(on: page,
                    tokens: [
                        "Drill and Ceremony (STRM Red Phase)",
                        "Execute Rest Positions While at the Halt (STRM Red Phase)",
                        "Execute Facing Movements While at the Halt (STRM Red Phase)",
                        "Marching (STRM Red Phase)",
                        "Idenitfy Rank Structure (STRM Red Phase)",
                        "Phonetic Alphabet (STRM Red Phase)",
                        "Execute the Position of Attention",
                        "Execute the Hand Salute",
                        "Know Who and When to Salute",
                        "Parade Rest",
                        "Stand at Ease",
                        "At Ease",
                        "Rest",
                        "Right Face",
                        "Left Face",
                        "About Face",
                        "Forward March",
                        "Half Step",
                        "Change Step",
                        "Enlisted Ranks",
                        "Officer Ranks",
                        "Warrant Officer Ranks",
                        "Know / Recite Phonetic Alphabet"
                    ],
                    value: redText, font: small, cg: cg)

                // white phase headers + bullets
                stampTokenList(on: page,
                    tokens: [
                        "Military Time (STRM White Phase Stripes for Skills)",
                        "Column Left (STRM White Phase)",
                        "Column Right (STRM White Phase)",
                        "Recite General Orders (STRM White Phase Stripes for Skills)",
                        "First Aid/CLS (STRM White Phase)",
                        "Halt",
                        "First General Order",
                        "Second General Order",
                        "Third General Order",
                        "Evaluate a Casualty",
                        "Perform First Aid and Prctice Individual Preventative Medicine Countermeasures",
                        "Perform First Aid for Bleeding Extremity",
                        "Perform First Aid for Splinting a Fracture"
                    ],
                    value: whiteText, font: small, cg: cg)

                // ACFT rows (use white)
                stampTokenList(on: page,
                    tokens: [
                        "3RM Deadlift",
                        "Standing Power Throw",
                        "Hand Release Push-Up",
                        "Sprint, Drag, Carry",
                        "Plank",
                        "2.0-Mile Run"
                    ],
                    value: whiteText, font: small, cg: cg)
            }
        }
        return outURL
    }

    private static func drawText(_ text: String, at p: CGPoint, font: UIFont, cg: CGContext) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key : Any] = [.font: font, .foregroundColor: UIColor.black]
        (text as NSString).draw(at: p, withAttributes: attrs)
    }

    private static func firstToken(_ token: String, on page: PDFPage, topFraction: CGFloat? = nil) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        let hits = doc.findString(token, withOptions: .caseInsensitive)
        if let top = topFraction {
            let h = page.bounds(for: .mediaBox).height
            return hits.first { $0.pages.contains(page) && $0.bounds(for: page).minY <= h * top }
        }
        return hits.first { $0.pages.contains(page) }
    }

    private static func selection(in page: PDFPage, token: String) -> PDFSelection? {
        guard let doc = page.document else { return nil }
        return doc.findString(token, withOptions: .caseInsensitive)
            .first { $0.pages.contains(page) }
    }

    private static func stampTokenList(on page: PDFPage, tokens: [String], value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let x = pageBounds.maxX - 160.0
        for token in tokens {
            if let sel = selection(in: page, token: token) {
                let r = sel.bounds(for: page)
                let y = r.midY - 4
                drawText(value, at: CGPoint(x: x, y: y), font: font, cg: cg)
            }
        }
    }

    private static func overlayRight(ofAnyToken tokens: [String], on page: PDFPage, yNudge: CGFloat,
                                     draw value: String, font: UIFont, cg: CGContext) {
        guard !value.isEmpty else { return }
        for t in tokens {
            if let sel = selection(in: page, token: t) {
                let r = sel.bounds(for: page)
                drawText(value, at: CGPoint(x: r.maxX + 8, y: r.minY + yNudge), font: font, cg: cg)
                return
            }
        }
    }

    private static func safeFieldName(_ ann: PDFAnnotation) -> String {
        if let n = ann.fieldName, !n.isEmpty { return n }
        if let n = ann.value(forAnnotationKey: PDFAnnotationKey(rawValue: "T")) as? String, !n.isEmpty { return n }
        return ""
    }
    private static func equals(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
    private static func containsAny(_ s: String, _ options: [String]) -> Bool {
        options.contains { s.range(of: $0, options: .caseInsensitive) != nil }
    }
    private static func combine(date: String, initials: String) -> String {
        guard !date.isEmpty, !initials.isEmpty else { return date.isEmpty ? initials : date }
        return "\(date) / \(initials)"
    }
}

