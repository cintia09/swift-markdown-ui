import SwiftUI

extension View {
  /// Sets the inline image provider for the Markdown inline images in a view hierarchy.
  /// - Parameter inlineImageProvider: The inline image provider to set. Use one of the built-in values, like
  ///                                  ``InlineImageProvider/default`` or ``InlineImageProvider/asset``,
  ///                                  or a custom inline image provider that you define by creating a type that
  ///                                  conforms to the ``InlineImageProvider`` protocol.
  /// - Returns: A view that uses the specified inline image provider for itself and its child views.
  public func markdownInlineImageProvider(_ inlineImageProvider: InlineImageProvider) -> some View {
    self.environment(\.inlineImageProvider, inlineImageProvider)
  }
}

extension EnvironmentValues {
  var inlineImageProvider: InlineImageProvider {
    get { self[InlineImageProviderKey.self] }
    set { self[InlineImageProviderKey.self] = newValue }
  }
}

private struct InlineImageProviderKey: EnvironmentKey {
  static let defaultValue: InlineImageProvider = .default
}


// MARK: - Inline Attribute Rewriter API

/// A closure that rewrites the `AttributedString` for a given `InlineNode`.
///
/// Use this to perform advanced, content-aware styling that's not possible
/// with the standard `Theme` system. The closure receives the original node
/// and its default rendered `AttributedString`, and should return a new
/// `AttributedString` to be used in the final `Text` view.
///
/// - Parameters:
///   - node: The `InlineNode` being processed.
///   - attributedString: The default `AttributedString` generated for this node.
/// - Returns: The final `AttributedString` to use for this node.
public typealias InlineAttributeRewriter = (String, AttributeContainer) -> AttributedString

private struct InlineAttributeRewriterKey: EnvironmentKey {
    // The default rewriter does nothing, just returns the original string.
    static let defaultValue: InlineAttributeRewriter = { text, container in
        .init(text, attributes: container)
    }
}

// MARK: - Attributed Text Renderer API

/// A closure that renders a final `AttributedString` into a `Text` view.
///
/// Use this to replace the default text rendering logic, which by default includes LaTeX processing.
/// You can provide a custom implementation to handle math rendering differently, or to
/// perform other final transformations on the attributed string before it becomes a `Text` view.
///
/// - Parameters:
///   - attributedString: The final `AttributedString` for a segment of text, after all
///     styles and rewrites have been applied.
///   - container: The `AttributeContainer` containing the SwiftUI environment's text-related
///     attributes (like font, color, etc.).
/// - Returns: The `Text` view to be displayed.
public typealias InlineAttributedTextRender = (AttributedString, AttributeContainer, CGFloat, Color) -> Text

private struct InlineAttributedTextRenderKey: EnvironmentKey {
    // By default, this points to the library's LaTeX renderer to ensure backward compatibility.
    // Replace `SimpleLatexExtractor` with the actual name from your library.
    static let defaultValue: InlineAttributedTextRender = { attributedString, container, _, _ in
        Text(attributedString)
    }
}


// MARK: - EnvironmentValues Extension

extension EnvironmentValues {
    var inlineAttributeRewriter: InlineAttributeRewriter {
        get { self[InlineAttributeRewriterKey.self] }
        set { self[InlineAttributeRewriterKey.self] = newValue }
    }
    
    var inlineAttributeTextRender: InlineAttributedTextRender {
        get { self[InlineAttributedTextRenderKey.self] }
        set { self[InlineAttributedTextRenderKey.self] = newValue }
    }
}

// MARK: - Public View Modifiers

extension View {
    /// Applies a custom transformation to the `AttributedString` of each `InlineNode`.
    ///
    /// This modifier gives you low-level access to the `AttributedString` generated for each
    /// inline element, allowing you to rewrite it based on the node's type and content.
    ///
    /// - Parameter rewriter: A closure that takes an `InlineNode` and its default
    ///   `AttributedString` and returns a new `AttributedString`.
    public func markdownInlineAttributeRewriter(_ rewriter: @escaping InlineAttributeRewriter) -> some View {
        self.environment(\.inlineAttributeRewriter, rewriter)
    }
    
    /// Overrides the final rendering step that converts an `AttributedString` to `Text`.
    ///
    /// By default, `SwiftMarkdownUI` uses a renderer that can process LaTeX syntax.
    /// Use this modifier to provide a completely different renderer, for example,
    /// to disable LaTeX processing or to integrate a different math rendering library.
    ///
    /// - Parameter renderer: A closure that takes a final `AttributedString` and its
    ///   `AttributeContainer`, and returns the `Text` to be displayed.
    public func markdownInlineTextRenderer(_ renderer: @escaping InlineAttributedTextRender) -> some View {
        self.environment(\.inlineAttributeTextRender, renderer)
    }
}
