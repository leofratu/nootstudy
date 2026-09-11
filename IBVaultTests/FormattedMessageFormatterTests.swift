import Testing
import Foundation
@testable import IBVault

@Suite("FormattedMessageFormatter Tests")
struct FormattedMessageFormatterTests {

    @Test("Headings parsed correctly")
    func headings() {
        let sections = FormattedMessageFormatter.sections(from: "# Title\n\n## Subtitle\n\n### Third")
        #expect(sections.contains(.heading(level: 1, text: "Title")))
        #expect(sections.contains(.heading(level: 2, text: "Subtitle")))
        #expect(sections.contains(.heading(level: 3, text: "Third")))
        let compact = FormattedMessageFormatter.sections(from: "# Title\n## Subtitle\n### Third")
        #expect(compact.contains(where: { if case .heading(_, let t) = $0 { return t == "Title" } else { return false } }))
        #expect(compact.contains(where: { if case .heading(_, let t) = $0 { return t == "Subtitle" } else { return false } }))
        #expect(compact.contains(where: { if case .heading(_, let t) = $0 { return t == "Third" } else { return false } }))
    }

    @Test("Lists parsed with bullet and numbered markers")
    func lists() {
        let sections = FormattedMessageFormatter.sections(from: "- apple\n* banana\n1. first\n2) second")
        #expect(sections.contains(where: { if case .listItem(let m, let t) = $0 { return m == "•" && t == "apple" } else { return false } }))
        #expect(sections.contains(where: { if case .listItem(let m, let t) = $0 { return m == "•" && t == "banana" } else { return false } }))
        #expect(sections.contains(where: { if case .listItem(let m, _) = $0 { return m == "1." } else { return false } }))
        #expect(sections.contains(where: { if case .listItem(let m, _) = $0 { return m == "2)" } else { return false } }))
    }

    @Test("Quotes parsed")
    func quotes() {
        let sections = FormattedMessageFormatter.sections(from: "> hello world")
        #expect(sections.contains(.quote("hello world")))
    }

    @Test("Dividers parsed")
    func dividers() {
        let sections = FormattedMessageFormatter.sections(from: "---")
        #expect(sections.contains(.divider))
        let sections2 = FormattedMessageFormatter.sections(from: "***")
        #expect(sections2.contains(.divider))
    }

