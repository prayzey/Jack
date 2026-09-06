import SwiftUI

struct FolderIconView: View {
    let folder: ClipFolderModel
    let accentColor: Color
    let textColor: Color
    var fontSize: CGFloat = 11
    var circleSize: CGFloat = 12

    var body: some View {
        if let icon = folder.effectiveFolderIcon {
            switch icon {
            case .symbol(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(folder.colorMode == .fill ? textColor : accentColor)
                    .frame(minWidth: circleSize, minHeight: circleSize)
            case .glyph(let glyph):
                Text(glyph)
                    .font(.system(size: fontSize + 1))
                    .frame(minWidth: circleSize, minHeight: circleSize)
                    .accessibilityLabel("\(folder.displayName) icon")
            }
        } else {
            Circle()
                .fill(accentColor)
                .frame(width: circleSize, height: circleSize)
        }
    }
}
