import SwiftUI
import WebKit

/// Serves the bundled MathJax and a course's `cards-media/` over `mm://app/…`, so cards render offline
/// and `<img src="name">` from imported Anki cards resolves without opening file access.
final class CardSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Where the bundled MathJax ended up (found by searching the app bundle, so it works however resources are laid out).
    static let mathJaxURL: URL? = {
        if let direct = Bundle.main.url(forResource: "tex-svg-full", withExtension: "js") { return direct }
        let e = FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            if url.lastPathComponent == "tex-svg-full.js" { return url }
        }
        return nil
    }()
    var mediaFolder: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return urlSchemeTask.didFailWithError(URLError(.badURL)) }
        let path = url.path
        var file: URL?
        var mime = "application/octet-stream"
        if path == "/mathjax.js" {
            file = CardSchemeHandler.mathJaxURL
            mime = "text/javascript"
        } else if path.hasPrefix("/media/"), let folder = mediaFolder {
            let name = String(path.dropFirst("/media/".count))
            if !name.contains("..") && !name.contains("/") {
                file = folder.appendingPathComponent(name)
                switch (name as NSString).pathExtension.lowercased() {
                case "png": mime = "image/png"
                case "jpg", "jpeg": mime = "image/jpeg"
                case "gif": mime = "image/gif"
                case "svg": mime = "image/svg+xml"
                case "webp": mime = "image/webp"
                default: break
                }
            }
        }
        guard let file, let data = try? Data(contentsOf: file) else {
            return urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Renders Anki-compatible HTML + MathJax (`\( \)`, `\[ \]`) with a bundled MathJax 3 (SVG output).
/// One page is loaded once; content changes go through `setContent(...)`.
struct CardWebView: UIViewRepresentable {
    var html: String
    var mediaFolder: URL?
    /// Set to scroll to the n-th bold section header.
    var scrollToSection: Int?
    var fontSize: CGFloat = 20

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.scheme, forURLScheme: "mm")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.loadHTMLString(Self.page, baseURL: URL(string: "mm://app/"))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.scheme.mediaFolder = mediaFolder
        let safe = CardText.sanitize(html)
        if c.pending != safe || c.fontSize != fontSize {
            c.pending = safe
            c.fontSize = fontSize
            c.flush()
        }
        if let n = scrollToSection, n != c.lastSection {
            c.lastSection = n
            web.evaluateJavaScript("scrollToSection(\(n))")
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let scheme = CardSchemeHandler()
        weak var web: WKWebView?
        var pending = ""
        var fontSize: CGFloat = 20
        var lastSection: Int?
        private var ready = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            flush()
        }

        func flush() {
            guard ready, let web else { return }
            let payload = (try? JSONSerialization.data(withJSONObject: [pending], options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            web.evaluateJavaScript("setContent(\(payload)[0], \(Int(fontSize)))")
        }

        // Links inside cards never navigate away.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .linkActivated ? .cancel : .allow
        }
    }

    static let page = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      html { -webkit-text-size-adjust: none; }
      body { margin: 0; padding: 18px 22px 120px; font: 20px/1.55 "Latin Modern Roman", "Times New Roman", Georgia, serif;
             color: #1c1b19; background: transparent; overflow-wrap: anywhere; }
      @media (prefers-color-scheme: dark) { body { color: #f2f1ee; } }
      svg { max-width: 100%; height: auto; }
      img { max-width: 100%; }
      mjx-container { color: inherit; }
      mjx-container[display="true"] { overflow-x: auto; overflow-y: hidden; padding: 2px 0; }
      b { font-weight: 700; }
      ul, ol { padding-left: 1.4em; }
    </style>
    <script>
      window.MathJax = { tex: { inlineMath: [['\\\\(', '\\\\)']], displayMath: [['\\\\[', '\\\\]']], processEscapes: true },
                         options: { enableMenu: false }, svg: { fontCache: 'global' } };
    </script>
    <script src="mm://app/mathjax.js" async></script>
    </head><body><div id="c"></div>
    <script>
      function fixMedia(root) {
        root.querySelectorAll('img').forEach(function (img) {
          var s = img.getAttribute('src') || '';
          if (s && !/^(mm|data|https?):/.test(s)) img.setAttribute('src', 'mm://app/media/' + encodeURIComponent(decodeURIComponent(s)));
        });
      }
      function setContent(html, size) {
        document.body.style.fontSize = size + 'px';
        var c = document.getElementById('c');
        c.innerHTML = html;
        fixMedia(c);
        var tries = 0;
        var go = function () {
          if (window.MathJax && MathJax.typesetPromise) { MathJax.typesetClear && MathJax.typesetClear([c]); MathJax.typesetPromise([c]); }
          else if (tries++ < 100) setTimeout(go, 50);   // no MathJax bundled: leave the plain text
        };
        go();
      }
      function scrollToSection(n) {
        var bs = Array.prototype.filter.call(document.querySelectorAll('#c b'), function (b) { return /:\\s*$/.test(b.textContent); });
        if (bs[n]) bs[n].scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    </script></body></html>
    """
}
