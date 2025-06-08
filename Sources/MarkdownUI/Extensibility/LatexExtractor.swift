//
//  LatexExtractor.swift
//  swift-markdown-ui
//
//  Created by mingdw on 2025/6/8.
//

// LatexExtractor.swift (最终修复版 - 职责分离)

import Foundation

// MARK: - Public Data Structures (无改动)
enum BlockType: Equatable, Hashable {
    case mixedContent, markdown, latexBlock, codeBlock
}

struct ContentBlock: Equatable, Hashable {
    let type: BlockType
    var content: String
    var isTerminated: Bool = true
}

enum LatexExtractorError: Error, Equatable {
    case unterminatedLatex(startDelimiter: String, partialContent: String)
    case unterminatedCodeBlock(startDelimiter: String, partialContent: String)
}


// MARK: - LatexExtractor
final class LatexExtractor {

    // MARK: - Private Properties & Constants (无改动)
    private static let codeBlockDelimiters = ["```", "~~~"]
    // 只用它来检测 `$...$` 形式的公式
    private static let inlineLatexPresenceRegex = try! NSRegularExpression(
        pattern: #"(?<![\$\\])\$((?:\\.|[^$\n])+?)\$(?!\$)"#
    )
    private var input: String = ""
    private var currentIndex: String.Index = "".startIndex
    private var blocks: [ContentBlock] = []
    private var currentBuffer = ""
    private var codeBlockStack: [String] = []

    // MARK: - Public API & Reset
    @MainActor static let shared = LatexExtractor(text: "")
    @MainActor static func parseSegments(_ content: String) -> [ContentBlock] {
        let extractor = LatexExtractor.shared
        extractor.reset(with: content)
        do {
            return try extractor.parse()
        } catch let error as LatexExtractorError {
            var finalBlocks = extractor.blocks
            switch error {
            case .unterminatedLatex(_, let partialContent):
                if !partialContent.isEmpty {
                    let normalized = Self.normalizeContent(for: .latexBlock, with: partialContent)
                    finalBlocks.append(ContentBlock(type: .latexBlock, content: normalized, isTerminated: false))
                }
            // 正确处理未闭合的代码块
            case .unterminatedCodeBlock:
                if !extractor.currentBuffer.isEmpty {
                    let normalized = Self.normalizeContent(for: .codeBlock, with: extractor.currentBuffer)
                    finalBlocks.append(ContentBlock(type: .codeBlock, content: normalized, isTerminated: false))
                }
            }
            return finalBlocks
        } catch {
            return extractor.blocks
        }
    }
    
    private init(text: String) { self.reset(with: text) }
    private func reset(with text: String) {
        self.input = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        self.currentIndex = self.input.startIndex
        self.blocks = []
        self.currentBuffer = ""
        self.codeBlockStack = []
    }
    
    // MARK: - 主解析逻辑 (使用您原始的、安全的版本)
    private func parse() throws -> [ContentBlock] {
        while hasMore {
            //print("enter, current index: \(currentIndex), end index: \(input.endIndex)")
            //if input[currentIndex].isNewline {
            //    currentBuffer.append("\n")
            //    advance()
            //    continue
            //}
            //print("input: \(input)")
            if !codeBlockStack.isEmpty {
                try parseInCodeBlock()
            } else {
                try parseInNormalContent()
            }
            
            //print("exit,  current index: \(currentIndex), end index: \(input.endIndex)")
        }
        
        flushBuffer()
        
        if let unterminatedDelimiter = codeBlockStack.last {
            // 手动补上闭合标记
            currentBuffer.append("\n\(unterminatedDelimiter)")

            // flush 为不完整代码块
            let normalized = Self.normalizeContent(for: .codeBlock, with: currentBuffer)
            blocks.append(ContentBlock(type: .codeBlock, content: normalized, isTerminated: false))
            
            currentBuffer = ""
            codeBlockStack.removeAll()
        }
        // 解析结束后，合并连续的 Markdown 块
        return Self.mergeConsecutiveBlocks(blocks)
    }

    // 您原始的 parseInNormalContent
    private func parseInNormalContent() throws {
        //let line = getLineContent(from: currentIndex)
        //print("#####parseInNormalContent: \(line)")
        if isAtStartOfLine() {
            //print("++++parseInNormalContent:\n\(line)")
            let line = getLineContent(from: currentIndex)
            let trimmedLine = line.drop(while: { $0.isWhitespace })
            if let match = Self.codeBlockDelimiters.first(where: { trimmedLine.hasPrefix($0) }) {
                //print("#####parseInNormalContent:\(line)")
                flushBuffer()
                codeBlockStack.append(match)
                currentBuffer.append(contentsOf: trimmedLine)
                advance(by: line.count)
                if hasMore && input[currentIndex] == "\n" {
                    currentBuffer.append("\n")
                    advance()
                }
                return
            }
        }
        currentBuffer.append(input[currentIndex])
        advance()
    }
    
