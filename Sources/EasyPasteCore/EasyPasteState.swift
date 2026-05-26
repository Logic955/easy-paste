import Foundation

/// 单文件持久化的全局状态。包含剪贴板历史 + 用户 pinboard 列表 + 当前选中的 board。
public struct EasyPasteState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var items: [ClipboardItem]
    public var pinboards: [Pinboard]
    public var activeBoardSelector: BoardSelectorRaw
    public var preferences: EasyPastePreferences

    public init(
        schemaVersion: Int = 1,
        items: [ClipboardItem] = [],
        pinboards: [Pinboard] = [],
        activeBoardSelector: BoardSelectorRaw = .all,
        preferences: EasyPastePreferences = EasyPastePreferences()
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.pinboards = pinboards
        self.activeBoardSelector = activeBoardSelector
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, items, pinboards, activeBoardSelector, preferences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        items = try c.decodeIfPresent([ClipboardItem].self, forKey: .items) ?? []
        pinboards = try c.decodeIfPresent([Pinboard].self, forKey: .pinboards) ?? []
        activeBoardSelector = try c.decodeIfPresent(BoardSelectorRaw.self, forKey: .activeBoardSelector) ?? .all
        preferences = try c.decodeIfPresent(EasyPastePreferences.self, forKey: .preferences) ?? EasyPastePreferences()
    }
}

/// `BoardSelector` 不直接 Codable（含关联值），用这个等价的 Codable 表示存盘。
public enum BoardSelectorRaw: Codable, Equatable, Hashable, Sendable {
    case all
    case pinned
    case board(UUID)

    public init(_ selector: BoardSelector) {
        switch selector {
        case .all:
            self = .all
        case .pinned:
            self = .pinned
        case .board(let id):
            self = .board(id)
        }
    }

    public var selector: BoardSelector {
        switch self {
        case .all:
            return .all
        case .pinned:
            return .pinned
        case .board(let id):
            return .board(id)
        }
    }
}
