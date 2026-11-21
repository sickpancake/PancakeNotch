import SwiftUI

extension Font {
    /// The app window's typeface: SF Pro Rounded, soft and friendly like the notch's curves.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
