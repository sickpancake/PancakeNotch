import CoreGraphics
import Foundation
import NotchCore

/// Where things sit in the open Now Playing panel (origin top-left, y down): the artwork on the left
/// under the top band, the song, the progress bar and the controls in a column beside it.
struct NowPlayingLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 16
    static let columnGap: CGFloat = 18

    let body: CGSize
    /// Height of the band beside the hardware notch.
    let bandHeight: CGFloat
    /// Width of the hardware notch; nothing may sit under it.
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    /// Room under the band for the artwork and the column.
    var contentTop: CGFloat { bandHeight + 8 }

    var artworkSize: CGFloat {
        max(64, min(112, body.height - contentTop - Self.bottomPadding))
    }

    /// The column beside the artwork.
    var columnWidth: CGFloat {
        max(160, body.width - 2 * Self.sidePadding - artworkSize - Self.columnGap)
    }

    /// Width of each half of the band beside the notch.
    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
}

/// "3:07", "1:02:45", "-0:42".
enum NowPlayingTime {
    static func format(_ seconds: TimeInterval, negative: Bool = false) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        let text = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
        return negative ? "-" + text : text
    }

    /// For VoiceOver: "2 minutes 5 seconds".
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
