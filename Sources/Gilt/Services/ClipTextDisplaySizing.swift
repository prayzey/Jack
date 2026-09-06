import CoreGraphics

/// Font size for a plain-text clip body. Short snippets grow to fill a tall
/// card instead of sitting as a 13pt line in a sea of dark grey; long text
/// stays at the base size so it keeps wrapping normally.
func clipTextDisplayFontSize(
    characterCount: Int,
    availableWidth: CGFloat,
    availableHeight: CGFloat,
    baseSize: CGFloat = 13,
    maxSize: CGFloat = 24
) -> CGFloat {
    guard characterCount > 0, availableWidth > 0, availableHeight > 0 else { return baseSize }
    // ponytail: average glyph ~0.55em wide, line ~1.35em tall; aim to fill
    // about 30% of the body so wrapped text still has breathing room.
    let glyphArea: CGFloat = 0.55 * 1.35
    let fitted = (0.3 * availableWidth * availableHeight / (glyphArea * CGFloat(characterCount))).squareRoot()
    return min(maxSize, max(baseSize, fitted.rounded()))
}
