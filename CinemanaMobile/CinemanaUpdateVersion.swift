import Foundation

/// App Store / sideload bundle build numbers are monotonic even when the
/// marketing version is reset (for example v2.0.2 -> v1.0).
enum CinemanaUpdateVersion {
    static func isNewer(installedBuild: String, publishedBuild: String) -> Bool {
        guard let installed = Int(installedBuild), let published = Int(publishedBuild),
              installed >= 0, published >= 0 else { return false }
        return published > installed
    }

    static func supports(minimumOS: String, systemOS: OperatingSystemVersion) -> Bool {
        let parts = minimumOS.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]) else { return false }
        let minor = parts.count > 1 ? Int(parts[1]) : 0
        let patch = parts.count > 2 ? Int(parts[2]) : 0
        guard let minor, let patch else { return false }
        let required = [major, minor, patch]
        let current = [systemOS.majorVersion, systemOS.minorVersion, systemOS.patchVersion]
        return !current.lexicographicallyPrecedes(required)
    }
}
