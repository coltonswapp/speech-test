//
//  KatakanaChartViews.swift
//  shizen
//
//  Katakana grids (seion, dakuten, yōon) for KatakanaChartViewController (DEBUG).
//


import UIKit

private enum KatakanaChartMetrics {
    /// Tracks row labels (`k-`, …) and aligns the header spacer with that column.
    static let prefixColumnWidth: CGFloat = 18
    /// Space between prefix column and the five kana tiles (also below `-a`/… headers).
    static let prefixToGridSpacing: CGFloat = 14
    /// Matches `KanaCard` geometry so textbook gaps occupy the same cell bounds without chrome.
    static let kanaTileAspectHeightOverWidth: CGFloat = 1.28
}

// MARK: - Chart model

private struct KatakanaChartRowSpec {
    let rowSound: String
    let cells: [(kana: String?, romaji: String?)]
}

private enum KatakanaReferenceCharts {
    static let sheetEmpty: (String?, String?) = (nil, nil)
    static let vowelSuffixes = ["-a", "-i", "-u", "-e", "-o"]

    static let seion: [KatakanaChartRowSpec] = [
        KatakanaChartRowSpec(rowSound: "", cells: zipKana(["ア", "イ", "ウ", "エ", "オ"], ["a", "i", "u", "e", "o"])),
        KatakanaChartRowSpec(rowSound: "k-", cells: zipKana(["カ", "キ", "ク", "ケ", "コ"], ["ka", "ki", "ku", "ke", "ko"])),
        KatakanaChartRowSpec(rowSound: "s-", cells: zipKana(["サ", "シ", "ス", "セ", "ソ"], ["sa", "shi", "su", "se", "so"])),
        KatakanaChartRowSpec(rowSound: "t-", cells: zipKana(["タ", "チ", "ツ", "テ", "ト"], ["ta", "chi", "tsu", "te", "to"])),
        KatakanaChartRowSpec(rowSound: "n-", cells: zipKana(["ナ", "ニ", "ヌ", "ネ", "ノ"], ["na", "ni", "nu", "ne", "no"])),
        KatakanaChartRowSpec(rowSound: "h-", cells: zipKana(["ハ", "ヒ", "フ", "ヘ", "ホ"], ["ha", "hi", "fu", "he", "ho"])),
        KatakanaChartRowSpec(rowSound: "m-", cells: zipKana(["マ", "ミ", "ム", "メ", "モ"], ["ma", "mi", "mu", "me", "mo"])),
        KatakanaChartRowSpec(rowSound: "y-", cells: [
            ("ヤ", "ya"), sheetEmpty, ("ユ", "yu"), sheetEmpty, ("ヨ", "yo"),
        ]),
        KatakanaChartRowSpec(rowSound: "r-", cells: zipKana(["ラ", "リ", "ル", "レ", "ロ"], ["ra", "ri", "ru", "re", "ro"])),
        KatakanaChartRowSpec(rowSound: "w-", cells: [
            ("ワ", "wa"), sheetEmpty, sheetEmpty, sheetEmpty, ("ヲ", "wo"),
        ]),
        KatakanaChartRowSpec(rowSound: "", cells: [
            sheetEmpty, sheetEmpty, ("ン", "n"), sheetEmpty, sheetEmpty,
        ]),
    ]

    /// Dakuten (ﾞ) and handakuten (ﾟ) counterparts to k/s/t/h rows — ガ行 through パ行.
    static let voiced: [KatakanaChartRowSpec] = [
        KatakanaChartRowSpec(rowSound: "g-", cells: zipKana(["ガ", "ギ", "グ", "ゲ", "ゴ"], ["ga", "gi", "gu", "ge", "go"])),
        KatakanaChartRowSpec(rowSound: "z-", cells: zipKana(["ザ", "ジ", "ズ", "ゼ", "ゾ"], ["za", "ji", "zu", "ze", "zo"])),
        KatakanaChartRowSpec(rowSound: "d-", cells: zipKana(["ダ", "ヂ", "ヅ", "デ", "ド"], ["da", "ji", "zu", "de", "do"])),
        KatakanaChartRowSpec(rowSound: "b-", cells: zipKana(["バ", "ビ", "ブ", "ベ", "ボ"], ["ba", "bi", "bu", "be", "bo"])),
        KatakanaChartRowSpec(rowSound: "p-", cells: zipKana(["パ", "ピ", "プ", "ペ", "ポ"], ["pa", "pi", "pu", "pe", "po"])),
    ]

    /// Yōon keeps **five equally wide slots** (same tile size as gojūon): three glyphs **left-aligned**, two trailing `sheetEmpty` columns — aligns with the −a · −i · −u lanes of charts above.
    static let yoonColumnHeaders = ["-ya", "-yu", "-yo", "", ""]

