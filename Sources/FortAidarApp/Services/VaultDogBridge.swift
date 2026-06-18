import Foundation
import WebKit

@MainActor
final class VaultDogBridge: ObservableObject {
    weak var webView: WKWebView?

    func addGuardedFile(name: String, kind: String) {
        let safeName = jsString(name)
        let safeKind = jsString(kind)
        webView?.evaluateJavaScript("window.vaultDogAddFile(\(safeName), \(safeKind));")
    }

    private func jsString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"file\""
    }
}
