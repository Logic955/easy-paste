import Foundation

public enum ClipboardKind: String, CaseIterable, Codable, Equatable, Sendable {
    case text
    case url
    case json
    case xml
    case yaml
    case sql
    case markdown
    case code
    case image

    public var displayName: String {
        switch self {
        case .text:
            return "文本"
        case .url:
            return "链接"
        case .json:
            return "JSON"
        case .xml:
            return "XML"
        case .yaml:
            return "YAML"
        case .sql:
            return "SQL"
        case .markdown:
            return "Markdown"
        case .code:
            return "代码"
        case .image:
            return "图片"
        }
    }
}

public enum ClipboardTransform: String, CaseIterable, Codable, Equatable, Sendable {
    case original
    case json
    case xml
    case yaml
    case sql
    case markdown
    case plain

    public var displayName: String {
        switch self {
        case .original:
            return "原始内容"
        case .json:
            return "格式化 JSON"
        case .xml:
            return "格式化 XML"
        case .yaml:
            return "整理 YAML"
        case .sql:
            return "格式化 SQL"
        case .markdown:
            return "整理 Markdown"
        case .plain:
            return "纯文本"
        }
    }
}

/// 选择哪个 pinboard 的视图：内置 All / Pinned，或某个用户创建的 pinboard。
public enum BoardSelector: Equatable, Hashable, Sendable {
    case all
    case pinned
    case board(UUID)
}

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ClipboardKind
    public var title: String
    public var preview: String
    public var sourceApp: String
    public var sourceBundleID: String?
    public var text: String?
    public var rtfDataBase64: String?
    public var htmlDataBase64: String?
    public var imagePNGBase64: String?
    public var rtfBlobPath: String?
    public var htmlBlobPath: String?
    public var imageBlobPath: String?
    public var rtfByteCount: Int?
    public var htmlByteCount: Int?
    public var imageByteCount: Int?
    /// 图片来源（Finder 拷贝图片文件时取文件名 + 父目录），用于搜索。
    public var imageName: String?
    /// 通过 Vision OCR 从图片识别出的文本（中英文），用于搜索。
    public var ocrText: String?
    public var pinned: Bool
    public var boardIDs: Set<UUID>
    public var createdAt: Date
    public var updatedAt: Date
    public var hash: String

    public init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        title: String,
        preview: String,
        sourceApp: String,
        sourceBundleID: String? = nil,
        text: String? = nil,
        rtfDataBase64: String? = nil,
        htmlDataBase64: String? = nil,
        imagePNGBase64: String? = nil,
        rtfBlobPath: String? = nil,
        htmlBlobPath: String? = nil,
        imageBlobPath: String? = nil,
        rtfByteCount: Int? = nil,
        htmlByteCount: Int? = nil,
        imageByteCount: Int? = nil,
        imageName: String? = nil,
        ocrText: String? = nil,
        pinned: Bool = false,
        boardIDs: Set<UUID> = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        hash: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.text = text
        self.rtfDataBase64 = rtfDataBase64
        self.htmlDataBase64 = htmlDataBase64
        self.imagePNGBase64 = imagePNGBase64
        self.rtfBlobPath = rtfBlobPath
        self.htmlBlobPath = htmlBlobPath
        self.imageBlobPath = imageBlobPath
        self.rtfByteCount = rtfByteCount
        self.htmlByteCount = htmlByteCount
        self.imageByteCount = imageByteCount
        self.imageName = imageName
        self.ocrText = ocrText
        self.pinned = pinned
        self.boardIDs = boardIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hash = hash
    }

    // 自定义 decoder：兼容旧版本持久化数据（没有 imageName / ocrText 字段时不报错）。
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, preview, sourceApp, sourceBundleID, text
        case rtfDataBase64, htmlDataBase64
        case imagePNGBase64, rtfBlobPath, htmlBlobPath, imageBlobPath
        case rtfByteCount, htmlByteCount, imageByteCount
        case imageName, ocrText, pinned, boardIDs
        case createdAt, updatedAt, hash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.kind = try c.decode(ClipboardKind.self, forKey: .kind)
        self.title = try c.decode(String.self, forKey: .title)
        self.preview = try c.decode(String.self, forKey: .preview)
        self.sourceApp = try c.decode(String.self, forKey: .sourceApp)
        self.sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.rtfDataBase64 = try c.decodeIfPresent(String.self, forKey: .rtfDataBase64)
        self.htmlDataBase64 = try c.decodeIfPresent(String.self, forKey: .htmlDataBase64)
        self.imagePNGBase64 = try c.decodeIfPresent(String.self, forKey: .imagePNGBase64)
        self.rtfBlobPath = try c.decodeIfPresent(String.self, forKey: .rtfBlobPath)
        self.htmlBlobPath = try c.decodeIfPresent(String.self, forKey: .htmlBlobPath)
        self.imageBlobPath = try c.decodeIfPresent(String.self, forKey: .imageBlobPath)
        self.rtfByteCount = try c.decodeIfPresent(Int.self, forKey: .rtfByteCount)
        self.htmlByteCount = try c.decodeIfPresent(Int.self, forKey: .htmlByteCount)
        self.imageByteCount = try c.decodeIfPresent(Int.self, forKey: .imageByteCount)
        self.imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
        self.ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        self.pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.boardIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .boardIDs) ?? []
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.hash = try c.decode(String.self, forKey: .hash)
    }
}
