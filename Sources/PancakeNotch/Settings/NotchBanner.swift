import NotchCore
import SwiftUI

/// The top of a MacBook screen with the notch open, showing the app's name and version: the
/// window's small nod to what the app does. Only the text is read by VoiceOver.
struct NotchBanner: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Self.screenTop, Self.screenBottom], startPoint: .top, endPoint: .bottom)
            MenuBarSketch()
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text("PancakeNotch")
                    .font(.title3.weight(.semibold))
                Text(AppInfo.version)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background {
                // The ears flare out beyond the body, like the real notch.
                NotchShape(topRadius: 12, bottomRadius: 24)
                    .fill(.black)
                    .padding(.horizontal, -12)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(SettingsPalette.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private static let screenTop = SettingsPalette.adaptive(light: NSColor(white: 0.9, alpha: 1), dark: NSColor(white: 0.23, alpha: 1))
    private static let screenBottom = SettingsPalette.adaptive(light: NSColor(white: 0.965, alpha: 1), dark: NSColor(white: 0.15, alpha: 1))
}

/// Placeholder menus on the left and status icons on the right, so the banner reads as a screen.
private struct MenuBarSketch: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([14, 36, 28, 34, 26], id: \.self) { width in
                Capsule().frame(width: CGFloat(width), height: 6)
            }
            Spacer()
            ForEach([12, 12, 12, 40], id: \.self) { width in
                Capsule().frame(width: CGFloat(width), height: 6)
            }
        }
        .foregroundStyle(.primary.opacity(0.14))
        .padding(.horizontal, 16)
        .frame(height: 26)
    }
}

/// A tiny screen with a notch, shown beside the app's name in the sidebar.
struct NotchGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(.primary, lineWidth: 1.5)
            .overlay(alignment: .top) {
                NotchShape(topRadius: 1.5, bottomRadius: 2.5)
                    .fill(.primary)
                    .frame(width: 10, height: 4.5)
                    .padding(.top, 1)
            }
            .frame(width: 22, height: 16)
            .accessibilityHidden(true)
    }
}

/// The app's name and version, as shown in the window.
enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else {
            return String(localized: "Development build")
        }
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return String(localized: "Version \(short) (\(build))")
    }

    static let sourceCode = URL(string: "https://github.com/sickpancake/PancakeNotch")!
    static let license = URL(string: "https://github.com/sickpancake/PancakeNotch/blob/main/LICENSE")!
}