    // 您原始的 parseInCodeBlock
    private func parseInCodeBlock() throws {
        //print("%%%%%%%%%%%%%%%%%%%%%%")
        guard let openingDelimiter = codeBlockStack.last else {
            //print("……………………………………………………………………")
            try parseInNormalContent(); return
        }
        let line = getLineContent(from: currentIndex)
        //print("-----parseInCodeBlock:\n\(line)")
        let trimmedLine = line.drop(while: { $0.isWhitespace })
        if let fenceType = Self.codeBlockDelimiters.first(where: { trimmedLine.hasPrefix($0) }) {
            let restOfLine = trimmedLine.dropFirst(fenceType.count)
            if fenceType == openingDelimiter && restOfLine.allSatisfy({ $0.isWhitespace }) {
                //print("-----parseInCodeBlock:\(line)")
                currentBuffer.append(contentsOf: trimmedLine)
                codeBlockStack.removeLast()
                if codeBlockStack.isEmpty {
                    //print("!!!!!!!parseInCodeBlock:\(line), line count: \(line.count)")
                    flushBuffer(typeOverride: .codeBlock)
                }
            } else {
                //print("++++++parseInCodeBlock:\(line)")
                currentBuffer.append(contentsOf: line)
                codeBlockStack.append(fenceType)
            }
        } else {
            //print("=====parseInCodeBlock:\(line), line count: \(line.count)")
            currentBuffer.append(contentsOf: line)
        }
        advance(by: line.count)
        if hasMore && input[currentIndex] == "\n" {
            //print("!!!!!!!parseInCodeBlock:\n\(line), line count: \(line.count)")
            currentBuffer.append("\n")
            advance()
        }
    }
    
    // MARK: - 缓冲区处理
    
    // flushBuffer 保持不变
    private func flushBuffer(typeOverride: BlockType? = nil) {
        if currentBuffer.isEmpty { return }
        if let type = typeOverride {
            //print("\n\n@@@@@currentBuffer:\n\n\(currentBuffer)\n\n")
            var normalizedContent = currentBuffer
            if type == .latexBlock {
                normalizedContent = Self.normalizeContent(for: type, with: normalizedContent)
            }
            if !normalizedContent.isEmpty {
                blocks.append(ContentBlock(type: type, content: normalizedContent))
            }
        } else {
            let subBlocks = processMarkdownBuffer(currentBuffer)
            blocks.append(contentsOf: subBlocks)
        }
        currentBuffer = ""
        //print("@@@@@blocks:\n\(blocks)")
    }
    
