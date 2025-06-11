// In: Sources/MarkdownUI/LaTeXRewriter.swift
import Foundation
import SwiftUI
import SwiftMath

// 规则 2: 将文本节点中的行内 LaTeX 重写为行内 LaTeX 节点
// (无需修改，因为它依赖的 parseMixedContentLine 已支持)
func latexInlineRule(inline: InlineNode) -> [InlineNode] {
    guard case .text(let text) = inline else {
        return [inline]
    }
    //print("++++++++++++:\n\(text)\n")
    if !text.contains("$")
        && !text.contains("\\(")
        && !text.contains("\\[")
        && !text.contains("$$") {
        return [inline]
    }
    
    let segmentsInLines = parseMixedContentLine(text)
    if segmentsInLines.count <= 1 && segmentsInLines.first?.isLatex == false {
        return [inline]
    }
    
    var newInlines: [InlineNode] = []
    for segment in segmentsInLines {
        print("++++++++++++:\n\(segment.content)\n")
        if segment.isLatex {
            let content = fixLatexSyntax(in: segment.content)
            newInlines.append(.latex(content: content))
            //print("----------:\n\(content)\n")
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
    let environments = ["pmatrix", "bmatrix", "vmatrix", "matrix", "cases", "align", "align*"]
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
    
    // --- 修复2.5: (安全版) 恢复 LaTeX 中常见的未转义字符，例如 %, # ---
    // 策略: 1. 隔离 \text{...} 块。 2. 在外部进行转义。 3. 恢复 \text{...} 块。
    
    var protectedBlocks: [String] = []
    var mutableText = text
    
    // 步骤 1: 识别并用占位符替换 \text{...} 等“安全区”
    let protectionRegex = try! NSRegularExpression(pattern: #"\\text\s*\{[^}]*\}"#)
    let protectionMatches = protectionRegex.matches(in: mutableText, range: NSRange(mutableText.startIndex..., in: mutableText))
    
    for match in protectionMatches.reversed() {
        guard let range = Range(match.range, in: mutableText) else { continue }
        
        let originalBlock = String(mutableText[range])
        let placeholder = "__PROTECTED_BLOCK_\(protectedBlocks.count)__"
        
        protectedBlocks.append(originalBlock)
        mutableText.replaceSubrange(range, with: placeholder)
    }
    protectedBlocks.reverse() // 恢复正确的顺序

    // 步骤 2: 在被“净化”过的字符串上执行转义
    // 注意：只转义 % 和 #。& 和 _ 有结构性作用，由其他修复步骤处理更佳。
    let latexSpecials = ["%", "#"]
    for symbol in latexSpecials {
        let pattern = #"(?<!\\)"# + NSRegularExpression.escapedPattern(for: symbol)
        let regex = try! NSRegularExpression(pattern: pattern)
        mutableText = regex.stringByReplacingMatches(
            in: mutableText,
            range: NSRange(mutableText.startIndex..., in: mutableText),
            withTemplate: "\\\\" + symbol // 替换模板需要 `\\` 来表示一个字面量 `\`
        )
    }
    
    // 步骤 3: 将被保护的块恢复原状
    if !protectedBlocks.isEmpty {
        for (index, originalBlock) in protectedBlocks.enumerated() {
            let placeholder = "__PROTECTED_BLOCK_\(index)__"
            mutableText = mutableText.replacingOccurrences(of: placeholder, with: originalBlock, options: .literal)
        }
    }
    
    text = mutableText // 将修复后的文本赋回
    
    // --- 修复3: 确保矩阵中的 `&` 符号周围有空格 ---
    let tightAlignRegex = try! NSRegularExpression(pattern: #"(\S)&(\S)"#)
    text = tightAlignRegex.stringByReplacingMatches(
        in: text,
        range: NSRange(text.startIndex..., in: text),
        withTemplate: "$1 & $2"
    )
    
    // --- 修复4: 为悬空的下标/上标自动添加花括号 ---
    // 例如：x_12 -> x_{12}, y^ab -> y^{ab}
    let danglingSubscriptRegex = try! NSRegularExpression(pattern: #"([_^])\s*([^{}\s\\][^\s{}]*)"#)
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

    // --- 使用了命名捕获组的、健壮的正则表达式 ---
    let combinedRegex = try! NSRegularExpression(pattern:
        #"""
        (?sx) # s: '.' 匹配换行符; x: 扩展模式，允许注释

        # --- 1. 命名捕获组 'CODE': 匹配所有代码块 (规则已优化) ---
        (?<CODE>
            # a. 围栏代码块 (最优先，最明确)
            `{3,} .*? \n [\s\S]*? \n \s* `{3,}
            |
            # b. 双反引号内联代码 (允许内部有单个反引号)
            `` .+? ``
            |
            # c. 单反引号内联代码 (必须优先于LaTeX匹配)
            #    [^`]+ 匹配一个或多个非反引号字符，这是贪婪的。
            `[^`]+`
        )

        | # --- 或者 ---

        # --- 2. 命名捕获组 'LATEX': 匹配所有 LaTeX 公式 (保持不变) ---
        (?<LATEX>
            # a. 块级公式
            \$\$ [\s\S]*? \$\$
            |
            \\\[ [\s\S]*? \\\]
            
            | # 或
            
            # b. 内联公式 (带防御条件)
            (?<!\$|\\) \$ (?: \\. | [^\$\\] )+? \$ (?!\$)
            
            | # 或
            
            # c. 另一种内联形式
            \\\( .*? \\\)
        )
        """#, options: [])
    
    let matches = combinedRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
    
    for match in matches {
        guard let matchRange = Range(match.range, in: line) else { continue }
        
        // 追加上一个匹配和当前匹配之间的普通文本
        if matchRange.lowerBound > currentIndex {
            let textSegment = String(line[currentIndex..<matchRange.lowerBound])
            segments.append((isLatex: false, content: textSegment))
        }
        
        // --- 【核心修复】: 检查哪个命名组匹配成功 ---
        let content = String(line[matchRange])
        
        // 检查 'CODE' 组是否有匹配
        if match.range(withName: "CODE").location != NSNotFound {
            // 如果是代码块，标记为 isLatex: false
            segments.append((isLatex: false, content: content))
        }
        // 检查 'LATEX' 组是否有匹配
        else if match.range(withName: "LATEX").location != NSNotFound {
            // 如果是 LaTeX 公式，标记为 isLatex: true
            segments.append((isLatex: true, content: content))
        }
        
        // 更新当前索引
        currentIndex = matchRange.upperBound
    }
    
    // 追加最后一个匹配之后的所有剩余文本
    if currentIndex < line.endIndex {
        segments.append((isLatex: false, content: String(line[currentIndex...])))
    }
    
    if segments.isEmpty && !line.isEmpty {
        segments.append((isLatex: false, content: line))
    }
    
    return segments.filter { !$0.content.isEmpty }
}

func LatexView(_ source: String, att: AttributeContainer) -> Text {
    let fontSize = att.fontProperties?.size ?? 14
    let foregroundColor = att.foregroundColor ?? .primary
    let hasLatexBlock = source.hasPrefix("$$") && source.hasSuffix("$$")
    
    let (_, nsImage) = MTMathImage(
      latex: source,
      fontSize: fontSize,
      textColor: MTColor(foregroundColor),
      labelMode: hasLatexBlock ? .display : .text
    ).asImage()

    guard let nsImage else {
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

func renderLatexInText(from attributedInput: AttributedString, container: AttributeContainer) -> Text {
    var finalTextView = Text("")
    var currentIndex = attributedInput.startIndex

    // 循环处理，直到字符串末尾
    while currentIndex < attributedInput.endIndex {
        
        // 【修改 1】: 先创建切片，再在切片上搜索，以修复编译错误
        let searchView = attributedInput[currentIndex...]
        guard let openRange = searchView.range(of: "$") else {
            // 如果在剩余部分找不到 "$$"，说明剩下都是普通文本
            let remainingPart = AttributedString(attributedInput[currentIndex...])
            if !remainingPart.characters.isEmpty {
                finalTextView = finalTextView + Text(remainingPart)
            }
            break // 结束循环
        }
        
        // 追加 "$$" 之前的普通文本部分
        let plainTextPart = AttributedString(attributedInput[currentIndex..<openRange.lowerBound])
        if !plainTextPart.characters.isEmpty {
            finalTextView = finalTextView + Text(plainTextPart)
        }
        
        // 从第一个 "$$" 之后开始，寻找与之配对的闭合 "$$"
        let searchStartForClose = openRange.upperBound
        
        // 【修改 2】: 对闭合的 "$$" 也使用相同的切片搜索方法
        let searchViewForClose = attributedInput[searchStartForClose...]
        guard let closeRange = searchViewForClose.range(of: "$") else {
            // 找到了开头的 "$$"，但没有找到闭合的
            let remainingPart = AttributedString(attributedInput[openRange.lowerBound...])
            if !remainingPart.characters.isEmpty {
                finalTextView = finalTextView + Text(remainingPart)
            }
            break // 结束循环
        }
        
        // 成功找到一对 "$$"，提取并渲染 LaTeX 公式
        let latexContentRange = searchStartForClose..<closeRange.lowerBound
        let latexPart = AttributedString(attributedInput[latexContentRange])
        
        if !latexPart.characters.isEmpty {
            // 提取纯文本内容
            let rawLatexString = String(latexPart.characters)
            
            // 【修改 3 - 逻辑修复】: 获取公式所在位置的局部属性，而不是使用全局的 container
            // 这样可以确保每个公式都用它自己的样式渲染
            //let localAttributes = attributedInput.attributes(at: latexContentRange.lowerBound)
            
            // 使用局部属性调用 LatexView
            finalTextView = finalTextView + LatexView(rawLatexString, att: container)
        }
        
        // 更新下一次循环的起始位置
        currentIndex = closeRange.upperBound
    }
    
    return finalTextView
}
