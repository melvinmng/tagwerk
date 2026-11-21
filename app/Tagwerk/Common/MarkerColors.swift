import SwiftUI

/// Colours of markers that carry text on a filled shape and must keep 4.5:1 in both appearances (PL1b, PL10b).
/// The values live in the colour catalog `Design/Colors.xcassets`; the contrast is checked by `MarkerColorsTests`
/// and `MarkerRenderContrastTests`.
extension ShapeStyle where Self == Color {
    /// Fill of the time capsule and the line of the "now" marker.
    static var nowMarkerFill: Color { Color("NowMarkerFill") }
    /// Text on `nowMarkerFill`.
    static var onNowMarker: Color { Color("OnNowMarker") }
    /// Fill of the "too early" capsule of a travel segment.
    static var travelWarningFill: Color { Color("TravelWarningFill") }
    /// Text on `travelWarningFill`.
    static var onTravelWarning: Color { Color("OnTravelWarning") }
}
