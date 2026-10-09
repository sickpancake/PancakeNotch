import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        PageScroll {
            VStack(spacing: 0) {
                AppIcon()
                    .frame(width: 104, height: 104)
                    .background {
                        EllipticalGradient(colors: [.white.opacity(0.16), .white.opacity(0)])
                            .frame(width: 320, height: 220)
                    }
                    .accessibilityHidden(true)
                Text("PancakeNotch")
                    .font(.system(size: 30, weight: .bold))
                    .kerning(-0.4)
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                Text(AppInfo.version)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
                    .padding(.top, 4)
                Text("A free, open-source app that puts your MacBook's notch to work.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 36)

            SettingsCard {
                SettingsRow(
                    title: String(localized: "Source code"),
                    subtitle: String(localized: "Follow along, report a bug or help out on GitHub.")
                ) {
                    Button { openURL(AppInfo.sourceCode) } label: {
                        Label(String(localized: "View on GitHub"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
                SettingsRow(
                    title: String(localized: "Your data stays here"),
                    subtitle: String(localized: "The numbers on Home are counted on this Mac and never sent anywhere.")
                ) {
                    Image(systemName: "lock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .accessibilityHidden(true)
                }
                SettingsRow(
                    title: String(localized: "License"),
                    subtitle: String(localized: "Free and open source under the GPL-3.0 license.")
                ) {
                    Button { openURL(AppInfo.license) } label: {
                        Label(String(localized: "Read License"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
            }
        }
    }
}

/// The app's icon. Unbundled development builds have only a generic icon, so they show the
/// notch glyph instead.
private struct AppIcon: View {
    var body: some View {
        if Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), .black], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                }
                .overlay { NotchGlyph(size: 52) }
                .padding(8)
        }
    }
}
