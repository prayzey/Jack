import Foundation

enum AppResourceLocator {
    static func resourceBundle(
        bundleName: String = AppBrand.resourceBundleName,
        mainBundleURL: URL = Bundle.main.bundleURL,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL
    ) -> Bundle {
        for bundleURL in bundleURLCandidates(
            bundleName: bundleName,
            mainBundleURL: mainBundleURL,
            mainResourceURL: mainResourceURL,
            executableURL: executableURL
        ) {
            if let bundle = Bundle(path: bundleURL.path) {
                return bundle
            }
        }

        if let developmentBundle = developmentResourceBundle(bundleName: bundleName) {
            return developmentBundle
        }

        return .main
    }

    static func bundleURLCandidates(
        bundleName: String,
        mainBundleURL: URL,
        mainResourceURL: URL?,
        executableURL: URL?
    ) -> [URL] {
        var candidates = [mainBundleURL.appendingPathComponent(bundleName)]

        if let mainResourceURL {
            candidates.append(mainResourceURL.appendingPathComponent(bundleName))
        }

        if let executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            candidates.append(executableDirectory.appendingPathComponent(bundleName))
        }

        return candidates
    }

    static func url(
        forResource name: String,
        withExtension ext: String,
        subdirectory: String? = nil
    ) -> URL? {
        let resourceBundle = resourceBundle()
        if let bundled = resourceBundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return bundled
        }

        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let filename = ext.isEmpty ? name : "\(name).\(ext)"

        let candidates: [URL]
        if let subdirectory, !subdirectory.isEmpty {
            candidates = [
                resourceURL.appendingPathComponent(subdirectory).appendingPathComponent(filename),
                resourceURL.appendingPathComponent(filename)
            ]
        } else {
            candidates = [resourceURL.appendingPathComponent(filename)]
        }

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static func developmentResourceBundle(bundleName: String) -> Bundle? {
        let buildDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: buildDirectory.path),
              let enumerator = FileManager.default.enumerator(
                at: buildDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else {
            return nil
        }

        // AI note:
        // `.build` can contain multiple copies of Gilt_Gilt.bundle (debug + index-build).
        // Taking the first match is wrong — index-build often lags behind the real build,
        // so new Localizable.strings keys resolve to English defaults in tests and `swift run`.
        // Prefer non-index-build paths, then the most recently modified bundle.
        var candidates: [(url: URL, isIndexBuild: Bool, modified: Date)] = []
        for case let candidate as URL in enumerator where candidate.lastPathComponent == bundleName {
            let values = try? candidate.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let isIndexBuild = candidate.pathComponents.contains("index-build")
            candidates.append((candidate, isIndexBuild, modified))
        }

        let preferred = candidates
            .sorted { lhs, rhs in
                if lhs.isIndexBuild != rhs.isIndexBuild {
                    return !lhs.isIndexBuild && rhs.isIndexBuild
                }
                return lhs.modified > rhs.modified
            }
            .first

        guard let preferred, let bundle = Bundle(path: preferred.url.path) else {
            return nil
        }
        return bundle
    }
}
