import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, text: String)
    case quote(String)
    case code(String)
    case table(MarkdownTable)
}

struct MarkdownTable: Equatable {
    var headers: [String]
    var rows: [[String]]
}

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("```") {
                let parsed = codeBlock(from: lines, start: index)
                blocks.append(.code(parsed.text))
                index = parsed.nextIndex
            } else if let table = tableBlock(from: lines, start: index) {
                blocks.append(.table(table.value))
                index = table.nextIndex
            } else if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
            } else if let item = listItem(from: trimmed) {
                blocks.append(.listItem(marker: item.marker, text: item.text))
                index += 1
            } else if trimmed.hasPrefix(">") {
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
            } else {
                let parsed = paragraph(from: lines, start: index)
                blocks.append(.paragraph(parsed.text))
                index = parsed.nextIndex
            }
        }
        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    private static func codeBlock(from lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        var codeLines: [String] = []
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return (codeLines.joined(separator: "\n"), index + 1)
            }
            codeLines.append(line)
            index += 1
        }
        return (codeLines.joined(separator: "\n"), index)
    }

    private static func tableBlock(from lines: [String], start: Int) -> (value: MarkdownTable, nextIndex: Int)? {
        guard start + 1 < lines.count,
              isTableRow(lines[start]),
              isSeparatorRow(lines[start + 1]) else { return nil }

        let headers = cells(from: lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, isTableRow(lines[index]) {
            rows.append(cells(from: lines[index]))
            index += 1
        }
        return (MarkdownTable(headers: headers, rows: rows), index)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func listItem(from line: String) -> (marker: String, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ("•", String(line.dropFirst(2).drop(while: { $0 == " " })))
        }
        guard let dot = line.firstIndex(of: "."),
              dot > line.startIndex,
              line[..<dot].allSatisfy(\.isNumber),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return ("\(line[..<dot]).", String(line[line.index(after: dot)...].drop(while: { $0 == " " })))
    }

    private static func paragraph(from lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        var paragraphLines: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") || heading(from: trimmed) != nil ||
                listItem(from: trimmed) != nil || trimmed.hasPrefix(">") {
                break
            }
            if tableBlock(from: lines, start: index) != nil {
                break
            }
            paragraphLines.append(trimmed)
            index += 1
        }
        return (paragraphLines.joined(separator: "\n"), index)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && cells(from: line).count >= 2
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = cells(from: line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
