import SwiftUI
import SwiftMath
import AppKit

extension Sequence where Element == InlineNode {
  func renderText(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) -> Text {
    var renderer = TextInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      images: images,
      softBreakMode: softBreakMode,
      attributes: attributes
    )
    renderer.render(self)
    return renderer.result
  }
}

private struct TextInlineRenderer {
  var result = Text("")

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let softBreakMode: SoftBreak.Mode
  private let attributes: AttributeContainer
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.softBreakMode = softBreakMode
    self.attributes = attributes
  }

  mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines {
      self.render(inline)
    }
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .html(let content):
      self.renderHTML(content)
    case .image(let source, _):
      self.renderImage(source)
    case .latex(let content):
      self.renderLatex(content)
    default:
      self.defaultRender(inline)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    self.defaultRender(.text(text))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.defaultRender(.softBreak)
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.defaultRender(.lineBreak)
    }
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.defaultRender(.lineBreak)
      self.shouldSkipNextWhitespace = true
    default:
      self.defaultRender(.html(html))
    }
  }

  private mutating func renderImage(_ source: String) {
    if let image = self.images[source] {
      self.result = self.result + Text(image)
    }
  }

  private mutating func renderLatex(_ source: String) {
      let fontSize = self.attributes.fontProperties?.size ?? 16
      let foregroundColor = self.attributes.foregroundColor ?? .primary
      
      //print("renderLatexAsAttachment:\n\(content)\n")
      // 渲染为 NSImage
      let (_, nsImage) = MTMathImage(
        latex: source,
        fontSize: fontSize,
        textColor: MTColor(foregroundColor),
        labelMode: .text
      ).asImage()

      // 渲染失败回退
      guard let nsImage else {
          self.defaultRender(.text(source))
        return
      }
        //print("renderLatex:\n\(source)\n")
      // 创建 NSTextAttachment
      // 1. 创建 Image 视图。
      let image = Image(nsImage: nsImage)
      
      // 2. [语法修正] 将 Image 通过字符串插值嵌入到 Text 中。
      var imageAsText = Text("\(image)")
      
      // 3. [对齐修正] 计算精确的基线偏移量。
      let imageHeight = nsImage.size.height
      let fontXHeight = fontSize
      let offset = (imageHeight / 2.0) - (fontXHeight / 2.0)
      let baselineOffset = -offset
      
      // 4. 应用计算出的偏移量
      imageAsText = imageAsText
          .baselineOffset(baselineOffset)
      
      // 5. 将处理好的 Text 拼接到最终结果
      self.result = self.result + Text(image) + Text(" ")
  }
    
  private mutating func defaultRender(_ inline: InlineNode) {
    self.result =
      self.result
      + Text(
        inline.renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
  }
}
