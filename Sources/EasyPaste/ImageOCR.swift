import AppKit
@preconcurrency import Vision

/// 用 Vision 框架做图片 OCR。支持中英文，返回 \n 拼接的完整文本。
/// 异步、可被取消，识别失败返回 nil。
enum ImageOCR {
    static func recognize(pngData: Data) async -> String? {
        guard let cgImage = NSImage(data: pngData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    NSLog("EasyPaste OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let combined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: combined.isEmpty ? nil : combined)
            }
            // Vision 内置中文识别（zh-Hans / zh-Hant）。同时启用英文，覆盖大多数代码截图 / 网页截图。
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    NSLog("EasyPaste OCR perform failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
