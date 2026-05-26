import CryptoKit
import Foundation

public enum ClipboardHasher {
    public static func hash(_ value: String) -> String {
        hash(Data(value.utf8))
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
