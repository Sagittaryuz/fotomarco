import Foundation

struct CloudArchiveFilename {
    let captureID: UUID
    let capturedAt: Date?
    let profile: CaptureProfileTag?
    let isOriginal: Bool

    static func make(captureID: UUID, capturedAt: Date, profile: CaptureProfileTag?,
                     originalExtension: String?) -> String {
        let suffix = originalExtension.map { "-original." + $0 } ?? "-stamped.jpg"
        let seconds = Int64(capturedAt.timeIntervalSince1970.rounded(.down))
        var identifier = "\(captureID.uuidString).\(seconds)"
        if let profile {
            var label = String(profile.name.prefix(60))
            while label.utf8.count > 36 { label.removeLast() }
            let encoded = Data(label.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            identifier += ".\(profile.id.uuidString).\(encoded)"
        }
        return identifier + suffix
    }

    init?(_ name: String) {
        guard name.utf8.count <= 160, let captureID = UUID(uuidString: String(name.prefix(36))),
              let separator = name.range(of: "-original.", options: .backwards)
                ?? name.range(of: "-stamped.", options: .backwards) else { return nil }
        let extensionPart = name[separator.upperBound...].lowercased()
        let isOriginal = name[separator] == "-original."
        let validExtension = (1...12).contains(extensionPart.utf8.count) &&
            extensionPart.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
        guard (isOriginal ? validExtension : extensionPart == "jpg"),
              separator.lowerBound >= name.index(name.startIndex, offsetBy: 36) else { return nil }
        let middle = name[name.index(name.startIndex, offsetBy: 36)..<separator.lowerBound]
        self.captureID = captureID
        self.isOriginal = isOriginal
        if middle.isEmpty {
            capturedAt = nil
            profile = nil
            return
        }
        let parts = middle.split(separator: ".", omittingEmptySubsequences: false)
        guard (parts.count == 2 || parts.count == 4), parts[0].isEmpty,
              let seconds = Int64(parts[1]), (0...253_402_300_799).contains(seconds) else { return nil }
        capturedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
        if parts.count == 4 {
            guard let profileID = UUID(uuidString: String(parts[2])), parts[3].utf8.count <= 48 else { return nil }
            var encoded = parts[3].replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let bytes = Data(base64Encoded: encoded), let label = String(data: bytes, encoding: .utf8) else { return nil }
            profile = CaptureProfileTag(id: profileID, name: label)
        } else {
            profile = nil
        }
    }
}
