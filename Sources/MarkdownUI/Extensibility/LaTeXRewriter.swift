// In: Sources/MarkdownUI/LaTeXRewriter.swift
import Foundation
import SwiftUI
import SwiftMath
/*
func latexBlockNodeRule(blockNode: BlockNode) -> [BlockNode] {
    guard case .paragraph(let children) = blockNode,
          case .text(let text) = children.first  else {
        return [blockNode]
    }
    let recoverText = SimpleLatexExtractor.recoverLatex(from: text)
    print("\n++++++++++++start\n\(recoverText)\n+++++++++++++end")
    if !recoverText.contains("$")
        && !recoverText.contains("\\(")
        && !recoverText.contains("\\[")
        && !recoverText.contains("$$") {
        //print("There is no latex\n")
        return [inline]
    }
    
    let segmentsInLines = parseMixedContentLine(recoverText)
    //print("----------:\n\(segmentsInLines)\n")
    if segmentsInLines.count <= 1 && segmentsInLines.first?.isLatex == false {
        return [inline]
    }
    
    var newInlines: [InlineNode] = []
    for segment in segmentsInLines {
        //print("----------:\n\(segment.content)\n")
        if segment.isLatex {
            //print("++++++++++++:\n\(segment.content)\n")
            //let content = fixLatexSyntax(in: segment.content)
            newInlines.append(.latex(content: segment.content))
            //print("----------:\n\(segment.content)\n")
        } else {
            newInlines.append(.text(segment.content))
            //print("++++++++++++:\n\(segment.content)\n")
        }
    }
    
    return newInlines
}

/// 接收一个确认是LaTeX的字符串，并修复其中常见的语法和转义错误。
/// 这个函数是高度优化的，专门用于修复单行的、可能包含错误的LaTeX代码。
/// 修复顺序经过精心设计，以避免一个修复破坏另一个修复。
///
/// - Parameter latexString: 输入的、可能包含错误的LaTeX字符串。
/// - Returns: 修复后的LaTeX字符串。
private func fixLatexSyntax(in latexString: String) -> String {
    var text = latexString

    // --- 修复1: 恢复矩阵和多行公式中丢失的换行符 `\\` ---
    // 策略：在 \begin{...} 和 \end{...} 环境内部，查找一个单独的、后面不跟已知命令或花括号的 `\`，
    // 并强制将其恢复为 `\\`。这能非常精确地修复 `a & b \ c & d` 这样的错误。
    let environments = [
        "pmatrix", "bmatrix", "vmatrix", "matrix",
        "cases",
        "align", "align*", "aligned", "alignedat",
        "gather", "gather*", "gathered",
        "split", "eqnarray", "eqnarray*"
    ]
    
    for env in environments {
        let pattern = ##"(\\begin\{"## + env + ##"\} .*? \\end\{"## + env + ##"\})"##
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 1), in: text) else { continue }
            
            var environmentContent = String(text[fullRange])
            
            // 匹配一个`\`，条件是：它前面没有另一个`\`，且后面不跟字母、星号或花括号。
            let brokenNewlineRegex = try! NSRegularExpression(pattern: #"(?<!\\)\\(?![a-zA-Z*{}])"#)
            environmentContent = brokenNewlineRegex.stringByReplacingMatches(
                in: environmentContent,
                range: NSRange(environmentContent.startIndex..., in: environmentContent),
                withTemplate: "\\\\\\\\" // 替换为字面量的 `\\`
            )
            
            text.replaceSubrange(fullRange, with: environmentContent)
        }
    }

    // --- 修复2: 修复 `\text{...}` 内部的转义空格 (`\ ` -> ` `) ---
    let textEnvRegexForSpace = try! NSRegularExpression(pattern: #"\\text\s*\{([^}]*)\}"#)
    let textMatchesForSpace = textEnvRegexForSpace.matches(in: text, range: NSRange(text.startIndex..., in: text))
    for match in textMatchesForSpace.reversed() {
        guard let fullRange = Range(match.range, in: text),
              let contentRange = Range(match.range(at: 1), in: text) else { continue }
        let fixedContent = String(text[contentRange]).replacingOccurrences(of: "\\ ", with: " ")
        text.replaceSubrange(fullRange, with: "\\text{\(fixedContent)}")
    }
    
    // --- 【修复2.5】: (真正安全版) 恢复 LaTeX 中常见的未转义字符 ---
    var protectedBlocks: [String: String] = [:] // 使用字典来确保占位符唯一
    var mutableText = text

    // 步骤 1: 从后向前，用唯一的占位符替换 \text{...} 块
    let protectionRegex = try! NSRegularExpression(pattern: #"\\text\s*\{[^}]*\}"#)
    let protectionMatches = protectionRegex.matches(in: mutableText, range: NSRange(mutableText.startIndex..., in: mutableText))

    for (i, match) in protectionMatches.enumerated().reversed() {
        guard let range = Range(match.range, in: mutableText) else { continue }
        
        let originalBlock = String(mutableText[range])
        let placeholder = "__PROTECTED_BLOCK_\(i)__" // 占位符现在与原始匹配顺序绑定
        
        protectedBlocks[placeholder] = originalBlock
        mutableText.replaceSubrange(range, with: placeholder)
    }

    // 步骤 2: 在被“净化”过的字符串上执行转义 (这部分逻辑是正确的，保持不变)
    let latexSpecials = ["%", "#"]
    for symbol in latexSpecials {
        let pattern = #"(?<!\\)"# + NSRegularExpression.escapedPattern(for: symbol)
        let regex = try! NSRegularExpression(pattern: pattern)
        mutableText = regex.stringByReplacingMatches(
            in: mutableText,
            range: NSRange(mutableText.startIndex..., in: mutableText),
            withTemplate: "\\\\" + symbol
        )
    }

    // 步骤 3: 遍历字典，将被保护的块恢复原状
    for (placeholder, originalBlock) in protectedBlocks {
        mutableText = mutableText.replacingOccurrences(of: placeholder, with: originalBlock, options: .literal)
    }

    text = mutableText // 将修复后的文本赋回
    
    // --- 修复3: 确保矩阵中的 `&` 符号周围有空格 ---
    let tightAlignRegex = try! NSRegularExpression(pattern: #"(\S)&(\S)"#)
    text = tightAlignRegex.stringByReplacingMatches(
        in: text,
        range: NSRange(text.startIndex..., in: text),
        withTemplate: "$1 & $2"
    )
    
    // 匹配一个 `_` 或 `^`，后面跟着至少一个不是分隔符或花括号的字符
    let danglingSubscriptRegex = try! NSRegularExpression(
        pattern: #"([_^])\s*([^{}\s\\$][^{}\s\\$]*)"# // <-- 在字符集中增加了 `$`
    )
    text = danglingSubscriptRegex.stringByReplacingMatches(
        in: text,
        range: NSRange(text.startIndex..., in: text),
        withTemplate: "$1{$2}"
    )
    
    return text
}

private func parseMixedContentLine(_ line: String) -> [(isLatex: Bool, content: String)] {
    var segments: [(isLatex: Bool, content: String)] = []
    var currentIndex = line.startIndex

    // --- 【最终、最强健的正则表达式】 ---
    let combinedRegex = try! NSRegularExpression(pattern:
    #"""
    (?sx) # s: '.' 匹配换行符; x: 扩展模式

    # --- 1. CODE 组 (最优先匹配，规则已强化) ---
    (?<CODE>
        `{3,}[\s\S]+?`{3,}  # 围栏代码块，可以跨行
        |
        ``[\s\S]+?``      # 双反引号，可以包含 `
        |
        `[^`]+?`          # 单反引号，不能包含 `
    )

    | # --- 或者 ---

    # --- 2. LATEX 组 (修复了内联公式的匹配) ---
    (?<LATEX>
        # a. 块级公式 (明确且优先)
        \$\$[\s\S]+?\$\$
        |
        \\\[[\s\S]+?\\\]
        
        | # 或
        
        # b. 【核心修复】内联公式 $...$
        #    匹配一个'$'，它前面不是另一个'$'或反斜杠
        (?<!\$|\\)
        \$
        #    匹配任何非'$'字符，或者被转义的'$' (\$)
        (?:\\. | [^$])+?
        #    直到匹配一个'$'，它后面不是另一个'$'
        \$
        (?!\$)
        
        | # 或，另一种内联形式 \( ... \)
        
        \\\(.+?\\\)
        | # 或，另一种内联形式 \( ... \)
                
        \\\(          # 匹配字面的 \(
        [\s\S]+?    # 匹配任何内容，非贪婪
        \\\)          # 匹配字面的 \)
        )
    """#, options: [])
    
    // --- 后续的处理逻辑完全正确，无需修改 ---
    let matches = combinedRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
    
    var lastMatchEnd = line.startIndex
    for match in matches {
        guard let matchRange = Range(match.range, in: line) else { continue }
        
        // 追加上一个匹配和当前匹配之间的普通文本
        if matchRange.lowerBound > lastMatchEnd {
            let textSegment = String(line[lastMatchEnd..<matchRange.lowerBound])
            segments.append((isLatex: false, content: textSegment))
        }
        
        // 检查哪个命名组匹配成功
        let content = String(line[matchRange])
        if match.range(withName: "CODE").location != NSNotFound {
            segments.append((isLatex: false, content: content))
        }
        else if match.range(withName: "LATEX").location != NSNotFound {
            segments.append((isLatex: true, content: content))
        }
        
        lastMatchEnd = matchRange.upperBound
    }
    
    // 追加最后一个匹配之后的所有剩余文本
    if lastMatchEnd < line.endIndex {
        segments.append((isLatex: false, content: String(line[lastMatchEnd...])))
    }
    
    // 如果没有任何匹配，则整个字符串都是普通文本
    if segments.isEmpty && !line.isEmpty {
        segments.append((isLatex: false, content: line))
    }
    
    return segments.filter { !$0.content.isEmpty }
}

private func LatexView(_ source: String, att: AttributeContainer) -> Text {
    let fontSize = att.fontProperties?.size ?? 14
    let foregroundColor = att.foregroundColor ?? .primary
    let hasLatexBlock = source.hasPrefix("$$") && source.hasSuffix("$$")
    //print("++++++++++++:\n\(source)\n")
    let (_, nsImage) = MTMathImage(
      latex: source,
      fontSize: fontSize,
      textColor: MTColor(foregroundColor),
      labelMode: hasLatexBlock ? .display : .text
    ).asImage()

    guard let nsImage else {
        print("=========:\n\(source)\n")
      return Text(source)
    }

    var nsFont: NSFont
    let attributedString = NSAttributedString(AttributedString(" ", attributes: att))
    if let fontFromAttributes = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, fontFromAttributes.pointSize > 0 {
        nsFont = fontFromAttributes
    } else {
        nsFont = .systemFont(ofSize: NSFont.systemFontSize)
    }

    let imageHeight = nsImage.size.height
    let fontXHeight = nsFont.xHeight
    let offset = (imageHeight / 2.0) - (fontXHeight / 2.0)
    let baselineOffset = -offset
    
    let imageAsText = Text("\(Image(nsImage: nsImage))")
        .baselineOffset(baselineOffset)
    
    return imageAsText
}

func renderTextWithLatex(from attributedInput: AttributedString, cache: [String: String]) -> Text {
    var finalTextView = Text("")
    var currentIndex = attributedInput.startIndex

    let placeholderPrefix = "LATEX_PLACEHOLDER_6A8C5E7B_"
    let regex = try! NSRegularExpression(pattern: "\(placeholderPrefix)\\d+")
    
    let plainString = String(attributedInput.characters)
    let matches = regex.matches(in: plainString, range: NSRange(plainString.startIndex..., in: plainString))
    
    var lastMatchEnd = attributedInput.startIndex
    
    for match in matches {
        guard let matchRange = Range(match.range, in: attributedInput) else { continue }
        
        // 1. 追加占位符之前的普通文本
        if matchRange.lowerBound > lastMatchEnd {
            // 【修复】: 将切片 AttributedSubstring 转换回 AttributedString
            let substring = attributedInput[lastMatchEnd..<matchRange.lowerBound]
            finalTextView = finalTextView + Text(AttributedString(substring))
        }
        
        // 2. 找到占位符，从缓存中恢复 LaTeX 并渲染
        let placeholderKey = String(attributedInput[matchRange].characters)
        if let latexString = cache[placeholderKey] {
            var localAttributes = AttributeContainer()
            if let run = attributedInput.runs.first(where: { $0.range.contains(matchRange.lowerBound) }) {
                localAttributes = run.attributes
            }
            
            finalTextView = finalTextView + LatexView(latexString, att: localAttributes)
        } else {
            finalTextView = finalTextView + Text(placeholderKey).foregroundColor(.red)
        }
        
        lastMatchEnd = matchRange.upperBound
    }
    
    // 3. 追加最后一个占位符之后的文本
    if lastMatchEnd < attributedInput.endIndex {
        // 【修复】: 同样，将切片转换回 AttributedString
        let substring = attributedInput[lastMatchEnd...]
        finalTextView = finalTextView + Text(AttributedString(substring))
    }
    
    return finalTextView
}
*/
#if false
// MARK: - Data Structures
enum BlockType {
    case markdownBlock
    case latexBlock
}

