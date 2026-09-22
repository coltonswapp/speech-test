import Combine
import SwiftUI
import UIKit

struct IntroPage: View {

    static let cardWHRatio: CGFloat = 1.77

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var activeCard: LandingCard? = landingCards.first
    @State private var scrollPosition: ScrollPosition = .init()
    @State private var currentScrollOffset: CGFloat = 0
    @State private var timer = Timer.publish(every: 0.01, on: .current, in: .default).autoconnect()
    @State private var initialAnimation: Bool = false
    @State private var titleProgress: CGFloat = 0
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var showAuthButtons: Bool = false

    var onGetStarted: () -> Void
    var onAppleSignIn: () -> Void
    var onLogin: () -> Void
    var onSignUp: () -> Void
    var revealsAuthOnGetStarted: Bool

    init(
        onGetStarted: @escaping () -> Void,
        onAppleSignIn: @escaping () -> Void = {},
        onLogin: @escaping () -> Void = {},
        onSignUp: @escaping () -> Void = {},
        revealsAuthOnGetStarted: Bool = true
    ) {
        self.onGetStarted = onGetStarted
        self.onAppleSignIn = onAppleSignIn
        self.onLogin = onLogin
        self.onSignUp = onSignUp
        self.revealsAuthOnGetStarted = revealsAuthOnGetStarted
    }

    var body: some View {
        ZStack {
            AmbientBackground()
                .animation(.easeInOut(duration: 1), value: activeCard)

            VStack(spacing: contentSpacing) {
                GeometryReader { geo in
                    let size = cardSize(in: geo.size)

                    InfiniteScrollView {
                        ForEach(landingCards) { card in
                            CarouselCardView(card, cardWidth: size.width, cardHeight: size.height)
                        }
                    }
                    .frame(height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .scrollIndicators(.hidden)
                    .scrollPosition($scrollPosition)
                    .scrollClipDisabled()
                    .onScrollPhaseChange({ _, newPhase in
                        scrollPhase = newPhase
                    })
                    .onScrollGeometryChange(for: CGFloat.self) {
                        $0.contentOffset.x + $0.contentInsets.leading
                    } action: { _, newValue in
                        currentScrollOffset = newValue

                        if scrollPhase != .decelerating || scrollPhase != .animating {
                            let rawIndex = Int((currentScrollOffset / size.width).rounded())
                            let activeIndex = ((rawIndex % landingCards.count) + landingCards.count) % landingCards.count
                            activeCard = landingCards[activeIndex]
                        }
                    }
                    .visualEffect { [initialAnimation] content, proxy in
                        content
                            .offset(y: !initialAnimation ? -(proxy.size.height + 200) : 0)
                    }
                }
                .padding(.top, 16)
                .frame(maxHeight: .infinity)
                .animation(.smooth(duration: 0.6), value: showAuthButtons)

                VStack(spacing: contentSpacing) {
                    VStack(spacing: 4) {
                        Text("Welcome to")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.secondary)
                            .blurOpacityEffect(initialAnimation)

                        Text("Shizen")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .textRenderer(TitleTextRenderer(progress: titleProgress))
                            .padding(.bottom, 12)
                            .onTapGesture {
                                withAnimation(.smooth(duration: 0.6)) {
                                    showAuthButtons = false
                                }
                            }

                        Text("Learn Japanese naturally, through listening.\nThe language as it's actually spoken.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.secondary)
                            .blurOpacityEffect(initialAnimation)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !showAuthButtons {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if revealsAuthOnGetStarted {
                                withAnimation(.smooth(duration: 0.6)) {
                                    showAuthButtons = true
                                }
                            }
                            onGetStarted()
                        } label: {
                            Text("Get Started")
                                .fontWeight(.semibold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 12)
                                .background(.white, in: .capsule)
                        }
                        .blurOpacityEffect(initialAnimation)
                        .opacity(showAuthButtons ? 0 : 1)
                        .animation(.snappy(extraBounce: 1.0), value: showAuthButtons)
                        .padding(.bottom)
                    }

                    if showAuthButtons {
                        VStack(spacing: 8) {
                            Button {
                                onAppleSignIn()
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "apple.logo")
                                        .foregroundStyle(.white)
                                    Text("Continue with Apple")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .frame(height: 55)
                                .background(.black, in: .capsule)
                            }

                            Button {
                                onLogin()
                            } label: {
                                Text("Log in")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .frame(height: 55)
                                    .background(.white, in: .capsule)
                            }

                            Button {
                                onSignUp()
                            } label: {
                                Text("Sign up")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .frame(height: 55)
                                    .overlay(
                                        Capsule()
                                            .stroke(.white.opacity(0.4), lineWidth: 1.5)
                                    )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom)
                        .opacity(showAuthButtons ? 1 : 0)
                        .offset(y: showAuthButtons ? 0 : 100)
                        .animation(.snappy(extraBounce: 1.0), value: showAuthButtons)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .safeAreaPadding(15)
        }
        .onReceive(timer) { _ in
            currentScrollOffset += 0.45
            scrollPosition.scrollTo(x: currentScrollOffset)
        }
        .task {
            try? await Task.sleep(for: .seconds(0.35))

            withAnimation(.smooth(duration: 0.75, extraBounce: 0)) {
                initialAnimation = true
            }

            withAnimation(.smooth(duration: 2.5, extraBounce: 0).delay(0.3)) {
                titleProgress = 1
            }
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 16 : 40
    }

    private func cardSize(in size: CGSize) -> (width: CGFloat, height: CGFloat) {
        let height = min(max(size.height, 80), size.width * Self.cardWHRatio)
        let width = height / Self.cardWHRatio
        return (width, height)
    }

    @ViewBuilder
    private func AmbientBackground() -> some View {
        GeometryReader {
            let size = $0.size

            ZStack {
                ForEach(landingCards) { card in
                    cardArtwork(card)
                        .ignoresSafeArea()
                        .frame(width: size.width, height: size.height)
                        .opacity(activeCard?.id == card.id ? 1 : 0)
                }

                Rectangle()
                    .fill(.black.opacity(0.45))
                    .ignoresSafeArea()
            }
            .compositingGroup()
            .blur(radius: 90, opaque: true)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func CarouselCardView(_ card: LandingCard, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        GeometryReader {
            let size = $0.size

            cardArtwork(card)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 10, x: 1, y: 0)
        }
        .frame(width: cardWidth, height: cardHeight)
        .scrollTransition(.interactive.threshold(.centered), axis: .horizontal) { content, phase in
            content
                .offset(y: phase == .identity ? -10 : 0)
                .rotationEffect(.degrees(phase.value * 5), anchor: .bottom)
        }
    }

    @ViewBuilder
    private func cardArtwork(_ card: LandingCard) -> some View {
        if UIImage(named: card.image) != nil {
            Image(card.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: card.placeholderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: card.symbolName)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }
}

#Preview {
    IntroPage(
        onGetStarted: {
            print("Get Started tapped")
        },
        onAppleSignIn: {
            print("Apple Sign In tapped")
        },
        onLogin: {
            print("Login tapped")
        },
        onSignUp: {
            print("Sign Up tapped")
        }
    )
}

extension View {
    func blurOpacityEffect(_ show: Bool) -> some View {
        self
            .blur(radius: show ? 0 : 2)
            .opacity(show ? 1 : 0)
            .scaleEffect(show ? 1 : 0.9)
    }
}
