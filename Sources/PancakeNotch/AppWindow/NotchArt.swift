import ModuleShelf
import NotchCore
import SwiftUI

/// The top edge of a pretend screen with a working notch in it: a sketched menu bar, a soft glow
/// behind the notch and the live `NotchPreview`, so people can try their hover settings right in
/// the window. Off, the notch dims and stops reacting.
struct NotchStage: View {
    let behavior: NotchBehavior
    var isActive = true
    /// Shows a sample Shelf inside the preview (when the Shelf is on).
    var showsShelf = false
    /// Width of the pretend screen the preview lays itself out for.
    var screenWidth: CGFloat = 560
    /// The preview is drawn a little smaller than life so the whole page fits.
    var scale: CGFloat = 0.85

    var body: some View {
        let preview = NotchPreview(behavior: behavior, screenWidth: screenWidth, module: showsShelf ? Self.sampleShelf : nil)
        let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
        ZStack(alignment: .top) {
            DotGrid()
                .mask {
                    EllipticalGradient(colors: [.black, .clear], center: .top, startRadiusFraction: 0, endRadiusFraction: 0.75)
                }
                .opacity(isActive ? 1 : 0.5)
            NotchGlow(scale: scale)
                .opacity(isActive ? 1 : 0.3)
            MenuBarSketch(height: NotchGeometry.simulatedSize.height * scale)
                .accessibilityHidden(true)
            hint
                .padding(.top, size.height * 0.52)
            preview
                .scaleEffect(scale, anchor: .top)
                .frame(width: size.width, height: size.height, alignment: .top)
                .opacity(isActive ? 1 : 0.4)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
        }
        .frame(minWidth: size.width, maxWidth: .infinity)
        .frame(height: size.height + 10, alignment: .top)
        .clipped()
    }

    /// Example items, shared by every preview (it holds nothing real).
    private static let sampleShelf = ShelfPreviewModule()

    /// Sits under the notch, so the opening panel covers it.
    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "cursorarrow.rays" : "power")
                .font(.app(size: 12, weight: .semibold))
            Text(isActive
                ? String(localized: "Hover the notch to try it. Click it to keep it small, and again to close it.")
                : String(localized: "Turn the notch on to try it here."))
                .font(.app(size: 12.5, weight: .medium))
        }
        .foregroundStyle(AppPalette.secondaryText)
        .accessibilityHidden(true)
    }
}

/// A soft white haze around the top centre, like light catching the edge of the notch. Drawn with
/// gradients rather than blurs so it looks the same in off-screen snapshots.
struct NotchGlow: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            EllipticalGradient(
                stops: [
                    .init(color: .white.opacity(0.2), location: 0),
                    .init(color: .white.opacity(0.07), location: 0.45),
                    .init(color: .white.opacity(0), location: 1),
                ],
                center: .top,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
            .frame(width: 640 * scale, height: 340 * scale)
            EllipticalGradient(
                colors: [.white.opacity(0.22), .white.opacity(0)],
                center: .top,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
            .frame(width: 340 * scale, height: 120 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A faint grid of dots, the stage's "wallpaper".
private struct DotGrid: View {
    var spacing: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = (size.width.truncatingRemainder(dividingBy: spacing)) / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(.white.opacity(0.16)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Placeholder menus on the left and status icons on the right, so the stage reads as a screen.
private struct MenuBarSketch: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.app(size: 9))
            ForEach(Array([34, 26, 30, 24].enumerated()), id: \.offset) { _, width in
                Capsule().frame(width: CGFloat(width), height: 5)
            }
            Spacer()
            ForEach(Array([11, 11, 11].enumerated()), id: \.offset) { _, width in
                RoundedRectangle(cornerRadius: 2.5).frame(width: CGFloat(width), height: 9)
            }
            Capsule().frame(width: 44, height: 5)
        }
        .foregroundStyle(.white.opacity(0.16))
        .padding(.horizontal, 20)
        .frame(height: height)
    }
}

/// The app's logo mark (`LogoGlyph`), shown beside its name in the sidebar.
struct NotchGlyph: View {
    var size: CGFloat = 24

    var body: some View {
        LogoGlyph()
            .fill(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A black notch panel the way it looks when open: ears flaring out at the top, rounded below.
struct NotchPanelShape: View {
    var body: some View {
        NotchShape(topRadius: 12, bottomRadius: 22)
            .fill(.black)
            .overlay {
                NotchShape(topRadius: 12, bottomRadius: 22)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
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
