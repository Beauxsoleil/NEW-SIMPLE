import Foundation

/// Swap your inline demo tables to this loader.
/// It compiles "as is" with starter data and can read full CSVs from the bundle in the future.
enum BodyCompTables {

    // MARK: - Embedded starter data (compiles today)
    static let embeddedHTWT = """
heightIn,minWeight,male17_20,male21_27,male28_39,male40plus,female17_20,female21_27,female28_39,female40plus
60,97,132,136,139,141,128,129,131,133
61,100,136,140,144,146,132,134,135,137
62,104,141,144,148,150,136,138,140,142
63,107,145,149,153,155,141,143,144,146
64,110,150,154,158,160,145,147,149,151
65,114,155,159,163,165,150,152,154,156
66,117,160,163,168,170,155,156,158,161
67,121,165,169,174,176,159,161,163,166
68,125,170,174,179,181,164,166,168,171
69,128,175,179,184,186,169,171,173,176
70,132,180,185,189,192,174,176,178,181
"""

    static let embeddedBFLimits = """
minAge,maxAge,maleMaxPct,femaleMaxPct
17,20,20,30
21,27,22,32
28,39,24,34
40,150,26,36
"""

    // Minimal demo charts; replace by bundle CSV later (same shape)
    static let embeddedOneSiteMale = """
waistIn,w120,w125,w130,w135
28,7,8,9,10
29,8,9,10,11
30,9,10,11,12
"""
    static let embeddedOneSiteFemale = """
waistIn,w120,w125,w130,w135
28,15,16,17,18
29,16,17,18,19
30,17,18,19,20
"""

    // MARK: - Future: Bundle CSV loading (call from BodyCompService.loadFullTablesIfAvailable())
    static func loadCSV(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "csv"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
