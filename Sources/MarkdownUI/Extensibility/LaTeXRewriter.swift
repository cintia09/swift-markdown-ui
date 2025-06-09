// In: Sources/MarkdownUI/LaTeXRewriter.swift
import Foundation

// 规则 1: 将代码块或包含块级 LaTeX 的段落进行分割和重写
@MainActor // 确保你的 LatexExtractor.parseSegments 是在主线程调用
func latexBlockRule(block: BlockNode) -> [BlockNode] {
    #if true
    guard case .paragraph(let children) = block,
          children.count == 1,
          case .text(let text) = children.first else {
        return [block]
    }

    let segments = LatexExtractor.parseSegments(text)
    
    var result: [BlockNode] = []
    
    for segment in segments {
        switch segment.type {
        case .latexBlock:
            result.append(.latexBlock(content: segment.content))
        case .markdown, .mixedContent:
            let inline = InlineNode.text(segment.content)
            result.append(.paragraph(content: [inline]))
        case .codeBlock:
            result.append(.codeBlock(fenceInfo: nil, content: segment.content))
        }
    }
    
    return result.isEmpty ? [block] : result
    #else
    // Case A: 处理 ```latex ... ``` 代码块 (保持不变)
    //if case .codeBlock(let fenceInfo, let content) = block,
    //   let info = fenceInfo?.lowercased(), ["latex", "math"].contains(info) {
    //    return [.latexBlock(content: content)]
    //}
    
    // Case B: 处理可能包含块级 LaTeX 的段落
    // cmark 会把一个复杂的段落解析成一系列 InlineNode，但如果段落内没有其他行内格式，
    // 通常会是一个大的 .text 节点。我们直接处理这个 .text 节点。
    //print("---------latexBlock:\n\(block)")
    guard case .paragraph(let children) = block else {
        // 如果不是段落，直接返回
        return [block]
    }
    
    //print("---------latexBlock:\n\(block)")
    // 我们需要将段落的行内节点重新拼接成一个字符串，再交给你的 Extractor
    let paragraphText = children.map { inlineNode -> String in
        // 这里需要一个简单的函数将 InlineNode 转换回其 Markdown 表示
        return inlineNode.renderPlainText() // MarkdownUI 应该有类似的方法
    }.joined()
    print("\n---------latexBlockRule:\n\n\(paragraphText)\n")
    // --- 核心逻辑开始 ---

    // 1. 使用你的顶层解析器来分割这个段落的文本
    let segments = LatexExtractor.parseSegments(paragraphText)
    
    // 2. 如果分割后只有一个块，并且不是 LaTeX 块，说明这个段落很普通，无需处理
    if segments.count <= 1 && segments.first?.type != .latexBlock {
        //print("---------latexBlock:\n\(block)")
        return [block] // 返回原始的段落节点
    }
    //print("+++++++++++=latexBlockRule:\n\(block)")
    // 3. 如果有多个块，或者唯一的块是 LaTeX 块，我们需要进行转换
    let newBlocks: [BlockNode] = segments.flatMap { segment -> [BlockNode] in
        switch segment.type {
        
        case .latexBlock:
            // 提取出的 LaTeX 块直接转换为 .latexBlock 节点
            print("==========latexBlock:\n\(segment.content)")
            return [.latexBlock(content: segment.content)]
            
        case .markdown, .mixedContent, .codeBlock:
            // 提取出的其他文本（原本是 LaTeX 块前后的部分），
            // 我们需要把它们重新包装成 .paragraph 节点。
            // 并且，这些文本可能包含行内公式，所以我们需要对它们再次进行行内解析。
            
            // a. 先用 cmark 把这段文本解析成最基本的行内节点
            let inlineNodes = Array<InlineNode>(markdown: segment.content)
            
            // b. 再对这些行内节点应用行内 LaTeX 规则
            let rewrittenInlines = (try? inlineNodes.rewrite(latexInlineRule)) ?? inlineNodes
            
            // c. 如果有内容，就创建一个新的段落
            if !rewrittenInlines.isEmpty {
                return [.paragraph(content: rewrittenInlines)]
            } else {
                return []
            }
        }
    }
    
    return newBlocks
    #endif
}

// 为了让上面的代码工作，我们需要一个将 [InlineNode] 转换为纯文本的方法
// MarkdownUI 内部有这个功能，我们来模拟一下
extension InlineNode {
    // 这是一个简化的版本，实际的 renderPlainText 可能更复杂
    func renderPlainText() -> String {
        switch self {
        case .text(let string), .code(let string), .html(let string):
            return string
        case .softBreak:
            return " "
        case .lineBreak:
            return "\n"
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return children.map { $0.renderPlainText() }.joined()
        case .link(_, let children), .image(_, let children):
            return children.map { $0.renderPlainText() }.joined()
        case .latex(let content):
            return "$\(content)$" // 逆向转换
        }
    }
}

// 还需要一个从字符串直接到 [InlineNode] 的解析器
extension Array where Element == InlineNode {
    init(markdown: String) {
        // 我们通过创建一个临时的段落块来提取其行内内容
        let blocks = Array<BlockNode>(markdown: markdown)
        if let firstBlock = blocks.first, case .paragraph(let content) = firstBlock, blocks.count == 1 {
            self = content
        } else {
            // 如果解析结果不是一个单一的段落，可能需要更复杂的处理
            // 但对于从段落中分割出的小文本片段，这通常足够了
            self = [.text(markdown)]
        }
    }
}

// 规则 2: 将文本节点中的行内 LaTeX 重写为行内 LaTeX 节点
// (无需修改，因为它依赖的 parseMixedContentLine 已支持)
func latexInlineRule(inline: InlineNode) -> [InlineNode] {
    guard case .text(let text) = inline else {
        return [inline]
    }
    
    if !text.contains("$") && !text.contains("\\") {
        return [inline]
    }
    
    let segments = LatexExtractor.parseMixedContentLine(text)
    
    if segments.count <= 1 && segments.first?.isLatex == false {
        return [inline]
    }
    
    var newInlines: [InlineNode] = []
    for segment in segments {
        if segment.isLatex {
            //let latexContent = stripLatexDelimiters(from: segment.content)
            newInlines.append(.latex(content: segment.content))
        } else {
            newInlines.append(.text(segment.content))
        }
    }
    
    return newInlines
}

// 辅助函数 (无需修改)
private func stripLatexDelimiters(from rawLatex: String) -> String {
    let trimmed = rawLatex.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("$") && trimmed.hasSuffix("$") && !trimmed.hasPrefix("$$") {
        return String(trimmed.dropFirst().dropLast())
    }
    if trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)") {
        return String(trimmed.dropFirst(2).dropLast(2))
    }
    if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") {
        return String(trimmed.dropFirst(2).dropLast(2))
    }
    if trimmed.hasPrefix("\\[") && trimmed.hasSuffix("\\]") {
        return String(trimmed.dropFirst(2).dropLast(2))
    }
    return rawLatex
}
