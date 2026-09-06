import Foundation
import SwiftUI

/// Formatting helpers shared across every meeting view.
enum MeetingFormatters {
    static func shortDuration(_ seconds: Double) -> String? {
        guard seconds > 1 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let leftover = minutes % 60
        return leftover > 0 ? "\(hours)h \(leftover)m" : "\(hours)h"
    }

    static func timer(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hh = total / 3600
        let mm = (total % 3600) / 60
        let ss = total % 60
        if hh > 0 {
            return String(format: "%d:%02d:%02d", hh, mm, ss)
        }
        return String(format: "%02d:%02d", mm, ss)
    }

    static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Single neutral row that renders one transcript chunk. Used by the live tab
/// and the full transcript tab so they stay visually identical.
struct MeetingChunkRow: View {
    let chunk: MeetingTranscriptChunk

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(chunk.formattedTimestamp)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 56, alignment: .leading)

            Text(chunk.text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

/// The accent color used across the meetings surface. Matches the workspace's
/// gold and the audio clip-type orange (for live-recording state) so meetings
/// inherit the existing design system instead of inventing a new one.
enum MeetingAccent {
    static let gold = Color(red: 0.83, green: 0.66, blue: 0.26)
    /// Same as `ClipType.audio` accent — meetings are voice content, so we
    /// reuse the audio identity rather than minting a new purple.
    static let recording = Color(red: 0.96, green: 0.58, blue: 0.28)
}
