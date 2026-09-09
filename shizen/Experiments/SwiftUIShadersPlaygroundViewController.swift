//
//  SwiftUIShadersPlaygroundViewController.swift
//  shizen
//
//  Experimental playground for Kris Puckett’s SwiftUIShaders (SPM).
//  All 41 effects — Settings → SwiftUI shaders.
//

import SwiftUI
import SwiftUIShaders
import UIKit

enum SwiftUIShaderDemo: String, CaseIterable, Identifiable {
    case aurora
    case blackHole
    case chromaticSplit
    case datamosh
    case disintegrate
    case duochrome
    case echo
    case emboss
    case etherealAura
    case frosted
    case geometricWarp
    case glitch
    case gravityWells
    case heatShimmer
    case holographic
    case inkBleed
    case kaleidoscope
    case liquidChrome
    case liquidMirror
    case liveRipple
    case magneticField
    case melt
    case morphBreathe
    case neonEdge
    case pixelateMosaic
    case pixelateStorm
    case plasma
    case pulse
    case refractLens
    case shatter
    case shatterGlass
    case shockwave
    case smokeReveal
    case solarize
    case thermal
    case topographic
    case touchRipple
    case underwaterCaustics
    case vortex
    case wavePool
    case wormhole

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .blackHole: return "Black hole"
        case .chromaticSplit: return "Chromatic split"
        case .datamosh: return "Datamosh"
        case .disintegrate: return "Disintegrate"
        case .duochrome: return "Duochrome"
        case .echo: return "Echo"
        case .emboss: return "Emboss"
        case .etherealAura: return "Ethereal aura"
        case .frosted: return "Frosted"
        case .geometricWarp: return "Geometric warp"
        case .glitch: return "Glitch"
        case .gravityWells: return "Gravity wells"
        case .heatShimmer: return "Heat shimmer"
        case .holographic: return "Holographic"
        case .inkBleed: return "Ink bleed"
        case .kaleidoscope: return "Kaleidoscope"
        case .liquidChrome: return "Liquid chrome"
        case .liquidMirror: return "Liquid mirror"
        case .liveRipple: return "Live ripple"
        case .magneticField: return "Magnetic field"
        case .melt: return "Melt"
        case .morphBreathe: return "Morph breathe"
        case .neonEdge: return "Neon edge"
        case .pixelateMosaic: return "Pixelate mosaic"
        case .pixelateStorm: return "Pixelate storm"
        case .plasma: return "Plasma"
        case .pulse: return "Pulse"
        case .refractLens: return "Refract lens"
        case .shatter: return "Shatter"
        case .shatterGlass: return "Shatter glass"
        case .shockwave: return "Shockwave"
        case .smokeReveal: return "Smoke reveal"
        case .solarize: return "Solarize"
        case .thermal: return "Thermal"
        case .topographic: return "Topographic"
        case .touchRipple: return "Touch ripple"
        case .underwaterCaustics: return "Underwater caustics"
        case .vortex: return "Vortex"
        case .wavePool: return "Wave pool"
        case .wormhole: return "Wormhole"
        }
    }

    var needsTouch: Bool {
        self == .refractLens || self == .touchRipple
    }
}

struct SwiftUIShadersPlaygroundView: View {
    @State private var selected: SwiftUIShaderDemo = .holographic
    @State private var touch: UnitPoint = .center
    @State private var search = ""

    private var filtered: [SwiftUIShaderDemo] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SwiftUIShaderDemo.allCases }
        return SwiftUIShaderDemo.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(height: 280)
                .padding(.horizontal)
                .padding(.top, 12)

            if selected.needsTouch {
                Text("Drag on the preview for this effect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            Text("\(SwiftUIShaderDemo.allCases.count) shaders · \(selected.title)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List(filtered) { demo in
                Button {
                    selected = demo
                } label: {
                    HStack {
                        Text(demo.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if demo == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Filter shaders")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("SwiftUI shaders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        GeometryReader { geo in
            appliedShader(sampleCard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard selected.needsTouch, geo.size.width > 0, geo.size.height > 0 else { return }
                        touch = UnitPoint(
                            x: value.location.x / geo.size.width,
                            y: value.location.y / geo.size.height
                        )
                    }
                )
        }
    }

    @ViewBuilder
    private func appliedShader<Content: View>(_ content: Content) -> some View {
        switch selected {
        case .aurora: content.bcsAurora()
        case .blackHole: content.bcsBlackHole()
        case .chromaticSplit: content.bcsChromaticSplit()
        case .datamosh: content.bcsDatamosh()
        case .disintegrate: content.bcsDisintegrate()
        case .duochrome: content.bcsDuochrome()
        case .echo: content.bcsEcho()
        case .emboss: content.bcsEmboss()
        case .etherealAura: content.bcsEtherealAura()
        case .frosted: content.bcsFrosted()
        case .geometricWarp: content.bcsGeometricWarp()
        case .glitch: content.bcsGlitch()
        case .gravityWells: content.bcsGravityWells()
        case .heatShimmer: content.bcsHeatShimmer()
        case .holographic: content.bcsHolographic()
        case .inkBleed: content.bcsInkBleed()
        case .kaleidoscope: content.bcsKaleidoscope()
        case .liquidChrome: content.bcsLiquidChrome()
        case .liquidMirror: content.bcsLiquidMirror()
        case .liveRipple: content.bcsLiveRipple()
        case .magneticField: content.bcsMagneticField()
        case .melt: content.bcsMelt()
        case .morphBreathe: content.bcsMorphBreathe()
        case .neonEdge: content.bcsNeonEdge()
        case .pixelateMosaic: content.bcsPixelateMosaic()
        case .pixelateStorm: content.bcsPixelateStorm()
        case .plasma: content.bcsPlasma()
        case .pulse: content.bcsPulse()
        case .refractLens: content.bcsRefractLens(touchPos: touch)
        case .shatter: content.bcsShatter()
        case .shatterGlass: content.bcsShatterGlass()
        case .shockwave: content.bcsShockwave()
        case .smokeReveal: content.bcsSmokeReveal()
        case .solarize: content.bcsSolarize()
        case .thermal: content.bcsThermal()
        case .topographic: content.bcsTopographic()
        case .touchRipple: content.bcsTouchRipple(touchPos: touch)
        case .underwaterCaustics: content.bcsUnderwaterCaustics()
        case .vortex: content.bcsVortex()
        case .wavePool: content.bcsWavePool()
        case .wormhole: content.bcsWormhole()
        }
    }

    private var sampleCard: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.35, blue: 0.72),
                    Color(red: 0.55, green: 0.22, blue: 0.55),
                    Color(red: 0.12, green: 0.55, blue: 0.48),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Text("静")
                    .font(.system(size: 88, weight: .bold))
                    .foregroundStyle(.white)
                Text("Shizen · shader lab")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(selected.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(24)
        }
    }
}

final class SwiftUIShadersPlaygroundViewController: UIHostingController<SwiftUIShadersPlaygroundView> {
    convenience init() {
        self.init(rootView: SwiftUIShadersPlaygroundView())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SwiftUI shaders"
        navigationItem.largeTitleDisplayMode = .never
    }
}