    // =========================================================================
    // 这是唯一的、真正的修复
    // `processMarkdownBuffer` 不再尝试解析代码块，因为它会与主解析器冲突。
    // =========================================================================
    private func processMarkdownBuffer(_ text: String) -> [ContentBlock] {
        var subBlocks: [ContentBlock] = []
        var lastIndex = text.startIndex

        // 正则表达式现在只关心 LaTeX 块，不再匹配代码块。
        let latexBlockFinder = try! NSRegularExpression(
            pattern: #"""
            (?sxm)
            ( ^\s* \$\$ .*? \$\$ \s* $ | ^\s* \\\[ .*? \\\] \s* $ | ^\s* \\begin\{[a-zA-Z0-9*]+\} .*? \\end\{[a-zA-Z0-9*]+\} \s* $ )
            """#,
            options: []
        )

        let matches = latexBlockFinder.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            if matchRange.lowerBound > lastIndex {
                let textPart = String(text[lastIndex..<matchRange.lowerBound])
                subBlocks.append(contentsOf: processGeneralMarkdown(textPart))
            }
            let rawContent = String(text[matchRange])
            let normalizedContent = Self.normalizeContent(for: .latexBlock, with: rawContent)
            if !normalizedContent.isEmpty {
                subBlocks.append(ContentBlock(type: .latexBlock, content: normalizedContent))
            }
            lastIndex = matchRange.upperBound
        }

        if lastIndex < text.endIndex {
            let textPart = String(text[lastIndex...])
            subBlocks.append(contentsOf: processGeneralMarkdown(textPart))
        }
        
        return subBlocks
    }

    // ... (其他所有函数，如 processGeneralMarkdown, normalizeContent, helpers 等都保持您原始的版本) ...
    private func processGeneralMarkdown(_ text: String) -> [ContentBlock] {
        if text.isEmpty { return [] }
        var subBlocks: [ContentBlock] = []
        let paragraphs = text.components(separatedBy: .newlines)
        for paragraph in paragraphs {
            let content = paragraph.trimmingCharacters(in: .newlines)
            if content.isEmpty { continue }

            // 使用一个新的辅助函数来判断是否存在 LaTeX
            if self.paragraphContainsLatex(content) {
                subBlocks.append(ContentBlock(type: .mixedContent, content: content))
            } else {
                subBlocks.append(ContentBlock(type: .markdown, content: content))
            }
        }
        return subBlocks
    }
    
    // =========================================================================
    // 这是新增的、健壮的辅助函数，用于替代有问题的正则表达式
    // =========================================================================
    private func paragraphContainsLatex(_ p: String) -> Bool {
        // 忽略反引号包裹的内容（inline code span）
        let inlineCodeRegex = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
        var stripped = p
        for match in inlineCodeRegex.matches(in: p, range: NSRange(p.startIndex..<p.endIndex, in: p)).reversed() {
            if let range = Range(match.range, in: stripped) {
                let length = stripped.distance(from: range.lowerBound, to: range.upperBound)
                stripped.replaceSubrange(range, with: String(repeating: " ", count: length))
            }
        }

        // 1. 先用我们修改过的、可靠的正则检查是否存在 `$...$` 公式
        if Self.inlineLatexPresenceRegex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)) != nil {
            return true
        }

        // 2. 检查是否存在 `\(` 行内 LaTeX
        var i = stripped.startIndex
        while i < stripped.endIndex {
            if stripped[i] == "\\" {
                let nextIndex = stripped.index(after: i)
                if nextIndex < stripped.endIndex {
                    if stripped[nextIndex] == "(" {
                        return true
                    }
                }
                i = nextIndex < stripped.endIndex ? stripped.index(after: nextIndex) : stripped.index(after: i)
            } else {
                i = stripped.index(after: i)
            }
        }

        // 3. 如果两种都找不到，才返回 false
        return false
    }
    
    private static func normalizeContent(for type: BlockType, with rawContent: String) -> String {
        let lines = rawContent.components(separatedBy: .newlines)
        switch type {
        case .codeBlock:
            guard lines.count > 1 else { return "" }
            let contentLines = lines.dropFirst().dropLast()
            let commonIndent = contentLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix(while: { $0.isWhitespace }).count }.min() ?? 0
            let deindentedLines = contentLines.map { String($0.dropFirst(min($0.count, commonIndent))) }
            return deindentedLines.joined(separator: "\n")
        case .latexBlock:
            let commonIndent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix(while: { $0.isWhitespace }).count }.min() ?? 0
            if commonIndent > 0 {
                let deindentedLines = lines.map { String($0.dropFirst(min($0.count, commonIndent))) }
                return deindentedLines.joined(separator: "\n")
            }
            return rawContent
        case .markdown, .mixedContent:
            return rawContent
        }
    }
    
    private static func mergeConsecutiveBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {
        if blocks.isEmpty { return [] }
        var merged: [ContentBlock] = []
        for block in blocks {
            if block.content.isEmpty { continue }
            if var lastBlock = merged.last, lastBlock.type == block.type, (block.type == .markdown || block.type == .mixedContent) {
                lastBlock.content += "\n\n" + block.content
                merged[merged.count - 1] = lastBlock
            } else {
                merged.append(block)
            }
        }
        return merged
    }
    
    private var hasMore: Bool { currentIndex < input.endIndex }
    
    private func advance(by count: Int = 1) {
        //print("enter, current index: \(currentIndex), end index: \(input.endIndex), count: \(count)")
        currentIndex = input.index(currentIndex, offsetBy: count, limitedBy: input.endIndex) ?? input.endIndex
        //print("exit,  current index: \(currentIndex), end index: \(input.endIndex), count: \(count)")
    }
    
    private func isAtStartOfLine() -> Bool {
        if currentIndex == input.startIndex { return true }
        let prevChar = input[input.index(before: currentIndex)]
        return prevChar.isNewline
    }
    
    private func getLineContent(from index: String.Index) -> Substring {
        let remaining = input[index...]
        if let newlineIndex = remaining.firstIndex(of: "\n") {
            return remaining[..<newlineIndex]
        }
        return remaining[...]
    }
    
    static func parseMixedContentLine(_ line: String) -> [(isLatex: Bool, content: String)] {
        var segments: [(isLatex: Bool, content: String)] = []
        var currentIndex = line.startIndex
        let inlineRegex = try! NSRegularExpression(pattern: #"(?x)(?<![\$\\])\$((?:\\.|[^$\n])+?)\$(?!\$) |\\\(((?:\\.|[^)\n])+?)\\\)"#)
        let matches = inlineRegex.matches(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line))
        for match in matches {
            guard let matchRange = Range(match.range, in: line) else { continue }
            if matchRange.lowerBound > currentIndex {
                segments.append((isLatex: false, content: String(line[currentIndex..<matchRange.lowerBound])))
            }
            segments.append((isLatex: true, content: String(line[matchRange])))
            currentIndex = matchRange.upperBound
        }
        if currentIndex < line.endIndex {
            segments.append((isLatex: false, content: String(line[currentIndex...])))
        }
        if segments.isEmpty && !line.isEmpty {
            segments.append((isLatex: false, content: line))
        }
        return segments.filter { !$0.content.isEmpty }
    }
}
