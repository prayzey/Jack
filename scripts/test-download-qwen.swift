#!/usr/bin/env swift
// Standalone harness that exercises LLM.swift against the unsloth Qwen3-4B-GGUF
// repo so we can confirm the download wiring actually works before relying on
// the in-app code path. Run with:
//   swift scripts/test-download-qwen.swift
//
// (Or via `swift` directly with package context — see the README block above.)
import Foundation

let modelID = "unsloth/Qwen3-4B-GGUF"
let url = URL(string: "https://huggingface.co/\(modelID)/tree/main")!
print("Fetching HF tree page: \(url)")
let (data, response) = try await URLSession.shared.data(from: url)
guard let http = response as? HTTPURLResponse else {
    print("Bad response"); exit(1)
}
print("HTTP \(http.statusCode), \(data.count) bytes")
guard let html = String(data: data, encoding: .utf8) else { exit(1) }
let regex = try NSRegularExpression(pattern: #"(?<=href=").*\.gguf\?download=true"#)
let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
print("Found \(matches.count) GGUF candidates")
for (i, m) in matches.prefix(20).enumerated() {
    guard let range = Range(m.range, in: html) else { continue }
    print("  [\(i)] \(html[range])")
}

let q4Filter = try NSRegularExpression(pattern: "(?i)Q4_K_M")
let q4 = matches.compactMap { m -> String? in
    guard let r = Range(m.range, in: html) else { return nil }
    let s = String(html[r])
    return q4Filter.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil ? s : nil
}
print("\nQ4_K_M filtered: \(q4.count)")
for s in q4 { print("  https://huggingface.co\(s)") }
