import Foundation
import Testing

@testable import EasyPasteCore

@MainActor
private func makeSQLiteStore() -> ClipboardStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    return ClipboardStore(fileURL: dir.appendingPathComponent("state.json"))
}

@Test @MainActor func legacyJSONMigratesPayloadsToSQLiteAndBlobs() throws {
    let store = makeSQLiteStore()
    let imageData = Data([137, 80, 78, 71, 1, 2, 3, 4])
    let rtfData = Data("{\\rtf1 hello}".utf8)
    let boardID = UUID()
    let itemID = UUID()
    let item = ClipboardItem(
        id: itemID,
        kind: .image,
        title: "Image",
        preview: "2 x 2",
        sourceApp: "Tests",
        rtfDataBase64: rtfData.base64EncodedString(),
        imagePNGBase64: imageData.base64EncodedString(),
        pinned: true,
        boardIDs: [boardID],
        hash: "image-hash"
    )
    let state = EasyPasteState(
        items: [item],
        pinboards: [Pinboard(id: boardID, name: "Board", sortIndex: 0)],
        preferences: EasyPastePreferences(soundEffects: true)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try FileManager.default.createDirectory(
        at: store.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try encoder.encode(state).write(to: store.fileURL)

    try store.load()

    #expect(FileManager.default.fileExists(atPath: store.databaseURL.path))
    #expect(FileManager.default.fileExists(atPath: store.blobsDirectoryURL.path))
    #expect(store.items.count == 1)
    #expect(store.pinboards.count == 1)
    #expect(store.preferences.soundEffects)

    let reloaded = ClipboardStore(fileURL: store.fileURL)
    try reloaded.load()
    let migrated = try #require(reloaded.items.first)
    #expect(migrated.id == itemID)
    #expect(migrated.imagePNGBase64 == nil)
    #expect(migrated.rtfDataBase64 == nil)
    #expect(migrated.imageBlobPath != nil)
    #expect(migrated.rtfBlobPath != nil)
    #expect(migrated.imageByteCount == imageData.count)
    #expect(migrated.rtfByteCount == rtfData.count)
    #expect(migrated.boardIDs == [boardID])
    #expect(migrated.pinned)
    #expect(FileManager.default.fileExists(atPath: reloaded.fileURL.deletingLastPathComponent().appendingPathComponent(migrated.imageBlobPath!).path))
}

@Test @MainActor func richTextPayloadPersistsAsBlobOnReload() throws {
    let store = makeSQLiteStore()
    let html = Data("<b>Hello</b>".utf8)
    let rtf = Data("{\\rtf1\\b Hello}".utf8)
    try store.upsert(ClipboardItem(
        kind: .text,
        title: "Rich",
        preview: "Hello",
        sourceApp: "Browser",
        text: "Hello",
        rtfDataBase64: rtf.base64EncodedString(),
        htmlDataBase64: html.base64EncodedString(),
        hash: "rich"
    ))

    let reloaded = ClipboardStore(fileURL: store.fileURL)
    try reloaded.load()
    let item = try #require(reloaded.items.first)
    #expect(item.rtfDataBase64 == nil)
    #expect(item.htmlDataBase64 == nil)
    #expect(item.rtfBlobPath != nil)
    #expect(item.htmlBlobPath != nil)
    #expect(item.rtfByteCount == rtf.count)
    #expect(item.htmlByteCount == html.count)
}

@Test @MainActor func savingReloadedBlobItemKeepsExistingPayloadFile() throws {
    let store = makeSQLiteStore()
    let imageData = Data([9, 8, 7, 6, 5])
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "Image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: imageData.base64EncodedString(),
        hash: "image"
    ))

    let reloaded = ClipboardStore(fileURL: store.fileURL)
    try reloaded.load()
    let item = try #require(reloaded.items.first)
    let path = try #require(item.imageBlobPath)
    let blobURL = reloaded.fileURL.deletingLastPathComponent().appendingPathComponent(path)
    #expect(try Data(contentsOf: blobURL) == imageData)

    try reloaded.updatePreferences { $0.soundEffects.toggle() }

    #expect(blobFileCount(in: reloaded.blobsDirectoryURL) == 1)
    #expect(try Data(contentsOf: blobURL) == imageData)
}

@Test @MainActor func ocrUpdateDoesNotChangeOrderingOrDuplicateItems() throws {
    let store = makeSQLiteStore()
    let older = Date().addingTimeInterval(-60)
    let newer = Date()
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "Old image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: Data([1]).base64EncodedString(),
        updatedAt: older,
        hash: "old"
    ))
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "New image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: Data([2]).base64EncodedString(),
        updatedAt: newer,
        hash: "new"
    ))

    try store.updateOCR(hash: "old", ocrText: "recognized")

    #expect(store.items.map(\.hash) == ["new", "old"])
    #expect(store.items.count == 2)
    #expect(store.items.first(where: { $0.hash == "old" })?.ocrText == "recognized")
    #expect(store.items.first(where: { $0.hash == "old" })?.updatedAt == older)
}

@Test @MainActor func clearHistoryRemovesPersistedBlobFiles() throws {
    let store = makeSQLiteStore()
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "Image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: Data([1, 2, 3, 4]).base64EncodedString(),
        hash: "image"
    ))
    #expect(blobFileCount(in: store.blobsDirectoryURL) > 0)

    try store.clearHistory()

    #expect(store.items.isEmpty)
    #expect(blobFileCount(in: store.blobsDirectoryURL) == 0)
}

@Test @MainActor func historyRetentionRemovesExpiredBlobFiles() throws {
    let store = makeSQLiteStore()
    let old = Date().addingTimeInterval(-9 * 24 * 60 * 60)
    let fresh = Date()
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "Old image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: Data([1, 2, 3]).base64EncodedString(),
        updatedAt: old,
        hash: "old-image"
    ))
    try store.upsert(ClipboardItem(
        kind: .image,
        title: "Fresh image",
        preview: "1 x 1",
        sourceApp: "Tests",
        imagePNGBase64: Data([4, 5, 6]).base64EncodedString(),
        updatedAt: fresh,
        hash: "fresh-image"
    ))
    #expect(blobFileCount(in: store.blobsDirectoryURL) == 2)

    try store.updatePreferences { $0.historyRetention = .week }

    #expect(store.items.map(\.hash) == ["fresh-image"])
    #expect(blobFileCount(in: store.blobsDirectoryURL) == 1)
}

private func blobFileCount(in directory: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
    ) else {
        return 0
    }
    return enumerator.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath }.count
}
