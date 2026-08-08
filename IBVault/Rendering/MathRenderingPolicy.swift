import Foundation
import SwiftUI

/// Canonical authority for how mathematical content is classified and styled.
/// Inline expressions stay in the prose flow; only explicit display delimiters
/// mount the MathJax surface.
nonisolated enum MathRenderingPolicy: Sendable {
    static func canonicalDisplayLatex(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        for delimiters in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)")] {
            if value.hasPrefix(delimiters.0), value.hasSuffix(delimiters.1), value.count >= delimiters.0.count + delimiters.1.count {
                value.removeFirst(delimiters.0.count)
                value.removeLast(delimiters.1.count)
                break
            }
        }
        return value
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func inlineText(_ latex: String) -> String {
        MathExpressionFormatter.inlineString(from: latex)
    }

    static func htmlDocument(latex: String, colorScheme: ColorScheme) -> String {
        let canonical = canonicalDisplayLatex(latex)
        let escaped = canonical
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let foreground = colorScheme == .dark ? "#F5F7FA" : "#182033"
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script>
        window.MathJax = {
          loader: {load: ['[tex]/ams']},
          tex: {
            packages: {'[+]': ['ams']},
            inlineMath: [['$', '$'], ['\\(', '\\)']],
            displayMath: [['$$', '$$'], ['\\[', '\\]']],
            processEscapes: true
          },
          svg: {fontCache: 'none'},
          startup: {ready: () => {
            MathJax.startup.defaultReady();
            MathJax.startup.promise
              .then(() => MathJax.typesetPromise([document.body]))
              .then(() => {
                reportHeight();
                new ResizeObserver(reportHeight).observe(document.body);
              })
              .catch(reportError);
          }}
        };
        function reportHeight() {
          window.webkit.messageHandlers.mathHeight.postMessage(
            Math.ceil(Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 38))
          );
        }
        function reportError() { window.webkit.messageHandlers.mathError.postMessage('render failed'); }
        </script>
        <script src="tex-svg.js"></script>
        <style>
          :root { color-scheme: light dark; }
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(foreground);
            overflow-x: auto;
            overflow-y: hidden;
          }
          body {
            box-sizing: border-box;
            min-height: 38px;
            padding: 8px 42px 8px 12px;
            font-size: 17px;
            line-height: 1.35;
          }
          mjx-container[jax="SVG"][display="true"] {
            margin: 0 !important;
            text-align: left !important;
            min-width: max-content;
          }
          mjx-container svg { max-width: none; }
        </style>
        </head>
        <body>$$\(escaped)$$</body>
        </html>
        """
    }
}
