import Foundation

/// 用户自定义的剪贴板分组（Paste 风格的 Pinboard）。
public struct Pinboard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}