struct ExtractedBlock {
    let type: BlockType
    let content: String
    let range: Range<String.Index> // 新增！
}

struct ExtractionResult {
    let hasLatex: Bool
    let blocks: [ExtractedBlock]
}

// MARK: - SimpleLatexExtractor
final class SimpleLatexExtractor {

    // MARK: - Public API
    //static func reJoinedWithLatex(from text: String) -> String {
    //    let result = extract(from: text)
    //    return result.blocks.map { $0.content }.joined()
    //}

    // In class SimpleLatexExtractor

    /// 主提取函数：分离出 LaTeX 和普通 Markdown/代码块，并返回带范围的块列表。
    static func extract(from text: String) -> ExtractionResult {
        if text.isEmpty {
            return ExtractionResult(hasLatex: false, blocks: [])
        }

        // --- 1. 正则表达式定义 (保持不变) ---
        // 代码块正则
        let codeRegex = try! NSRegularExpression(pattern: #"`{3,}[\s\S]*?`{3,}|``[\s\S]*?``|`[^`]+?`"#, options: [])
        // LaTeX 公式正则
        let latexRegex = try! NSRegularExpression(pattern:
            #"""
            (?smx) # s: '.' 匹配换行; m: '^'和'$'匹配行首行尾; x: 扩展模式
            # 块级公式
            ^\s* \$\$ [\s\S]*? \$\$ \s* $ |
            ^\s* \\\[ [\s\S]*? \\\] \s* $ |
            # 内联公式
            (?<![a-zA-Z0-9]|\\|\$) \$ ([^$]+?) \$ (?![a-zA-Z0-9]|\$) |
            \\\( ([\s\S]*?) \\\)
            """#, options: [])

        // --- 2. 查找所有匹配 ---
        let codeMatches = codeRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let latexMatches = latexRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // --- 3. 过滤掉在代码块内部的 LaTeX 公式 (保持不变) ---
        let codeRanges = codeMatches.map { $0.range }
        let validLatexMatches = latexMatches.filter { latexMatch in
            !codeRanges.contains { codeRange in
                NSIntersectionRange(latexMatch.range, codeRange).length > 0
            }
        }

        // --- 4. 将所有有效匹配（代码+LaTeX）合并并排序 ---
        let allMatches = (codeMatches.map { (match: $0, type: BlockType.markdownBlock) } +
                          validLatexMatches.map { (match: $0, type: BlockType.latexBlock) })
            .sorted { $0.match.range.location < $1.match.range.location }

        // --- 5. 构建最终的、包含所有文本片段的块列表 (核心修改) ---
        var finalBlocks: [ExtractedBlock] = []
        var lastIndex = text.startIndex
        var hasLatex = !validLatexMatches.isEmpty

        for item in allMatches {
            guard let matchRange = Range(item.match.range, in: text) else { continue }

            // a. 追加上一个匹配和当前匹配之间的普通文本
            if matchRange.lowerBound > lastIndex {
                let range = lastIndex..<matchRange.lowerBound
                let content = String(text[range])
                finalBlocks.append(ExtractedBlock(type: .markdownBlock, content: content, range: range))
            }

            // b. 处理当前匹配
            let content = String(text[matchRange])
            finalBlocks.append(ExtractedBlock(type: item.type, content: content, range: matchRange))
            
            lastIndex = matchRange.upperBound
        }

        // c. 追加最后一个匹配之后的所有剩余文本
        if lastIndex < text.endIndex {
            let range = lastIndex..<text.endIndex
            let content = String(text[range])
            finalBlocks.append(ExtractedBlock(type: .markdownBlock, content: content, range: range))
        }

        // 注意：我们不再需要 mergeAdjacentMixedContent，因为这个新逻辑已经正确处理了所有片段。
        return ExtractionResult(hasLatex: hasLatex, blocks: finalBlocks)
    }
    
    // MARK: - Private Implementation
    
    /*private static func fixAndWrapBlockLatex(_ rawBlock: String) -> String {
        var content = rawBlock
        if content.hasPrefix("$$") { content = String(content.dropFirst(2)) }
        if content.hasPrefix("\\[") { content = String(content.dropFirst(2)) }
        if content.hasSuffix("$$") { content = String(content.dropLast(2)) }
        if content.hasSuffix("\\]") { content = String(content.dropLast(2)) }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return "$$ " + trimmedContent.replacingOccurrences(of: "\n", with: " ") + " $$"
    }
    
    private static func mergeAdjacentMixedContent(in blocks: [ExtractedBlock]) -> [ExtractedBlock] {
        guard !blocks.isEmpty else { return [] }
        var merged: [ExtractedBlock] = []
        var currentContent = ""
        for block in blocks {
            if block.type == .markdownBlock {
                currentContent.append(block.content)
            } else {
                if !currentContent.isEmpty {
                    merged.append(ExtractedBlock(type: .markdownBlock, content: currentContent))
                    currentContent = ""
                }
                merged.append(block)
            }
        }
        if !currentContent.isEmpty {
            merged.append(ExtractedBlock(type: .markdownBlock, content: currentContent))
        }
        return merged
    }*/

    // 这是一个特殊的、几乎不可能在普通文本中出现的占位符
    private static let placeholderPrefix = "LATEX_PLACEHOLDER_6A8C5E7B_"
    
    // 用于存储被提取出来的 LaTeX 公式
    private static var latexCache: [String: String] = [:]
    
    private static var placeholderCounter = 0
    
    /// 预处理 Markdown 文本。
    /// 1. 提取所有 LaTeX 公式。
    /// 2. 用唯一的占位符替换它们。
    /// 3. 返回被“净化”过的 Markdown 文本和包含公式的缓存。
    static func preprocess(markdown: String) -> String {
        self.latexCache = [:]
        var processedText = ""
        
        let result = SimpleLatexExtractor.extract(from: markdown)
        
        for block in result.blocks {
            if block.type == .latexBlock {
                // 如果是 LaTeX 块，创建占位符并存入缓存
                var placeholder = "\(placeholderPrefix)\(placeholderCounter)"
                self.latexCache[placeholder] = block.content
                //if isBlockLatex(source: block.content) {
                    //placeholder = placeholder.trimmingCharacters(in: .whitespacesAndNewlines)
                    //placeholder = "\n\(placeholder)\n"
                //}
                //self.latexCache[placeholder] = block.content
                processedText.append(placeholder)
                placeholderCounter += 1
            } else {
                // 如果是普通 Markdown/代码块，直接追加
                processedText.append(block.content)
            }
        }
        
        return processedText
    }
    /*
    /// 一个简单的辅助函数，用于判断一个字符串是否是内联 LaTeX
    static private func isInlineLatex(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("$") && trimmed.hasSuffix("$") && !trimmed.hasPrefix("$$")) ||
               (trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)"))
    }
    
    static func recoverLatex(from textWithPlaceholders: String) -> String {
        // 如果缓存为空，或者文本不包含占位符前缀，说明无需处理，直接返回原字符串以提高效率。
        if latexCache.isEmpty || !textWithPlaceholders.contains(placeholderPrefix) {
            return textWithPlaceholders
        }
        
        var recoveredString = textWithPlaceholders
        
        // 遍历缓存中的每一个占位符和其对应的原始 LaTeX 公式
        for (placeholder, originalLatex) in latexCache {
            // 在整个字符串中，将占位符替换回原始的 LaTeX 公式
            recoveredString = recoveredString.replacingOccurrences(of: placeholder, with: originalLatex)
        }
        
        return recoveredString
    }*/
    
    static func renderTextWithLatex(from attributedInput: AttributedString, container: AttributeContainer) -> Text {
        var finalTextView = Text("")
        var currentIndex = attributedInput.startIndex

        //let placeholderPrefix = "LATEX_PLACEHOLDER_6A8C5E7B_"
        let regex = try! NSRegularExpression(pattern: "\(placeholderPrefix)\\d+")
        
        let plainString = String(attributedInput.characters)
        let matches = regex.matches(in: plainString, range: NSRange(plainString.startIndex..., in: plainString))
        
        var lastMatchEnd = attributedInput.startIndex
        
        for match in matches {
            guard let matchRange = Range(match.range, in: attributedInput) else { continue }
            
            // 1. 追加占位符之前的普通文本
            if matchRange.lowerBound > lastMatchEnd {
                // 【修复】: 将切片 AttributedSubstring 转换回 AttributedString
                let substring = attributedInput[lastMatchEnd..<matchRange.lowerBound]
                finalTextView = finalTextView + Text(AttributedString(substring))
            }
            
            // 2. 找到占位符，从缓存中恢复 LaTeX 并渲染
            let placeholderKey = String(attributedInput[matchRange].characters)
            if let latexString = latexCache[placeholderKey] {
                finalTextView = finalTextView + LatexView(latexString, container: container)
                //let placeholderSubstring = attributedInput[matchRange]
                //let latexContainer = placeholderSubstring.runs.first?.attributes ?? container
                //finalTextView = finalTextView + LatexView(latexString, container: latexContainer)
            } else {
                finalTextView = finalTextView + Text(placeholderKey).foregroundColor(.red)
            }
            
            lastMatchEnd = matchRange.upperBound
        }
        
        // 3. 追加最后一个占位符之后的文本
        if lastMatchEnd < attributedInput.endIndex {
            // 【修复】: 同样，将切片转换回 AttributedString
            let substring = attributedInput[lastMatchEnd...]
            finalTextView = finalTextView + Text(AttributedString(substring))
        }
        
        return finalTextView
    }
    
    private static func LatexView(_ source: String, container: AttributeContainer) -> Text {
        let fontSize = container.fontProperties?.size ?? 14
        let foregroundColor = container.foregroundColor ?? .primary
        let hasLatexBlock = isBlockLatex(source: source)
        //print("++++++++++++:\n\(source)\n")
        let mathImage = MTMathImage(
            latex: source,
            fontSize: fontSize,
            textColor: MTColor(foregroundColor),
            labelMode: hasLatexBlock ? .display : .text
          )
        
        //mathImage.font = MTFontManager.manager.xitsFont(withSize: fontSize)
        
        let (_, nsImage) = mathImage.asImage()
        guard let nsImage else {
            print("=========:\n\(source)\n")
          return Text(source)
        }

        var nsFont: NSFont
        let attributedString = NSAttributedString(AttributedString(" ", attributes: container))
        if let fontFromAttributes = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, fontFromAttributes.pointSize > 0 {
            nsFont = fontFromAttributes
        } else {
            nsFont = .systemFont(ofSize: NSFont.systemFontSize)
        }

        let imageHeight = nsImage.size.height
        let fontXHeight = nsFont.xHeight
        let offset = (imageHeight / 2.0) - (fontXHeight / 2.0)
        let baselineOffset = -offset
        
        let imageAsText = Text("\(Image(nsImage: nsImage))")
            .baselineOffset(baselineOffset)
        
        return hasLatexBlock ? Text("\n") + imageAsText + Text("\n"): imageAsText
        //return imageAsText
    }
    
    static private func isBlockLatex(source: String) -> Bool {
        // 1. 移除字符串首尾的所有空白字符（空格、换行符等）
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. 在处理过的、干净的字符串上进行判断
        if trimmedSource.hasPrefix("$$") && trimmedSource.hasSuffix("$$") {
            return true
        }
        
        if trimmedSource.hasPrefix("\\[") && trimmedSource.hasSuffix("\\]") {
            return true
        }
        
        return false
    }
    
    static func latexBlockNodeRule(blockNode: BlockNode) -> [BlockNode] {
        // 1. 检查节点是否为段落，且其中只有一个子节点，且该子节点为文本。
        guard case .paragraph(let children) = blockNode,
              children.count == 1,
              case .text(let placeholderKey) = children.first else {
            // 如果不满足，说明是普通段落或混合内容段落，原样返回。
            return [blockNode]
        }
        print("+++++++++\(placeholderKey)")
        // 2. 检查这个文本是否是我们的占位符。
        //    `.trimmingCharacters` 用于处理解析器可能在占位符前后加入的不可见空白。
        let trimmedKey = placeholderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.hasPrefix(placeholderPrefix) else {
            // 不是占位符，原样返回。
            print("========\(placeholderKey)")
            return [blockNode]
        }
        //print("========\(placeholderKey)")
        // 3. 从缓存中恢复原始的 LaTeX 字符串。
        guard let originalLatex = latexCache[trimmedKey] else {
            // 在缓存中找不到（理论上不应发生），作为错误处理，原样返回。
            return [blockNode]
        }
        print("--------\(originalLatex)")
        // 4. 判断恢复后的字符串是否是块级公式。
        if isBlockLatex(source: originalLatex) {
            // 是块级公式！
            // 创建并返回我们自定义的 LaTeX 块节点，
            // 注意：我们存储的是【原始的 LaTeX 内容】，而不是占位符！
            // 这样后续的渲染步骤就可以直接使用这个内容了。
            return [BlockNode.latexBlock(content: originalLatex)]
        } else {
            // 虽然是占位符，但它代表的是一个内联公式。
            // 我们不希望转换它，让它保持为段落，后续由 inline 规则处理。
            return [blockNode]
        }
    }
}
#else
// In: Sources/MarkdownUI/LaTeXRewriter.swift
import Foundation
import SwiftUI
import SwiftMath

// MARK: - Data Structures
enum BlockType {
    case markdownBlock
    case latexBlock
}

struct ExtractedBlock {
    let type: BlockType
    let content: String
}

struct ExtractionResult {
    let hasLatex: Bool
    let blocks: [ExtractedBlock]
}

// MARK: - SimpleLatexExtractor
final class SimpleLatexExtractor {

    // MARK: - State Management
    
    // 这是一个特殊的、几乎不可能在普通文本中出现的占位符前缀
    private static let placeholderBlockPrefix = "LATEX_BLOCK_PLACEHOLDER_6A8C5E7B_"
    private static let placeholderInlinePrefix = "LATEX_INLINE_PLACEHOLDER_6A8C5E7B_"
    
    // 用于存储被提取出来的 LaTeX 公式，键是占位符，值是原始 LaTeX 字符串
    private static var latexCache: [String: String] = [:]
    
    // 用于生成唯一的占位符ID
    private static var placeholderBlockCounter = 0
    private static var placeholderInlineCounter = 0
    
    // MARK: - Public API (The Main Workflow)

    /// **步骤 1: 预处理 Markdown 文本**
    /// 提取所有 LaTeX 公式，用唯一的占位符替换它们，并返回净化后的 Markdown 文本。
    /// 这个函数应该在将 Markdown 字符串传递给解析器之前调用。
    ///
    /// - Parameter markdown: 原始的、包含 LaTeX 的 Markdown 字符串。
    /// - Returns: 一个“净化”过的、所有 LaTeX 都被替换为占位符的字符串。
    /// **步骤 1: 预处理 Markdown 文本【终极简化版】**
        /// 直接在原始 Markdown 字符串上查找并替换所有 LaTeX 公式，无需独立的提取步骤。
        public static func preprocess(markdown: String) -> String {

            var processedText = markdown
            
            // --- 1. 定义正则表达式 ---
            let codeRegex = try! NSRegularExpression(pattern: #"`{3,}[\s\S]*?`{3,}|``[\s\S]*?``|`[^`]+?`"#, options: [])
            let latexRegex = try! NSRegularExpression(pattern:
                #"""
                (?smx) # s: '.' 匹配换行; m: '^'和'$'匹配行首行尾; x: 扩展模式
                # 块级公式
                ^\s* \$\$ [\s\S]*? \$\$ \s* $ |
                ^\s* \\\[ [\s\S]*? \\\] \s* $ |
                # 内联公式
                (?<![\\$])\$([^\n$]+?)\$(?!\$) |
                \\\( ([\s\S]*?) \\\)
                """#, options: [])

            // --- 2. 查找所有匹配 ---
            let fullRange = NSRange(markdown.startIndex..., in: markdown)
            let codeMatches = codeRegex.matches(in: markdown, range: fullRange)
            let latexMatches = latexRegex.matches(in: markdown, range: fullRange)

            // --- 3. 过滤掉在代码块内部的 LaTeX 公式 ---
            let codeRanges = codeMatches.map { $0.range }
            let validLatexMatches = latexMatches.filter { latexMatch in
                !codeRanges.contains { codeRange in
                    NSIntersectionRange(latexMatch.range, codeRange).length > 0
                }
            }
            
            // 如果没有有效的 LaTeX，直接返回
            guard !validLatexMatches.isEmpty else {
                return markdown
            }

            // --- 4. 【核心逻辑】从后向前替换，并根据公式类型决定替换内容 ---
            for (_, match) in validLatexMatches.enumerated().reversed() {
                guard let range = Range(match.range, in: processedText) else { continue }
                
                let originalLatex = String(processedText[range])
                
                if isBlockLatex(source: originalLatex) {
                    let placeholder = "\(placeholderBlockPrefix)\(placeholderBlockCounter)"
                    placeholderBlockCounter += 1
                    //print("++++++++\n\(placeholder)\n, \(originalLatex)\n")
                    self.latexCache[placeholder] = originalLatex
                    
                    // 1. 提取原始块的行首缩进
                    let indentation = getIndentation(of: range.lowerBound, in: processedText)
                    
                    // 2. 构建既保留缩进又强制分段的替换字符串
                    let replacementString = "\n\n" + indentation + placeholder + "\n\n"
                    
                    processedText.replaceSubrange(range, with: replacementString)
                } else {
                    let placeholder = "\(placeholderInlinePrefix)\(placeholderInlineCounter)"
                    placeholderInlineCounter += 1
                    //print("++++++++\n\(placeholder)\n, \(originalLatex)\n")
                    self.latexCache[placeholder] = originalLatex
                    
                    // 对于内联公式，直接替换
                    processedText.replaceSubrange(range, with: placeholder)
                }
            }

            //print("========\(processedText)")
            return processedText
        }


    /// **步骤 2: 自定义块级规则**
    /// 这个函数在 Markdown 解析后，作为自定义规则被调用。
    /// 它的职责是识别出代表“块级公式”的占位符段落，并将其转换为自定义的 `.latexBlock` 节点。
    ///
    /// - Parameter blockNode: Markdown 解析器生成的块节点。
    /// - Returns: 转换后的块节点数组。
    static func latexBlockNodeRule(blockNode: BlockNode) -> [BlockNode] {
        // 1. 检查节点是否为段落，且其中只有一个子节点，且该子节点为文本。
        //    这是识别出块级公式占位符的关键前提。
        //print("========\n\(blockNode)\n")
        guard case .paragraph(let children) = blockNode,
              children.count == 1,
              case .text(let placeholderKey) = children.first else {
            // 如果不满足，说明是普通段落或混合内容的段落（包含内联公式），原样返回。
            return [blockNode]
        }
        //print("--------\n\(blockNode)\n")
        // 2. 检查这个文本是否是我们的占位符。
        //    `.trimmingCharacters` 用于处理解析器可能在占位符前后加入的不可见空白。
        let trimmedKey = placeholderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.hasPrefix(placeholderBlockPrefix) else {
            // 不是占位符，原样返回。
            return [blockNode]
        }
        //print("++++++++\n\(placeholderKey)\n")
        // 3. 从缓存中恢复原始的 LaTeX 字符串。
        guard let originalLatex = latexCache[trimmedKey] else {
            // 在缓存中找不到（理论上不应发生），作为错误处理，原样返回。
            return [blockNode]
        }
        
        latexCache[trimmedKey] = nil
        return [BlockNode.latexBlock(content: originalLatex)]

    }

    /// **步骤 3: 渲染包含内联公式的文本**
    /// 当渲染一个段落的 AttributedString 时，调用此函数。
    /// 它会找到文本中的内联公式占位符，并将其替换为渲染好的 LaTeX 图像。
    ///
    /// - Parameters:
    ///   - attributedInput: 包含占位符的富文本字符串。
    ///   - container: 该文本的属性容器，用于获取字体大小、颜色等信息。
    /// - Returns: 一个组合了普通文本和 LaTeX 图像的 SwiftUI `Text` 视图。
    static func renderTextWithLatex(from attributedInput: AttributedString, container: AttributeContainer) -> Text {
        var finalTextView = Text("")
        //print("========\n\(attributedInput)\n")
        // 如果缓存为空或文本不含占位符，快速返回
        if latexCache.isEmpty || !String(attributedInput.characters).contains(placeholderInlinePrefix) {
            return Text(attributedInput)
        }
        
        let regex = try! NSRegularExpression(pattern: "\(placeholderInlinePrefix)\\d+")
        let plainString = String(attributedInput.characters)
        let matches = regex.matches(in: plainString, range: NSRange(plainString.startIndex..., in: plainString))
        
        var lastMatchEnd = attributedInput.startIndex
        //print("========\n\(attributedInput)\n")
        for match in matches {
            guard let matchRange = Range(match.range, in: attributedInput) else { continue }
            
            // a. 追加占位符之前的普通文本
            if matchRange.lowerBound > lastMatchEnd {
                let substring = attributedInput[lastMatchEnd..<matchRange.lowerBound]
                finalTextView = finalTextView + Text(AttributedString(substring))
            }
            
            // b. 找到占位符，从缓存中恢复 LaTeX 并渲染为图像
            let placeholderKey = String(attributedInput[matchRange].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            //print("========\n\(placeholderKey)\n, \n\(latexCache[placeholderKey])\n")
            if let latexString = latexCache[placeholderKey] {
                latexCache[placeholderKey] = nil
                // 使用占位符所在位置的文本属性来渲染 LaTeX
                //let runAttributes = attributedInput.runs[matchRange].attributes
                //print("========\n\(latexString)\n")
                finalTextView = finalTextView + LatexView(latexString, container: container)
            } else {
                // 如果找不到（异常情况），显示占位符本身并标红
                finalTextView = finalTextView + Text(placeholderKey).foregroundColor(.red)
            }
            
            lastMatchEnd = matchRange.upperBound
        }
        
        // c. 追加最后一个占位符之后的文本
        if lastMatchEnd < attributedInput.endIndex {
            let substring = attributedInput[lastMatchEnd...]
            finalTextView = finalTextView + Text(AttributedString(substring))
        }
        
        return finalTextView
    }
    
    // MARK: - Private Implementation
    /*
    /// 主提取函数：分离出 LaTeX 和普通 Markdown/代码块。
    private static func extract(from text: String) -> ExtractionResult {
        if text.isEmpty {
            return ExtractionResult(hasLatex: false, blocks: [])
        }
        //print("========\n\(text)\n")
        // 正则表达式:
        // 1. `codeRegex`: 匹配所有形式的代码块 (```, ``, ``)
        let codeRegex = try! NSRegularExpression(pattern: #"`{3,}[\s\S]*?`{3,}|``[\s\S]*?``|`[^`]+?`"#, options: [])
        // LaTeX 公式正则
        let latexRegex = try! NSRegularExpression(pattern:
            #"""
            (?smx) # s: '.' 匹配换行; m: '^'和'$'匹配行首行尾; x: 扩展模式
            # 块级公式
            ^\s* \$\$ [\s\S]*? \$\$ \s* $ |
            ^\s* \\\[ [\s\S]*? \\\] \s* $ |
            # 内联公式
            (?<![a-zA-Z0-9]|\\|\$) \$ ([^$]+?) \$ (?![a-zA-Z0-9]|\$) |
            \\\( ([\s\S]*?) \\\)
            """#, options: [])

        // 查找所有匹配
        let codeMatches = codeRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let latexMatches = latexRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // 过滤掉在代码块内部的 LaTeX 公式
        let codeRanges = codeMatches.map { $0.range }
        let validLatexMatches = latexMatches.filter { latexMatch in
            !codeRanges.contains { codeRange in
                NSIntersectionRange(latexMatch.range, codeRange).length > 0
            }
        }

        if validLatexMatches.isEmpty {
            return ExtractionResult(hasLatex: false, blocks: [ExtractedBlock(type: .markdownBlock, content: text)])
        }
        
        // 将所有有效匹配（代码+LaTeX）合并并按位置排序
        let allMatches = (codeMatches.map { (match: $0, type: BlockType.markdownBlock) } +
                          validLatexMatches.map { (match: $0, type: BlockType.latexBlock) })
            .sorted { $0.match.range.location < $1.match.range.location }

        // 构建最终的、包含所有文本片段的块列表
        var finalBlocks: [ExtractedBlock] = []
        var lastIndex = text.startIndex

        for item in allMatches {
            guard let matchRange = Range(item.match.range, in: text) else { continue }

            // a. 追加上一个匹配和当前匹配之间的普通文本
            if matchRange.lowerBound > lastIndex {
                let content = String(text[lastIndex..<matchRange.lowerBound])
                if !content.isEmpty {
                    finalBlocks.append(ExtractedBlock(type: .markdownBlock, content: content))
                }
            }

            // b. 处理当前匹配
            let content = String(text[matchRange])
            finalBlocks.append(ExtractedBlock(type: item.type, content: content))
            
            lastIndex = matchRange.upperBound
        }

        // c. 追加最后一个匹配之后的所有剩余文本
        if lastIndex < text.endIndex {
            let content = String(text[lastIndex..<text.endIndex])
            if !content.isEmpty {
                finalBlocks.append(ExtractedBlock(type: .markdownBlock, content: content))
            }
        }
        //print("========\n\(finalBlocks)\n")
        return ExtractionResult(hasLatex: true, blocks: finalBlocks)
    }
    */
    /// 辅助函数：将 LaTeX 字符串渲染为 SwiftUI 视图
    private static func LatexView(_ source: String, container: AttributeContainer) -> Text {
        let fontSize = container.fontProperties?.size ?? 14
        let foregroundColor = container.foregroundColor ?? .primary
        let isBlock = isBlockLatex(source: source)
        
        // 使用 SwiftMath 渲染 LaTeX
        let (_, nsImage) = MTMathImage(
          latex: source,
          fontSize: fontSize,
          textColor: MTColor(foregroundColor),
          labelMode: isBlock ? .display : .text
        ).asImage()

        guard let nsImage else {
          return Text(source) // 渲染失败则返回原始文本
        }

        // 计算基线偏移，使公式图像与周围文本对齐
        var nsFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
        if let fontFromAttributes = NSAttributedString(AttributedString(" ", attributes: container))
            .attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            nsFont = fontFromAttributes
        }

        let imageHeight = nsImage.size.height
        let fontXHeight = nsFont.xHeight
        let baselineOffset = -((imageHeight / 2.0) - (fontXHeight / 2.0))
        
        let imageAsText = Text("\(Image(nsImage: nsImage))")
            .baselineOffset(baselineOffset)
        
        // 块级公式前后添加换行符以产生间距
        return isBlock ? Text("\n") + imageAsText + Text("\n") : imageAsText
    }
    
    /// 辅助函数：判断一个 LaTeX 字符串是否为块级公式
    static private func isBlockLatex(source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$")) ||
               (trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]"))
    }
    
    /// 【新增辅助函数】获取一个字符串块的行首缩进
    private static func getIndentation(of index: String.Index, in text: String) -> String {
        // 找到该位置所在行的开始
        let lineStart = text.lineRange(for: index..<index).lowerBound
        
        // 找到该行第一个非空白字符的位置
        if let firstNonWhitespace = text[lineStart...].firstIndex(where: { !$0.isWhitespace }) {
            // 返回从行首到该位置的子字符串
            return String(text[lineStart..<firstNonWhitespace])
        }
        
        // 如果整行都是空白，则返回整行（保留所有空格）
        return String(text[lineStart...])
    }

    private static func resetLatecCache() {
        //latexCache = [:]
        //placeholderCounter = 0
    }
}
#endif
