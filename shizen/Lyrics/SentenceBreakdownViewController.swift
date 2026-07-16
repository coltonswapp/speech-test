//
//  SentenceBreakdownViewController.swift
//  shizen
//
//  Sentence (title) + left-aligned flow of underlined tappable word chips. Definition tip on tap.
//

import UIKit

// MARK: - Left-aligned flow (variable-width items wrap, rows align left)

private final class LeftAlignedCollectionViewFlowLayout: UICollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard
            let original = super.layoutAttributesForElements(in: rect)
        else { return nil }
        let a = original.map { $0.copy() as! UICollectionViewLayoutAttributes }
        var left = sectionInset.left
        var lineY: CGFloat = -1
        for at in a.sorted(by: {
            if abs($0.frame.minY - $1.frame.minY) > 0.5 { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }) {
            if at.representedElementKind != nil { continue }
            if lineY < 0 { lineY = at.frame.minY }
            if abs(at.frame.minY - lineY) > 0.5 {
                left = sectionInset.left
                lineY = at.frame.minY
            }
            at.frame.origin.x = left
            left += at.frame.width + minimumInteritemSpacing
        }
        return a
    }
}

// MARK: - Token cell

private final class TokenCollectionViewCell: UICollectionViewCell {
    static let reuseId = "TokenCollectionViewCell"
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 1
        textLabel.textAlignment = .center
        contentView.addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            textLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        let font = UIFont.preferredFont(forTextStyle: .title3)
        let m = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        textLabel.attributedText = m
    }
}

// MARK: - View controller

final class SentenceBreakdownViewController: UIViewController {

    private let sentence: String
    private var tokens: [JapaneseToken] = []
    private var tokenLookupSurfaces: [String] = []
    private let tokenizer = JapaneseTokenizer()

    private let sentenceLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = UIFont.preferredFont(forTextStyle: .title1)
        l.textColor = .label
        return l
    }()

    private lazy var collectionView: UICollectionView = {
        let flow = LeftAlignedCollectionViewFlowLayout()
        flow.scrollDirection = .vertical
        flow.estimatedItemSize = .zero
        flow.minimumInteritemSpacing = 8
        flow.minimumLineSpacing = 10
        flow.sectionInset = .zero
        let cv = UICollectionView(frame: .zero, collectionViewLayout: flow)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.allowsSelection = true
        cv.alwaysBounceVertical = true
        cv.register(TokenCollectionViewCell.self, forCellWithReuseIdentifier: TokenCollectionViewCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private var collectionHeightConstraint: NSLayoutConstraint?

    init(sentence: String) {
        self.sentence = sentence
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        overrideUserInterfaceStyle = .light

        tokens = Self.expandIfSingleFullSentenceToken(
            base: sentence,
            tokens: tokenizer.tokenize(sentence)
        )
        tokenLookupSurfaces = JMDictStore.shared.effectiveLookupSurfaces(for: tokens)
        sentenceLabel.text = sentence

        title = "Words"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        view.addSubview(sentenceLabel)
        view.addSubview(collectionView)

        let h = collectionView.heightAnchor.constraint(equalToConstant: 1)
        h.priority = .defaultHigh
        h.isActive = true
        collectionHeightConstraint = h

        NSLayoutConstraint.activate([
            sentenceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            sentenceLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            sentenceLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: sentenceLabel.bottomAnchor, constant: 24),
            collectionView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        collectionView.reloadData()
    }

override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
        let w = max(collectionView.bounds.width, 1)
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        let hGap: CGFloat = 8, vGap: CGFloat = 10
        let font = UIFont.preferredFont(forTextStyle: .title3)
        for t in tokens {
            let sz = (t.text as NSString).size(withAttributes: [.font: font])
            let cw = ceil(sz.width) + 20, ch = ceil(sz.height) + 12
            if x > 0, x + cw > w {
                y += rowH + vGap
                x = 0
                rowH = 0
            }
            rowH = max(rowH, ch)
            x += cw + hGap
        }
        y += rowH
        collectionHeightConstraint?.constant = max(y, 60)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    // MARK: - Token expansion (single full-string NLToken)

    private static func expandIfSingleFullSentenceToken(base: String, tokens: [JapaneseToken]) -> [JapaneseToken] {
        guard
            tokens.count == 1,
            let t = tokens.first,
            t.text == base,
            t.text.count > 1
        else { return tokens }

        var out: [JapaneseToken] = []
        var i = base.startIndex
        while i < base.endIndex {
            let c = String(base[i])
            let j = base.index(after: i)
            let isOnlyPuncOrSpace = c.unicodeScalars.allSatisfy { s in
                CharacterSet.punctuationCharacters.contains(s)
                || CharacterSet.whitespacesAndNewlines.contains(s)
            }
            if isOnlyPuncOrSpace {
                i = j
                continue
            }
            if !c.isEmpty {
                out.append(JapaneseToken(text: c, range: i..<j))
            }
            i = j
        }
        return out.isEmpty ? tokens : out
    }
}

// MARK: - Collection

extension SentenceBreakdownViewController: UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout
{

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tokens.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TokenCollectionViewCell.reuseId,
            for: indexPath
        ) as! TokenCollectionViewCell
        cell.configure(text: tokens[indexPath.item].text)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let text = tokens[indexPath.item].text
        let font = UIFont.preferredFont(forTextStyle: .title3)
        let wMax = max(collectionView.bounds.width, 1)
        let s = (text as NSString).boundingRect(
            with: CGSize(width: wMax, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(
            width: min(wMax, ceil(s.width) + 20),
            height: ceil(s.height) + 12
        )
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let i = indexPath.item
        let surface =
            tokenLookupSurfaces.indices.contains(i) ? tokenLookupSurfaces[i] : tokens[i].text
        WordDictionaryDetailSheetPresenter.present(surface: surface, sentence: sentence, from: self)
    }
}
