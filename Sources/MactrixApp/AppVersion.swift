import Foundation

struct AppVersion {
  let displayVersion: String
  let build: String

  init(info: [String: Any]) {
    let version = info["CFBundleShortVersionString"] as? String
    let commit = info["MactrixGitCommit"] as? String
    let label = version.flatMap { $0.isEmpty ? nil : $0 } ?? "Development"
    if let commit, !commit.isEmpty, !commit.contains("$(") {
      let shortCommit = commit == "local" ? commit : String(commit.prefix(7))
      displayVersion = "\(label) (\(shortCommit))"
    } else {
      displayVersion = label
    }
    build = info["CFBundleVersion"] as? String ?? ""
  }
}
