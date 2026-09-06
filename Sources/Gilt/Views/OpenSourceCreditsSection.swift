import AppKit
import SwiftUI

/// Attribution panel for the Settings → License tab. Lists every third-party
/// AI model and library Jack ships with, alongside its license and source URL.
/// Required to satisfy CC-BY-4.0 (Parakeet), MIT (Whisper et al.), and
/// Apache 2.0 (Qwen, FluidAudio) attribution clauses.
struct OpenSourceCreditsSection: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let author: String
        let license: String
        let purpose: String
        let url: String
    }

    private let aiModels: [Entry] = [
        Entry(
            name: "Qwen 3.5 4B",
            author: "Alibaba, Qwen Team",
            license: "Apache 2.0",
            purpose: "Local large language model powering dictation polish and meeting summaries.",
            url: "https://huggingface.co/Qwen/Qwen3.5-4B"
        ),
        Entry(
            name: "Whisper (Small & Medium Multilingual)",
            author: "OpenAI",
            license: "MIT",
            purpose: "Multilingual speech recognition used as a meeting-transcription fallback.",
            url: "https://github.com/openai/whisper"
        ),
        Entry(
            name: "Parakeet TDT 0.6B",
            author: "NVIDIA",
            license: "CC-BY-4.0",
            purpose: "Low-latency on-device speech recognition for live dictation.",
            url: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"
        ),
        Entry(
            name: "Silero VAD",
            author: "Silero Team",
            license: "MIT",
            purpose: "Voice activity detection. Trims silence from audio captures.",
            url: "https://github.com/snakers4/silero-vad"
        )
    ]

    var body: some View {
        SettingsSection(L10n.string("ui.open.source.credits", default: "Open Source Credits")) {
            VStack(alignment: .leading, spacing: 0) {
                categoryLabel(L10n.string("ui.ai.models", default: "AI Models"))
                entryList(aiModels)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func categoryLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(SettingsTheme.textTertiary)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func entryList(_ entries: [Entry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                creditRow(entry)
                if index < entries.count - 1 {
                    Rectangle()
                        .fill(SettingsTheme.divider)
                        .frame(height: 0.5)
                        .padding(.leading, 18)
                }
            }
        }
    }

    @ViewBuilder
    private func creditRow(_ entry: Entry) -> some View {
        Button {
            if let url = URL(string: entry.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                    .lineLimit(1)
                Text(entry.author)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                licenseBadge(entry.license)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.purpose)
    }

    private func licenseBadge(_ license: String) -> some View {
        Text(license)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(SettingsTheme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(SettingsTheme.sidebarBackground)
            )
            .overlay(
                Capsule().strokeBorder(SettingsTheme.border, lineWidth: 0.5)
            )
    }
}