    static let yoon: [KatakanaChartRowSpec] = [
        yoonPaddedRow(rowSound: "k-", k: ["キャ", "キュ", "キョ"], r: ["kya", "kyu", "kyo"]),
        yoonPaddedRow(rowSound: "sh-", k: ["シャ", "シュ", "ショ"], r: ["sha", "shu", "sho"]),
        yoonPaddedRow(rowSound: "ch-", k: ["チャ", "チュ", "チョ"], r: ["cha", "chu", "cho"]),
        yoonPaddedRow(rowSound: "n-", k: ["ニャ", "ニュ", "ニョ"], r: ["nya", "nyu", "nyo"]),
        yoonPaddedRow(rowSound: "h-", k: ["ヒャ", "ヒュ", "ヒョ"], r: ["hya", "hyu", "hyo"]),
        yoonPaddedRow(rowSound: "m-", k: ["ミャ", "ミュ", "ミョ"], r: ["mya", "myu", "myo"]),
        yoonPaddedRow(rowSound: "r-", k: ["リャ", "リュ", "リョ"], r: ["rya", "ryu", "ryo"]),
        yoonPaddedRow(rowSound: "g-", k: ["ギャ", "ギュ", "ギョ"], r: ["gya", "gyu", "gyo"]),
        yoonPaddedRow(rowSound: "j-", k: ["ジャ", "ジュ", "ジョ"], r: ["ja", "ju", "jo"]),
        yoonPaddedRow(rowSound: "b-", k: ["ビャ", "ビュ", "ビョ"], r: ["bya", "byu", "byo"]),
        yoonPaddedRow(rowSound: "p-", k: ["ピャ", "ピュ", "ピョ"], r: ["pya", "pyu", "pyo"]),
    ]

    private static func yoonPaddedRow(rowSound: String, k: [String], r: [String]) -> KatakanaChartRowSpec {
        KatakanaChartRowSpec(rowSound: rowSound, cells: zipKana(k, r) + [sheetEmpty, sheetEmpty])
    }

    static func zipKana(_ k: [String], _ r: [String]) -> [(kana: String?, romaji: String?)] {
        precondition(k.count == r.count && !r.isEmpty)
        return zip(k, r).map { (kana: $0.0, romaji: $0.1) }
    }
}

// MARK: - KatakanaGridChartView

/// Shared column-header row + stacked `KanaChartRowView`s (gojūon, yōon, …).
/// Reuses `KanaCard` / `KanaChartRowView` from `HiraganaChartViews.swift` so the tile geometry stays in lockstep.
final class KatakanaGridChartView: UIView {

    enum GridKind {
        case seion
        case voiced
        case yoon
    }

    fileprivate init(
        columnSuffixes: [String],
        rows: [KatakanaChartRowSpec],
        onKanaSelected: ((String, String) -> Void)? = nil
    ) {
        precondition(!columnSuffixes.isEmpty)
        for row in rows {
            precondition(
                row.cells.count == columnSuffixes.count,
                "Row \(row.rowSound) cell count \(row.cells.count) != column count \(columnSuffixes.count)"
            )
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let leadingSpacer = UIView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        leadingSpacer.widthAnchor.constraint(equalToConstant: KatakanaChartMetrics.prefixColumnWidth).isActive = true

        let suffixStack = UIStackView(arrangedSubviews: columnSuffixes.map { suffix in
            let lbl = UILabel()
            lbl.text = suffix
            lbl.font = .preferredFont(forTextStyle: .footnote)
            lbl.textColor = .secondaryLabel
            lbl.adjustsFontForContentSizeCategory = true
            lbl.textAlignment = .center
            return lbl
        })
        suffixStack.axis = .horizontal
        suffixStack.spacing = 6
        suffixStack.translatesAutoresizingMaskIntoConstraints = false
        suffixStack.alignment = .center
        suffixStack.distribution = .fillEqually

        let headerRow = UIStackView(arrangedSubviews: [leadingSpacer, suffixStack])
        headerRow.axis = .horizontal
        headerRow.spacing = KatakanaChartMetrics.prefixToGridSpacing
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.alignment = .center

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.spacing = 8
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        for row in rows {
            bodyStack.addArrangedSubview(
                KanaChartRowView(rowSound: row.rowSound, cells: row.cells)
            )
        }

        let rootStack = UIStackView(arrangedSubviews: [headerRow, bodyStack])
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init(kind: GridKind, onKanaSelected: ((String, String) -> Void)? = nil) {
        switch kind {
        case .seion:
            self.init(
                columnSuffixes: KatakanaReferenceCharts.vowelSuffixes,
                rows: KatakanaReferenceCharts.seion,
                onKanaSelected: onKanaSelected
            )
        case .voiced:
            self.init(
                columnSuffixes: KatakanaReferenceCharts.vowelSuffixes,
                rows: KatakanaReferenceCharts.voiced,
                onKanaSelected: onKanaSelected
            )
        case .yoon:
            self.init(
                columnSuffixes: KatakanaReferenceCharts.yoonColumnHeaders,
                rows: KatakanaReferenceCharts.yoon,
                onKanaSelected: onKanaSelected
            )
        }
    }
}
