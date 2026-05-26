import Foundation

public enum ClipboardFormatter {
    public enum FormatError: LocalizedError, Equatable {
        case invalidJSON

        public var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "不是有效的 JSON"
            }
        }
    }

    public static func detectKind(_ value: String) -> ClipboardKind {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .text
        }

        // 顺序敏感：JSON / XML 起始字符强、先判；SQL 单独判（看关键字）；
        // YAML 在 markdown 之前（YAML key: value 容易被 markdown 误认，但 markdown 启发式较粗）。
        if isJSON(trimmed) {
            return .json
        }

        if isXML(trimmed) {
            return .xml
        }

        if isSQL(value) {
            return .sql
        }

        if isURLLike(trimmed) {
            return .url
        }

        if isYAML(value) {
            return .yaml
        }

        if isMarkdown(value) {
            return .markdown
        }

        if isCode(value) {
            return .code
        }

        return .text
    }

    public static func isJSON(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8) else {
            return false
        }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    public static func isXML(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else {
            return false
        }

        return matches(#"^<\?xml[\s\S]+\?>"#, in: trimmed)
            || matches(#"^<([A-Za-z_][\w:.-]*)(\s[^>]*)?>[\s\S]*</\1>$"#, in: trimmed)
            || matches(#"^<[A-Za-z_][\w:.-]*(\s[^>]*)?/>$"#, in: trimmed)
    }

    public static func isMarkdown(_ value: String) -> Bool {
        let patterns = [
            #"(?m)^#{1,6}\s+\S"#,
            #"(?m)^[-*+]\s+\S"#,
            #"(?m)^\d+\.\s+\S"#,
            #"```[\s\S]*```"#,
            #"\[[^\]]+\]\([^)]+\)"#,
            #"(?m)^\|.+\|$"#,
            #"(?m)^>\s+\S"#,
            #"(^|\s)(\*\*|__)[^*_]+(\*\*|__)(\s|$)"#
        ]

        return patterns.contains { matches($0, in: value) }
    }

    /// SQL 检测：必须含核心关键字结构，且不是 markdown 代码块外的散文。
    public static func isSQL(_ value: String) -> Bool {
        let segments = splitOnSingleQuotedLiterals(value)
        // 仅在非字符串段上做关键字匹配，避免 'select' 之类的字面量触发误判。
        let stripped = segments.enumerated()
            .filter { $0.offset % 2 == 0 }
            .map { $0.element }
            .joined(separator: " ")

        // 这些谓语 / 子句一旦出现，配合 SELECT…FROM 才算 SQL —— 避免散文里 "select X from Y" 被误判。
        let strongHints = [
            #"(?i)\b(WHERE|GROUP\s+BY|ORDER\s+BY|HAVING|LIMIT|OFFSET|JOIN|UNION)\b"#,
            #"[*,();]"#,
            #"(?i)\b(AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX)\b"#
        ]

        let hasSelectFrom = matches(#"(?is)\bSELECT\b[\s\S]+?\bFROM\b"#, in: stripped)
        let hasStrong = strongHints.contains { matches($0, in: stripped) }

        if hasSelectFrom && hasStrong {
            return true
        }

        if matches(#"(?is)\bINSERT\s+INTO\b[\s\S]+?\bVALUES\b"#, in: stripped) {
            return true
        }

        if matches(#"(?is)\bUPDATE\b\s+\w+\s+\bSET\b"#, in: stripped) {
            return true
        }

        if matches(#"(?is)\bDELETE\s+FROM\b"#, in: stripped) {
            return true
        }

        if matches(#"(?is)\bWITH\b\s+\w+\s+\bAS\b\s*\("#, in: stripped) {
            return true
        }

        return false
    }

    /// YAML 检测：≥2 行，多数非空行像 `key: value`，且没有任何行以 `{`/`<` 开头。
    public static func isYAML(_ value: String) -> Bool {
        let lines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonBlank.count >= 2 else {
            return false
        }

        for line in nonBlank {
            let trimmedStart = line.drop(while: { $0 == " " || $0 == "\t" })
            if let first = trimmedStart.first {
                if first == "{" || first == "<" || first == "[" {
                    return false
                }
            }
        }

        let keyRegex = #"^\s*(-\s+)?[\w.\-]+\s*:(\s+\S.*)?$"#
        let listRegex = #"^\s*-\s+\S"#
        let docMarker = #"^---\s*$"#
        let matched = nonBlank.filter {
            matches(keyRegex, in: $0) || matches(listRegex, in: $0) || matches(docMarker, in: $0)
        }

        return Double(matched.count) / Double(nonBlank.count) >= 0.6
    }

    public static func format(_ value: String, as transform: ClipboardTransform) throws -> String {
        switch transform {
        case .original:
            return value
        case .json:
            return try formatJSON(value)
        case .xml:
            return formatXML(value)
        case .yaml:
            return formatYAML(value)
        case .sql:
            return formatSQL(value)
        case .markdown:
            return formatMarkdown(value)
        case .plain:
            return formatPlainText(value)
        }
    }

    public static func formatJSON(_ value: String) throws -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let output = String(data: formatted, encoding: .utf8) else {
            throw FormatError.invalidJSON
        }

        return output
    }

    public static func formatXML(_ value: String) -> String {
        let source = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
            .replacingOccurrences(of: "><", with: ">\n<")

        var depth = 0

        return source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let isClosing = line.hasPrefix("</")
                let isDeclaration = line.hasPrefix("<?") || line.hasPrefix("<!")
                let isSelfClosing = line.hasSuffix("/>")
                let isInlineClose = matches(#"^<([A-Za-z_][\w:.-]*)(\s[^>]*)?>.*</\1>$"#, in: line)

                if isClosing {
                    depth = max(depth - 1, 0)
                }

                let output = String(repeating: "  ", count: depth) + line

                if !isClosing && !isDeclaration && !isSelfClosing && !isInlineClose {
                    depth += 1
                }

                return output
            }
            .joined(separator: "\n")
    }

    /// YAML 轻量整理：tab → 2 空格、去尾空白、连续空行折叠、`key:` 后保证单空格。幂等。
    public static func formatYAML(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        var output: [String] = []
        var blankCount = 0
        var inBlockScalar = false
        var blockScalarIndent = -1

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)

            // 把行首 tab 展开成 2 空格（仅 leading）。
            var leadingTabs = 0
            while line.first == "\t" {
                leadingTabs += 1
                line.removeFirst()
            }
            if leadingTabs > 0 {
                line = String(repeating: "  ", count: leadingTabs) + line
            }

            // 行尾空白
            while line.last == " " || line.last == "\t" {
                line.removeLast()
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行折叠
            if trimmed.isEmpty {
                blankCount += 1
                if blankCount <= 1 {
                    output.append("")
                }
                continue
            }
            blankCount = 0

            // 块标量（| 或 >）后续行原样保留
            if inBlockScalar {
                let leading = line.prefix(while: { $0 == " " }).count
                if leading > blockScalarIndent || trimmed.isEmpty {
                    output.append(line)
                    continue
                }
                inBlockScalar = false
                blockScalarIndent = -1
            }

            // `key: value` 单空格规整（仅当行不像注释、且匹配简单 key:value 模式）。
            if !trimmed.hasPrefix("#"),
               let normalizedLine = collapseYAMLKeyValueSpacing(line) {
                output.append(normalizedLine)
            } else {
                output.append(line)
            }

            // 检测块标量起始
            if trimmed.hasSuffix("|") || trimmed.hasSuffix(">") ||
                matches(#":\s*[|>][-+]?\s*$"#, in: trimmed) {
                inBlockScalar = true
                blockScalarIndent = line.prefix(while: { $0 == " " }).count
            }
        }

        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SQL 关键字大写 + 主子句换行。保留字符串字面量中的原始内容。
    public static func formatSQL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        // 1) 用 ' …' 字面量分段：奇数段是 quoted（保持不变），偶数段做替换。
        let segments = splitOnSingleQuotedLiterals(trimmed)
        let majorClauses = [
            "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING",
            "LIMIT", "OFFSET", "UNION ALL", "UNION", "INTERSECT", "EXCEPT",
            "VALUES", "SET", "RETURNING", "WITH"
        ]
        let inlineClauses = [
            "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
            "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "CROSS JOIN", "JOIN",
            "ON", "AND", "OR"
        ]
        let standaloneKeywords = [
            "INSERT INTO", "DELETE FROM", "UPDATE", "CREATE TABLE", "ALTER TABLE",
            "DROP TABLE", "TRUNCATE", "AS", "IN", "NOT", "IS", "NULL",
            "DISTINCT", "BETWEEN", "LIKE", "ILIKE", "EXISTS", "CASE", "WHEN",
            "THEN", "ELSE", "END", "USING", "ASC", "DESC", "BY"
        ]

        var rebuilt: [String] = []

        for (index, segment) in segments.enumerated() {
            if index % 2 == 1 {
                // quoted literal
                rebuilt.append("'\(segment)'")
                continue
            }

            var transformed = segment

            // 大写所有关键字（多 token 的先替换以避免子串问题）。
            let allKeywords = (majorClauses + inlineClauses + standaloneKeywords)
                .sorted { $0.count > $1.count }

            for keyword in allKeywords {
                let escaped = NSRegularExpression.escapedPattern(for: keyword)
                let pattern = #"(?i)\b"# + escaped + #"\b"#
                transformed = replace(pattern: pattern, in: transformed) { _ in keyword }
            }

            rebuilt.append(transformed)
        }

        var joined = rebuilt.joined()

        // 2) 折叠多余空白（不动 quoted —— 但我们已经把 quoted 用 '…' 包回去后再展开会破坏；
        //    所以再分一次：替换非 quoted 段的空白。
        joined = collapseWhitespaceOutsideQuotes(joined)

        // 3) 在主子句前换行。
        for clause in [
            "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING",
            "LIMIT", "OFFSET", "UNION ALL", "UNION", "INTERSECT", "EXCEPT",
            "VALUES", "SET", "RETURNING"
        ] {
            let escaped = NSRegularExpression.escapedPattern(for: clause)
            let pattern = #"\s*\b"# + escaped + #"\b"#
            joined = replace(pattern: pattern, in: joined) { match in
                let isAtStart = (match.lowerBound == joined.startIndex)
                return (isAtStart ? "" : "\n") + clause
            }
        }

        // 4) JOIN / ON / AND / OR 缩进续行。
        for clause in inlineClauses {
            let escaped = NSRegularExpression.escapedPattern(for: clause)
            let pattern = #"\s*\b"# + escaped + #"\b"#
            joined = replace(pattern: pattern, in: joined) { match in
                let isAtStart = (match.lowerBound == joined.startIndex)
                return (isAtStart ? "" : "\n  ") + clause
            }
        }

        // 5) SELECT 行多列：把 `,` 后的空格改为 `\n  `（仅 SELECT 与 FROM 之间）。
        joined = formatSelectColumns(in: joined)

        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func formatMarkdown(_ value: String) -> String {
        let lines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }

        var output: [String] = []
        var blankCount = 0
        var inFence = false

        for rawLine in lines {
            var line = rawLine.replacingOccurrences(
                of: #"^\s{4,}([-*+]|\d+\.)\s+"#,
                with: "  $1 ",
                options: .regularExpression
            )

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                output.append(line)
                blankCount = 0
                continue
            }

            if !inFence && line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankCount += 1
                if blankCount <= 1 {
                    output.append("")
                }
                continue
            }

            blankCount = 0

            if !inFence {
                line = line.replacingOccurrences(of: "\t", with: "  ")
            }

            output.append(line)
        }

        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func formatPlainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func preview(_ value: String, limit: Int = 180) -> String {
        let compact = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.count > limit else {
            return compact
        }

        return String(compact.prefix(max(limit - 1, 0))) + "..."
    }

    public static func isURLLike(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !value.isEmpty else {
            return false
        }

        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "ssh", "git"].contains(scheme) {
            return true
        }

        return matches(#"^(?:git|ssh)@[\w.-]+:[^\s]+$"#, in: value)
    }

    private static func isCode(_ value: String) -> Bool {
        let patterns = [
            #"\b(function|const|let|var|class|import|export|return|async|await)\b"#,
            #"=>\s*[{(]?"#,
            #";\s*$"#,
            #"(?m)^\s*(if|for|while|switch)\s*\("#,
            #"</?[A-Za-z][\w:-]*(\s[^>]*)?>"#,
            #"\b(def|from|print|lambda|yield)\b"#
        ]

        return patterns.contains { matches($0, in: value) }
    }

    // MARK: - Regex helpers

    private static func matches(_ pattern: String, in value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    /// 用回调替换正则匹配区域；回调收到匹配在原串中的 Range。
    private static func replace(
        pattern: String,
        in value: String,
        using replacement: (Range<String.Index>) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: nsRange).reversed()
        var result = value

        for match in matches {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            let replaced = replacement(range)
            result.replaceSubrange(range, with: replaced)
        }

        return result
    }

    private static func collapseYAMLKeyValueSpacing(_ line: String) -> String? {
        let pattern = #"^(\s*)((?:-\s+)?[\w.\-]+)\s*:\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges == 4,
              let indentRange = Range(match.range(at: 1), in: line),
              let keyRange = Range(match.range(at: 2), in: line),
              let valueRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let indent = String(line[indentRange])
        let key = String(line[keyRange])
        let rawValue = String(line[valueRange]).trimmingCharacters(in: .whitespaces)

        if rawValue.isEmpty {
            return indent + key + ":"
        }

        return indent + key + ": " + rawValue
    }

    /// 把字符串按单引号字面量拆开：偶数段是普通文本，奇数段是不含外侧引号的字面量内容。
    private static func splitOnSingleQuotedLiterals(_ value: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var insideQuote = false
        var iterator = value.makeIterator()

        while let ch = iterator.next() {
            if ch == "'" {
                if insideQuote {
                    // 处理 SQL 中的 '' 转义：连续两个单引号当作一个字符。
                    var lookahead = iterator
                    if let next = lookahead.next(), next == "'" {
                        current.append("'")
                        current.append("'")
                        iterator = lookahead
                        continue
                    }
                    segments.append(current)
                    current = ""
                    insideQuote = false
                } else {
                    segments.append(current)
                    current = ""
                    insideQuote = true
                }
                continue
            }
            current.append(ch)
        }

        // 收尾：未闭合的字符串当普通文本处理。
        if insideQuote {
            // segments 末尾追加的 "" 替换为 "' + current"，保留原样。
            if let last = segments.popLast() {
                segments.append(last + "'" + current)
            } else {
                segments.append("'" + current)
            }
            // 让段数为奇数（普通文本结尾）以匹配偶数段=文本约定。
            return segments
        }

        segments.append(current)
        return segments
    }

    /// 将外部传入的、已经把 quoted 部分用 '…' 重新包好的字符串中的非 quoted 区域空白折叠。
    private static func collapseWhitespaceOutsideQuotes(_ value: String) -> String {
        var result = ""
        var insideQuote = false
        var pendingSpace = false
        var iterator = value.makeIterator()

        while let ch = iterator.next() {
            if ch == "'" {
                if insideQuote {
                    var lookahead = iterator
                    if let next = lookahead.next(), next == "'" {
                        result.append("''")
                        iterator = lookahead
                        continue
                    }
                }
                insideQuote.toggle()
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append("'")
                continue
            }

            if insideQuote {
                result.append(ch)
                continue
            }

            if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
                pendingSpace = true
                continue
            }

            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(ch)
        }

        return result
    }

    /// 把 SELECT 行的列用 `,\n  ` 分隔（仅在 SELECT 与 FROM 之间）。
    private static func formatSelectColumns(in value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        var rebuilt: [String] = []

        for raw in lines {
            let line = String(raw)
            if line.uppercased().hasPrefix("SELECT") {
                // 把 SELECT 行的逗号变成换行 + 缩进。
                let withBreaks = breakSelectColumns(line)
                rebuilt.append(contentsOf: withBreaks.split(separator: "\n").map(String.init))
            } else {
                rebuilt.append(line)
            }
        }

        return rebuilt.joined(separator: "\n")
    }

    private static func breakSelectColumns(_ line: String) -> String {
        // 输入形如 "SELECT a, b, c"；按非引号、非括号区域的逗号切分。
        guard line.uppercased().hasPrefix("SELECT") else {
            return line
        }
        let head = "SELECT "
        let tail = String(line.dropFirst("SELECT".count)).trimmingCharacters(in: .whitespaces)

        var parts: [String] = []
        var current = ""
        var depth = 0
        var insideQuote = false
        var iterator = tail.makeIterator()

        while let ch = iterator.next() {
            if ch == "'" {
                insideQuote.toggle()
                current.append(ch)
                continue
            }
            if insideQuote {
                current.append(ch)
                continue
            }
            if ch == "(" {
                depth += 1
                current.append(ch)
                continue
            }
            if ch == ")" {
                depth = max(0, depth - 1)
                current.append(ch)
                continue
            }
            if ch == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(ch)
        }

        let final = current.trimmingCharacters(in: .whitespaces)
        if !final.isEmpty {
            parts.append(final)
        }

        guard parts.count > 1 else {
            return head + tail
        }

        return head + parts.joined(separator: ",\n  ")
    }
}
