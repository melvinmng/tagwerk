import SwiftUI

/// The colour of the bolt that marks a habit as automatic (design GW3b). One named colour with a light and a dark value in
/// `Design/Colors.xcassets`; `HabitMarkerTintTests` holds both to 3:1 against the list backgrounds, because the bolt and the
/// progress ring are graphic objects (WCAG 1.4.11). The green check keeps meaning "done".
enum HabitMarkerTint {
    static let assetName = "HabitAutomaticMarker"

    static var automatic: Color { Color(assetName) }
}
