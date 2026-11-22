import SwiftUI

/// Text colours that keep the audit's contrast on the app's backgrounds, cards and tinted cards (strand K, plan g3-system-anbindungen).
/// The values live in the colour catalog `Design/Colors.xcassets`; `TextTonesTests` measures every pair. Fills, bars, dots and symbols
/// keep the system colours: only text and the symbols that sit in a text line use these tones.
extension ShapeStyle where Self == Color {
    /// Secondary text (captions, counts, section headers, values): the system grey is darker in the light appearance (78 %, KO1a).
    static var secondaryText: Color { Color("TextSecondary") }
    /// Time line of an entry in the hour grid, on the tinted event colour (85 %, KO3a).
    static var gridTimeText: Color { Color("TextGridTime") }
    /// Red text (overdue, deadlines, errors): darker in the light appearance, lighter in the dark one (KO2a).
    static var redText: Color { Color("TextRed") }
    /// Orange text (warnings, "knapp").
    static var orangeText: Color { Color("TextOrange") }
    /// Purple text (assistant, suggestions).
    static var purpleText: Color { Color("TextPurple") }
    /// Green text (done, free).
    static var greenText: Color { Color("TextGreen") }
}
