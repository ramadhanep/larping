import SwiftUI

/// Animated splash — the brief branded screen over the app at launch. The
/// `LogoHorizontal` wordmark tints white in dark mode / black in light mode
/// (`colorScheme`-driven), so it always reads against the `Canvas` backdrop.
/// The static pre-SwiftUI launch screen is just the `Canvas` background
/// (`UILaunchScreen` in `Info.plist`), making the handoff seamless.
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.canvas
            .ignoresSafeArea()
            .overlay {
                Image("LogoHorizontal")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            }
    }
}