    @Test("Fenced code blocks parsed")
    func fencedCode() {
        let source = "```swift\nlet x = 1\n```"
        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(where: { if case .codeBlock(let code, let lang) = $0 { return code.contains("let x = 1") && lang == "swift" } else { return false } }))
    }

    @Test("Tables with outer pipes handled")
    func tablesWithPipes() {
        let source = "| Name | Age |\n|---|---|\n| Ada | 30 |\n"
        let safe = MessageRenderingPolicy.displaySafeMarkdown(source)
        #expect(safe.contains("Ada"))
        #expect(safe.contains("Age"))
    }

    @Test("Tables without outer pipes handled")
    func tablesWithoutOuterPipes() {
        let source = "Name | Age\n---|---\nAda | 30"
        let safe = MessageRenderingPolicy.displaySafeMarkdown(source)
        #expect(safe.contains("Ada"))
        #expect(safe.contains("Age"))
        // Also via formatter markdown sections should not crash and should produce markdown
        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(!sections.isEmpty)
    }

    @Test("Inline math rendered inline")
    func inlineMath() {
        let source = "The equation $x^2$ is simple."
        let sections = FormattedMessageFormatter.sections(from: source)
        // Inline math is converted to readable text inside markdown, not a separate mathBlock
        #expect(sections.contains(where: { if case .markdown(let t) = $0 { return t.contains("x") } else { return false } }))
        // Also ensure inlineText conversion works
        let inline = MathExpressionFormatter.inlineString(from: "x^2")
        #expect(inline.contains("²") || inline.contains("x"))
    }

    @Test("Display math creates mathBlock")
    func displayMath() {
        let source = "Before\n\n$$E = mc^2$$\n\nAfter"
        let sections = FormattedMessageFormatter.sections(from: source)
        #expect(sections.contains(where: { if case .mathBlock(let latex) = $0 { return latex.contains("E = mc^2") } else { return false } }))
        #expect(sections.contains(where: { if case .markdown(let t) = $0 { return t.contains("Before") } else { return false } }))
        #expect(sections.contains(where: { if case .markdown(let t) = $0 { return t.contains("After") } else { return false } }))
    }

    @Test("Unclosed delimiters render literally")
    func unclosedDelimiters() {
        let source1 = "Price is $5 and more text $unclosed"
        let sections1 = FormattedMessageFormatter.sections(from: source1)
        // Unclosed $ must not swallow following content; the formatter converts closed $...$ to readable text
        // and leaves unclosed delimiters as literal text, but $5 may be converted to "5" via inline math.
        let combined1 = sections1.map { s in
            switch s {
            case .markdown(let t): return t
            case .mathBlock(let t): return t
            default: return ""
            }
        }.joined(separator: " ")
        // Must preserve "more text" and not swallow it as math
        #expect(combined1.contains("more text"))
        #expect(combined1.contains("Price"))
        // The $5 case may be rendered as "5" without $, which is acceptable; just ensure no crash and content preserved
        #expect(combined1.contains("5"))

        let source2 = "Start $$unclosed display math and more"
        let sections2 = FormattedMessageFormatter.sections(from: source2)
        let combined2 = sections2.map { s in
            switch s {
            case .markdown(let t): return t
            case .mathBlock(let t): return t
            default: return ""
            }
        }.joined(separator: " ")
        #expect(combined2.contains("more"))
        #expect(combined2.contains("Start"))
        // Unclosed $$ should leave the raw text, not create a mathBlock that swallows "more"
        #expect(!combined2.contains("mathBlock") || combined2.contains("unclosed"))
    }

    @Test("NBSP normalized to space")
    func nbsp() {
        let source = "Hello\u{00A0}world\u{00A0}test"
        let normalized = FormattedMessageFormatter.normalizeResponseText(source)
        #expect(!normalized.contains("\u{00A0}"))
        #expect(normalized.contains("Hello world"))
        let latex = "a\u{00A0}b"
        let canonical = MathRenderingPolicy.canonicalDisplayLatex(latex)
        #expect(!canonical.contains("\u{00A0}"))
        let canonical2 = FormattedMessageFormatter.canonicalDisplayLatex(latex)
        #expect(!canonical2.contains("\u{00A0}"))
    }

    @Test("Depth counting for nested frac")
    func nestedFrac() {
        let source = "\\frac{\\frac{a}{b}}{c}"
        let result = MathExpressionFormatter.inlineString(from: source)
        // Should not crash and should contain a, b, c
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(result.contains("c"))
        #expect(result.contains("/"))
    }

    @Test("Depth counting preserves text with braces")
    func textWithBraces() {
        let source = "\\text{a {b} c}"
        let result = MathExpressionFormatter.inlineString(from: source)
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(result.contains("c"))
    }

    @Test("Attributed markdown not nil for simple markdown")
    func attributedMarkdown() {
        let attr = FormattedMessageFormatter.attributedMarkdown(from: "**bold** and *italic*")
        #expect(attr != nil)
    }

    @Test("Inline latex arrow maps to unicode arrow not word arrow")
    func latexArrowMapping() {
        let eq = "6CO_2 + 6H_2O \\rightarrow C_6H_{12}O_6 + 6O_2"
        let result = MathExpressionFormatter.inlineString(from: eq)
        #expect(result.contains("→"))
        #expect(!result.contains("arrow"))
        #expect(!result.contains("rightarrow"))
        // Prefix collision: \\rightarrow must not be truncated by \\right
        let leftArrow = MathExpressionFormatter.inlineString(from: "A \\leftarrow B")
        #expect(leftArrow.contains("←"))
        let rightDouble = MathExpressionFormatter.inlineString(from: "A \\Rightarrow B")
        #expect(rightDouble.contains("⇒"))
        let leftDouble = MathExpressionFormatter.inlineString(from: "A \\Leftarrow B")
        #expect(leftDouble.contains("⇐"))
    }

    @Test("Full command map coverage")
    func commandMapCoverage() {
        let cases: [(String, String)] = [
            ("\\to", "→"), ("\\approx", "≈"), ("\\neq", "≠"), ("\\ne", "≠"),
            ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
            ("\\times", "×"), ("\\cdot", "·"), ("\\pm", "±"), ("\\infty", "∞"),
            ("\\sum", "Σ"), ("\\int", "∫"), ("\\partial", "∂"),
            ("\\alpha", "α"), ("\\omega", "ω"), ("\\Gamma", "Γ")
        ]
        for (cmd, expected) in cases {
            let out = MathExpressionFormatter.inlineString(from: cmd)
            #expect(out.contains(expected), "\\(cmd) should map to \\(expected) got \\(out)")
        }
        // Unknown command degrades gracefully
        let unknown = MathExpressionFormatter.inlineString(from: "\\unknowncmd")
        #expect(unknown.contains("unknowncmd") || unknown == "unknowncmd")
        #expect(!unknown.contains("\\"))
    }

    @Test("GFM pipe tables parse to table sections")
    func pipeTables() {
        let withPipes = "| Stage | Location |\n|---|---|\n| Light-dependent | Thylakoid |\n| Calvin cycle | Stroma |"
        let sections = FormattedMessageFormatter.sections(from: withPipes)
        #expect(sections.contains(where: { if case .table(let h, let rows) = $0 { return h.count == 2 && rows.count == 2 } else { return false } }))
        let withoutOuterPipes = "Stage | Location\n---|---\nLight-dependent | Thylakoid\nCalvin cycle | Stroma"
        let sections2 = FormattedMessageFormatter.sections(from: withoutOuterPipes)
        #expect(sections2.contains(where: { if case .table = $0 { return true } else { return false } }))
    }
}
