#if false
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
    private static var placeholderCodeBlockPrefix = "__CODE_BLOCK_PLACEHOLDER_"
    
    // 用于存储被提取出来的 LaTeX 公式，键是占位符，值是原始 LaTeX 字符串
    private static var latexCache: [String: String] = [:]
    
    // 用于生成唯一的占位符ID
    private static var placeholderBlockCounter = 0
    private static var placeholderInlineCounter = 0
    
    // MARK: - Public API (The Main Workflow)

    /// **步骤 1: 预处理 Markdown 文本**
    /// 提取所有 LaTeX 公式，用唯一的占位符替换它们，并返回净化后的 Markdown 文本。
    /// 这个函数应该在将 Markdown 字符串传递给解析器之前调用。
    /*public static func preprocess(markdown: String) -> String {
        //print("--- DEBUG: Preprocessing input ---\n\(markdown)\n---------------------------------")
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
        //print("--- DEBUG: Preprocessing latexMatches ---\n\(latexMatches)\n---------------------------------")
        // --- 3. 过滤掉在代码块内部的 LaTeX 公式 ---
        let codeRanges = codeMatches.map { $0.range }
        let validLatexMatches = latexMatches.filter { latexMatch in
            !codeRanges.contains { codeRange in
                NSIntersectionRange(latexMatch.range, codeRange).length > 0
            }
        }
        //print("--- DEBUG: Preprocessing validLatexMatches ---\n\(validLatexMatches)\n---------------------------------")
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
    }*/

    static func preprocess(markdown: String) -> String {
        var placeholdercodeBlockCounter = 0
        var codeBlockCache: [String: String] = [:]

        var processedText = markdown
        
        let codeRegex = try! NSRegularExpression(
            pattern: #"""
            # 围栏式代码块
            ^ \s* (?<fence>`{3,}|~{3,}) .*? \n [\s\S]+? \n \s* \k<fence> \s* $
            |
            # 行内代码，双反引号
            `` [^`\n]*? ``
            |
            # 行内代码，单反引号
            # 关键修复：内容不能以 $ 开头，也不能以 $ 结尾
            # 这可以防止它匹配到 `$code$` 这种会被误认为 LaTeX 的情况
            `
            (?!\$)  # 不能以 $ 开头
            [^`\n]+? # 内容
            (?<!\$) # 不能以 $ 结尾
            `
            """#,
            options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
        )
        
        // 你的 latexRegex 已经很好了，我们继续使用它
        let latexRegex = try! NSRegularExpression(
            pattern: #"""
            # x: 扩展/注释模式 (通过 .allowCommentsAndWhitespace 启用)
            # s: '.' 匹配换行 (通过 .dotMatchesLineSeparators 启用)
            # m: '^' 匹配行首 (通过 .anchorsMatchLines 启用)

            # 块级公式 (匹配独占一行的 $$...$$ 或 \[...\])
            (?:(?<=^|\n)\s*)
            (
              \$\$ .+? \$\$ |
              \\\[ .+? \\\]
            ) |
            # 内联公式 (匹配 $...$ 或 \(...\) 但避免匹配 $$)
            (?<!\$)\$ ([^\$\n]+) \$(?!\$) |
            \\\( .+? \\\)
            """#,
            options: [
                .allowCommentsAndWhitespace, // 正确的选项，用于开启注释和自由空格模式
                .anchorsMatchLines,          // 使得 ^ 和 $ 匹配行的开始和结束
                .dotMatchesLineSeparators    // 使得 '.' 可以匹配换行符
            ]
        )

        // --- 2. 查找所有匹配并过滤（与原来相同）---
        let fullRange = NSRange(markdown.startIndex..., in: markdown)
        let codeMatches = codeRegex.matches(in: markdown, range: fullRange)
        let latexMatches = latexRegex.matches(in: markdown, range: fullRange)
        
        let codeRanges = codeMatches.map { $0.range }
        
        // ==================【 添加这段决定性的调试代码 】==================
        //print("--- DEBUG: TOTAL CODE BLOCKS FOUND: \(codeMatches.count) ---")
        for (index, codeMatch) in codeMatches.enumerated() {
            let codeString = (markdown as NSString).substring(with: codeMatch.range)
            // 只打印较短的代码块，避免日志过长
            if codeString.count < 200 {
                print("Code Block \(index) (\(codeMatch.range)): \(codeString)")
            } else {
                print("Code Block \(index) (\(codeMatch.range)): [Content too long, length: \(codeString.count)]")
            }
        }
        // =============================================================
        
        let validLatexMatches = latexMatches.filter { latexMatch in
            !codeRanges.contains { codeRange in
                NSIntersectionRange(latexMatch.range, codeRange).length > 0
            }
        }
        //print("--- DEBUG: Preprocessing latexMatches ---\n\(latexMatches)\n---------------------------------")
        //print("--- DEBUG: Preprocessing validLatexMatches ---\n\(validLatexMatches)\n---------------------------------")
        guard !validLatexMatches.isEmpty else {
            return markdown
        }

        // --- 3. 【核心逻辑优化】从后向前替换，使用 Parser 进行分类 ---
        for match in validLatexMatches.reversed() {
            guard let range = Range(match.range, in: processedText) else { continue }
            
            let originalLatex = String(processedText[range])
            
            // **【新变化】在这里使用 Parser 来分析匹配到的内容**
            let components: [Component] = Parser.parse(originalLatex.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // 一个有效的公式匹配应该只解析出一个组件
            guard components.count == 1, let component = components.first, component.type.isEquation else {
                // 如果 Parser 认为这不是一个单一、有效的公式，就跳过它
                // 这增加了代码的健壮性，防止正则表达式的误匹配
                continue
            }
            
            // **【新变化】使用 component.type.inline 来判断公式类型**
            if !component.type.inline { // 这是块级公式
                let placeholder = "\(placeholderBlockPrefix)\(placeholderBlockCounter)"
                placeholderBlockCounter += 1
                
                // 使用组件的 originalText 来缓存，确保是纯净的公式文本
                self.latexCache[placeholder] = component.originalText
                
                // 【保留的逻辑】这里的缩进处理完全复用你原来的代码，因为它依赖于 range
                // 1. 提取原始块的行首缩进
                let indentation = getIndentation(of: range.lowerBound, in: processedText)
                
                // 2. 构建既保留缩进又强制分段的替换字符串
                let replacementString = "\n\n" + indentation + placeholder + "\n\n"
                
                processedText.replaceSubrange(range, with: replacementString)
                
            } else { // 这是内联公式
                let placeholder = "\(placeholderInlinePrefix)\(placeholderInlineCounter)"
                placeholderInlineCounter += 1
                
                self.latexCache[placeholder] = component.originalText
                
                // 对于内联公式，直接替换
                processedText.replaceSubrange(range, with: placeholder)
            }
        }

        return processedText
    }

    /// **步骤 2: 自定义块级规则**
    /// 这个函数在 Markdown 解析后，作为自定义规则被调用。
    /// 它的职责是识别出代表“块级公式”的占位符段落，并将其转换为自定义的 `.latexBlock` 节点。
    ///
    /// - Parameter blockNode: Markdown 解析器生成的块节点。
    /// - Returns: 转换后的块节点数组。
    /*static func latexBlockNodeRule(blockNode: BlockNode) -> [BlockNode] {
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
        
        //latexCache[trimmedKey] = nil
        return [BlockNode.latexBlock(content: originalLatex)]

    }*/

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
                //latexCache[placeholderKey] = nil
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

    /// 辅助函数：将 LaTeX 字符串渲染为 SwiftUI 视图
    static func LatexView(_ source: String, container: AttributeContainer) -> Text {
        let fontSize = container.fontProperties?.size ?? 14
        let foregroundColor = container.foregroundColor ?? .primary
        let isBlock = isBlockLatex(source: source)
        //print("---------\n\(source)\n")
        /*let source = """
         $\nabla a \mathbf{E} = \frac{\rho}{\epsilon_0}$
        """*/
        // 使用 SwiftMath 渲染 LaTeX
        let (_, nsImage) = MTMathImage(
          latex: source,
          fontSize: fontSize,
          textColor: MTColor(foregroundColor),
          labelMode: isBlock ? .display : .text,
          textAlignment: .center
        ).asImage()

        guard let nsImage else {
            print("---------\n\(source) failed\n")
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
        //return isBlock ? Text("\n") + imageAsText + Text("\n") : imageAsText
        return imageAsText
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
}

struct LatexBlockView: View {
    @Environment(\.textStyle) var textStyle
    
    private var attributes: AttributeContainer {
      var attributes = AttributeContainer()
      self.textStyle._collectAttributes(in: &attributes)
      return attributes
    }
    
    let latexString: String
    
    var body: some View {
        HStack {
            Spacer()
            SimpleLatexExtractor.LatexView(latexString, container: attributes)
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 10)
    }
}


/// A block of components.
struct ComponentBlock: Hashable, Identifiable {
  
  /// The component's identifier.
  ///
  /// Unique to every instance.
  let id = UUID()
  
  /// The block's components.
  let components: [Component]
  
  /// True iff this block has only one component and that component is
  /// not inline.
  var isEquationBlock: Bool {
    components.count == 1 && !components[0].type.inline
  }
}

/// A LaTeX component.
struct Component: CustomStringConvertible, Equatable, Hashable {
  
  /// A LaTeX component type.
  enum ComponentType: String, Equatable, CustomStringConvertible {
    
    /// A text component.
    case text
    
    /// An inline equation component.
    ///
    /// - Example: `$x^2$`
    case inlineEquation
    
    /// An inline equation component.
    ///
    /// - Example: `\(x^2\)`
    case inlineParenthesesEquation
    
    /// A TeX-style block equation.
    ///
    /// - Example: `$$x^2$$`.
    case texEquation
    
    /// A block equation.
    ///
    /// - Example: `\[x^2\]`
    case blockEquation
    
    /// A named equation component.
    ///
    /// - Example: `\begin{equation}x^2\end{equation}`
    case namedEquation
    
    /// A named equation component.
    ///
    /// - Example: `\begin{equation*}x^2\end{equation*}`
    case namedNoNumberEquation
    
    /// The component's description.
    var description: String {
      rawValue
    }
    
    /// The order we should scan components when parsing.
    static let order: [ComponentType] = [
      .namedNoNumberEquation,
      .namedEquation,
      .blockEquation,
      .texEquation,
      .inlineEquation,
      .inlineParenthesesEquation
    ]
    
    /// The component's left terminator.
    var leftTerminator: String? {
      switch self {
      case .text: return nil
      case .inlineEquation: return "$"
      case .inlineParenthesesEquation: return "\\("
      case .texEquation: return "$$"
      case .blockEquation: return "\\["
      case .namedEquation: return "\\begin{equation}"
      case .namedNoNumberEquation: return "\\begin{equation*}"
      }
    }
    
    /// The component's right terminator.
    var rightTerminator: String? {
      switch self {
      case .text: return nil
      case .inlineEquation: return "$"
      case .inlineParenthesesEquation: return "\\)"
      case .texEquation: return "$$"
      case .blockEquation: return "\\]"
      case .namedEquation: return "\\end{equation}"
      case .namedNoNumberEquation: return "\\end{equation*}"
      }
    }
    
    /// Whether or not this component is inline.
    var inline: Bool {
      switch self {
      case .text, .inlineEquation, .inlineParenthesesEquation: return true
      default: return false
      }
    }
    
    /// True iff the component is not `text`.
    var isEquation: Bool {
      return self != .text
    }
  }
  
  /// The component's inner text.
  let text: String
  
  /// The component's type.
  let type: ComponentType
  
  /// The original input text that created this component.
  var originalText: String {
    "\(type.leftTerminator ?? "")\(text)\(type.rightTerminator ?? "")"
  }
  
  /// The component's original text with newlines trimmed.
  var originalTextTrimmingNewlines: String {
    originalText.trimmingCharacters(in: .newlines)
  }
  
  /// The component's description.
  var description: String {
    return "(\(type), \"\(text)\")"
  }
  
  // MARK: Initializers
  
  /// Initializes a component.
  ///
  /// The text passed to the component is stripped of the left and right
  /// terminators defined in the component's type.
  ///
  /// - Parameters:
  ///   - text: The component's text.
  ///   - type: The component's type.
  init(text: String, type: ComponentType) {
    if type.isEquation {
      var text = text
      if let leftTerminator = type.leftTerminator, text.hasPrefix(leftTerminator) {
        text = String(text[text.index(text.startIndex, offsetBy: leftTerminator.count)...])
      }
      if let rightTerminator = type.rightTerminator, text.hasSuffix(rightTerminator) {
        text = String(text[..<text.index(text.endIndex, offsetBy: -rightTerminator.count)])
      }
      self.text = text
    }
    else {
      self.text = text
    }
    
    self.type = type
  }
  
}

/// Parses text for LaTeX equations.
class Parser {
  
  /// Parses the input text for component blocks.
  ///
  /// - Parameters:
  ///   - text: The input text.
  /// - Returns: An array of component blocks.
  static func parse(_ text: String) -> [ComponentBlock] {
    let components: [Component] = parse(text)
    var blocks = [ComponentBlock]()
    var blockComponents = [Component]()
    for component in components {
      if component.type.inline {
        blockComponents.append(component)
      } else {
        blocks.append(ComponentBlock(components: blockComponents))
        blocks.append(ComponentBlock(components: [component]))
        blockComponents.removeAll()
      }
    }
    if !blockComponents.isEmpty {
      blocks.append(ComponentBlock(components: blockComponents))
    }
    return blocks
  }
  
  /// Parses the input text in to components.
  ///
  /// - Parameter input: The input text.
  /// - Returns: An array of components.
  static func parse(_ input: String) -> [Component] {
    var components: [Component] = []
    var stack = [Component.ComponentType]()
    var index = input.startIndex
    var startIndex = index
    var endIndex = index
    
    inputLoop: while index < input.endIndex {
      let remaining = input[index...]
      
      if !stack.isEmpty {
        for type in Component.ComponentType.order {
          guard let end = type.rightTerminator else { continue }
          if remaining.hasPrefix(end) {
            if index > input.startIndex && input[input.index(before: index)] == "\\" {
              index = input.index(index, offsetBy: end.count)
              continue inputLoop
            }
            
            let previousEndIndex = endIndex
            endIndex = input.index(index, offsetBy: end.count)

            if stack.last == type {
              let lastType = stack.removeLast()
              if stack.isEmpty {
                if previousEndIndex < startIndex {
                  components.append(Component(text: String(input[previousEndIndex..<startIndex]), type: .text))
                }
                
                components.append(Component(text: String(input[startIndex..<endIndex]), type: lastType))
              }
            }
            index = endIndex
            continue inputLoop
          }
        }
      }
      
      for type in Component.ComponentType.order {
        guard let start = type.leftTerminator else { continue }
        if remaining.hasPrefix(start) {
          if index > input.startIndex && input[input.index(before: index)] == "\\" {
            index = input.index(index, offsetBy: start.count)
            continue inputLoop
          }
          
          if stack.isEmpty {
            startIndex = index
          }
          
          stack.append(type)
          index = input.index(index, offsetBy: start.count)
          continue inputLoop
        }
      }
      
      index = input.index(after: index)
    }
    
    if endIndex < index {
      components.append(Component(text: String(input[endIndex..<index]), type: .text))
    }
    
    return components
  }
}
#endif
