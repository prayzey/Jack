import AppKit
import Foundation

enum AppAttribution {
    static let copyright = "Copyright © 2025-2026 Praise Adesokan. All rights reserved."

    static let lilAgentsName = "Lil Agents"
    static let lilAgentsRepositoryURL = "https://github.com/ryanstephen/lil-agents"
    static let lilAgentsCopyright = "Copyright (c) 2026 Ryan Stephen"
    static let lilAgentsLicenseName = "MIT License"

    static let lilAgentsMITLicenseText = """
    MIT License

    Copyright (c) 2026 Ryan Stephen

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    static let openSourceCreditsText = """
    Open Source Acknowledgements

    Jack includes work derived from:

    \(lilAgentsName)
    \(lilAgentsCopyright)
    Licensed under the \(lilAgentsLicenseName)
    \(lilAgentsRepositoryURL)

    \(lilAgentsMITLicenseText)
    """

    @MainActor
    static var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: AppBrand.displayName,
            .applicationVersion: AppVersionInfo.current.settingsLabel,
            .credits: creditsAttributedString
        ]
    }

    @MainActor
    private static var creditsAttributedString: NSAttributedString {
        NSAttributedString(
            string: openSourceCreditsText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
