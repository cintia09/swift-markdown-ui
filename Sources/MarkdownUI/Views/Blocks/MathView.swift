//
//  MathView.swift
//  swift-markdown-ui
//
//  Created by mingdw on 2025/6/8.
//

import SwiftUI
import SwiftMath

// 使用 #if os(macOS) 来区分平台
#if os(macOS)

// MARK: - macOS Implementation
struct MathView: NSViewRepresentable {
    @Environment(\.textStyle) var textStyle
    
    private var attributes: AttributeContainer {
      var attributes = AttributeContainer()
      self.textStyle._collectAttributes(in: &attributes)
      return attributes
    }
    
    var equation: String
    var font: MathFont = .latinModernFont
    var textAlignment: MTTextAlignment = .center
    var fontSize: CGFloat = 14
    var labelMode: MTMathUILabelMode = .display
    var insets: MTEdgeInsets = MTEdgeInsets()
    var textColor = MTColor(.primary)
    
    /*init(equation: String, font: MathFont = .latinModernFont, textAlignment: MTTextAlignment = .center, fontSize: CGFloat = 14, labelMode: MTMathUILabelMode = .display, insets: MTEdgeInsets = .zero, textColor: Color = .primary) {
        self.equation = equation
        self.font = font
        self.textAlignment = textAlignment
        self.fontSize = fontSize
        self.labelMode = labelMode
        self.insets = insets
        self.textColor = MTColor(textColor)
    }*/

    func makeNSView(context: Context) -> MTMathUILabel {
        MTMathUILabel()
    }
    
    func updateNSView(_ view: MTMathUILabel, context: Context) {
        let newFontSize = attributes.fontProperties?.size ?? fontSize
        view.latex = equation
        view.font = MTFontManager().font(withName: font.rawValue, size: newFontSize)
        view.textAlignment = textAlignment
        view.labelMode = labelMode
        view.textColor = textColor
        view.contentInsets = insets
    }
}

#elseif os(iOS) || os(tvOS)

// MARK: - iOS / tvOS Implementation
struct MathView: UIViewRepresentable {
    var equation: String
    var font: MathFont = .latinModernFont
    var textAlignment: MTTextAlignment = .center
    var fontSize: CGFloat = 14
    var labelMode: MTMathUILabelMode = .display
    var insets: MTEdgeInsets = MTEdgeInsets()
    var textColor: MTColor

    init(equation: String, font: MathFont = .latinModernFont, textAlignment: MTTextAlignment = .center, fontSize: CGFloat = 14, labelMode: MTMathUILabelMode = .display, insets: MTEdgeInsets = .zero, textColor: Color = .primary) {
        self.equation = equation
        self.font = font
        self.textAlignment = textAlignment
        self.fontSize = fontSize
        self.labelMode = labelMode
        self.insets = insets
        self.textColor = MTColor(textColor)
    }
    
    func makeUIView(context: Context) -> MTMathUILabel {
        MTMathUILabel()
    }
    
    func updateUIView(_ view: MTMathUILabel, context: Context) {
        view.latex = equation
        view.font = MTFontManager().font(withName: font.rawValue, size: fontSize)
        view.textAlignment = textAlignment
        view.labelMode = labelMode
        view.textColor = textColor
        view.contentInsets = insets
    }
}

#else

// MARK: - Fallback for other platforms (like watchOS)
// 对于不支持的平台，我们可以提供一个占位符视图，这样至少能编译通过
struct MathView: View {
    var equation: String
    
    // 我们需要一个初始化方法来匹配其他的，即使参数没用
    init(equation: String, font: MathFont = .latinModernFont, textAlignment: MTTextAlignment = .center, fontSize: CGFloat = 14, labelMode: MTMathUILabelMode = .display, insets: MTEdgeInsets = .zero, textColor: Color = .primary) {
        self.equation = equation
    }
    
    var body: some View {
        // 在 watchOS 或其他不支持的平台上，只显示原始 LaTeX 文本
        Text(equation)
            .font(.caption.monospaced())
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
}

#endif
