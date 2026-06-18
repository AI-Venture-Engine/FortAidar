# 🐕 VaultDog — 3D Glass File Keeper

Free file storage app for Apple (iOS/macOS) — for humans AND AI agents.

## What is this?
Instead of a boring icon in the dock, VaultDog is a **3D volumetric mascot on a transparent glass platform**. You drag files onto the dog, it guards them.

## Quick Start
```bash
bash run.sh
# Opens http://localhost:8090
```

## Architecture

### Visual Components
| Component | Description |
|-----------|-------------|
| Glass Platform | Wireframe disc (rings + radial lines), edge glow, translucent halo |
| 3D Mascot | PNG with alpha channel on textured plane, floating above platform |
| Floating Files | Colored cubes orbiting the platform (docs, configs, keys, secrets) |
| Particles | Ambient dust motes for atmosphere |

### Stack
- **p5.js 1.11.3** + WEBGL mode
- **Transparent PNG** mascot (chromakey from JPEG)
- **orbitControl()** for camera

### Integration into SwiftUI App
```swift
import SwiftUI
import WebKit

struct VaultDogView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        if let url = Bundle.main.url(forResource: "index", 
                                      withExtension: "html", 
                                      subdirectory: "vaultdog") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

### Communication: JS ↔ Swift
```javascript
// In index.html — send file deposit events to Swift
function depositFile(fileName, fileType) {
    window.webkit.messageHandlers.vaultDog.postMessage({
        action: 'deposit',
        name: fileName,
        type: fileType
    });
}
```

```swift
// In SwiftUI — receive events from p5.js
class VaultDogCoordinator: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, 
                                didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["action"] as? String == "deposit" {
            // Handle file deposit
        }
    }
}
```

## Files
- `index.html` — Full p5.js app (WEBGL)
- `dog_transparent.png` — Doberman mascot with alpha channel
- `run.sh` — Launch script (starts http.server on :8090)

## Narrative (Future)
Doberman (strict) + Dachshund (sassy) — guard files together. Dachshund flies to Mars with Elon. Returns with martian files. 💫

## Linear
[AI3-399](https://linear.app/ai3lab/issue/AI3-399/vaultdog-3d-glass-file-keeper-for-apple)
