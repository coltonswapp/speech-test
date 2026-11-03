//
//  PaywallExperimentViewController.swift
//  shizen
//
//  Picker for the custom paywall variants, with mock-offering knobs (trial
//  eligibility, currency) so each layout can be checked in every state.
//

import UIKit

final class PaywallExperimentViewController: UITableViewController {
    enum Variant: CaseIterable {
        case hana, hanaGlass, glowGlass, featureCarousel, timeline, compare, boldHero, boldHeroGlass, boldHeroGlassCompact, boldHeroGlassCompactPlain, nightGlow

        var title: String {
            switch self {
            case .hana: return "Hana pitch"
            case .hanaGlass: return "Hana pitch · glass"
            case .glowGlass: return "Glow · glass"
            case .featureCarousel: return "Feature carousel · glass"
            case .timeline: return "Trial timeline"
            case .compare: return "Free vs Pro"
            case .boldHero: return "Bold hero"
            case .boldHeroGlass: return "Bold hero · glass"
            case .boldHeroGlassCompact: return "Bold hero · glass compact"
            case .boldHeroGlassCompactPlain: return "Bold hero · glass compact · plain"
            case .nightGlow: return "Night glow"
            }
        }

        var subtitle: String {
            switch self {
            case .hana: return "Mascot speech bubble · tiled features · short plan tiles"
            case .hanaGlass: return "Brand blobs · glass bubble, feature grid, plans · Hana reacts"
            case .glowGlass: return "Night glow's short pitch on brand blobs · glass features & plans"
            case .featureCarousel: return "Swipe feature cards with lesson art & previews · side-by-side plans"
            case .timeline: return "Today → reminder → billing day · Yearly/Monthly switch"
            case .compare: return "Comparison table · side-by-side plan cards"
            case .boldHero: return "Huge headline on grid · bottom sheet · black CTA"
            case .boldHeroGlass: return "Huge headline on grid over brand blobs · feature carousel · short plan tiles"
            case .boldHeroGlassCompact: return "Smaller title & subhead · feature carousel · short plan tiles"
            case .boldHeroGlassCompactPlain: return "Compact headline on a plain grid · no color blobs · feature carousel · short plan tiles"
            case .nightGlow: return "Hana in a yellow glow · free-trial switch · per-week prices"
            }
        }

        var symbolName: String {
            switch self {
            case .hana: return "camera.macro"
            case .hanaGlass: return "drop.halffull"
            case .glowGlass: return "sparkles"
            case .featureCarousel: return "rectangle.stack"
            case .timeline: return "calendar.badge.clock"
            case .compare: return "tablecells"
            case .boldHero: return "textformat.size.larger"
            case .boldHeroGlass: return "textformat.size"
            case .boldHeroGlassCompact: return "textformat.size.smaller"
            case .boldHeroGlassCompactPlain: return "square.grid.3x3"
            case .nightGlow: return "moon.stars.fill"
            }
        }

        func makeViewController(provider: PaywallProviding) -> PaywallBaseViewController {
            switch self {
            case .hana: return PaywallHanaViewController(provider: provider)
            case .hanaGlass: return PaywallHanaGlassViewController(provider: provider)
            case .glowGlass: return PaywallGlowGlassViewController(provider: provider)
            case .featureCarousel: return PaywallFeatureCarouselViewController(provider: provider)
            case .timeline: return PaywallTimelineViewController(provider: provider)
            case .compare: return PaywallCompareViewController(provider: provider)
            case .boldHero: return PaywallBoldHeroViewController(provider: provider)
            case .boldHeroGlass: return PaywallBoldHeroGlassViewController(provider: provider)
            case .boldHeroGlassCompact: return PaywallBoldHeroGlassViewController(provider: provider, headline: .compact)
            case .boldHeroGlassCompactPlain: return PaywallBoldHeroGlassViewController(provider: provider, headline: .compact, showsColorBlobs: false)
            case .nightGlow: return PaywallNightGlowViewController(provider: provider)
            }
        }
    }

    private enum Section: Int, CaseIterable {
        case variants, offering
    }

    private let provider = MockPaywallProvider()
    private let cellID = "cell"

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Paywalls"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .variants: return Variant.allCases.count
        case .offering: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .variants: return "Variants"
        case .offering: return "Mock offering"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .variants: return nil
        case .offering: return "Ineligible users see no trial copy. Impressions so far: \(provider.impressionCount)."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .variants:
            let variant = Variant.allCases[indexPath.row]
            content.text = variant.title
            content.secondaryText = variant.subtitle
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: variant.symbolName)
            cell.accessoryType = .disclosureIndicator
        case .offering:
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                content.text = "Trial eligible"
                let toggle = UISwitch()
                toggle.isOn = provider.isTrialEligible
                toggle.addAction(UIAction { [weak self, weak toggle] _ in
                    self?.provider.isTrialEligible = toggle?.isOn ?? true
                }, for: .valueChanged)
                cell.accessoryView = toggle
                content.image = UIImage(systemName: "gift")
            } else {
                content.text = "Currency"
                let currencies = MockPaywallProvider.Currency.allCases
                let segmented = UISegmentedControl(items: currencies.map(\.rawValue))
                segmented.selectedSegmentIndex = currencies.firstIndex(of: provider.currency) ?? 0
                segmented.addAction(UIAction { [weak self, weak segmented] _ in
                    guard let segmented else { return }
                    self?.provider.currency = currencies[segmented.selectedSegmentIndex]
                }, for: .valueChanged)
                cell.accessoryView = segmented
                content.image = UIImage(systemName: "dollarsign.circle")
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .variants else { return }
        present(Variant.allCases[indexPath.row].makeViewController(provider: provider), animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh the impression count in the footer after a paywall closes.
        tableView.reloadSections(IndexSet(integer: Section.offering.rawValue), with: .none)
    }
}
