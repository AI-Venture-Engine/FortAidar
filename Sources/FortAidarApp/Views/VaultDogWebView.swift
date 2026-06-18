import SwiftUI
import WebKit

struct VaultDogWebView: NSViewRepresentable {
    @ObservedObject var bridge: VaultDogBridge

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false

        bridge.webView = webView

        if let url = vaultDogIndexURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if bridge.webView !== nsView {
            bridge.webView = nsView
        }
    }

    private func vaultDogIndexURL() -> URL? {
        let bundleName = "FortAidar_FortAidarApp"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle")
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "vaultdog") {
                return url
            }
        }

        return nil
    }
}
