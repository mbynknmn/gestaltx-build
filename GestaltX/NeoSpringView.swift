// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Nouvborne/Ketamine's GPL-3.0 respring implementation.
// Original WebKit technique: neonmodder123; Swift implementation: skadz108.
// NeoSpring project: https://github.com/rooootdev/neospring
// GestaltX changes (2026): corrected raw-string HTML escaping and random-data
// request size; added cancellation, timeout and Simulator exclusion.
import SwiftUI
import WebKit
import QuartzCore

struct NeoSpringView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var running = false
    @State private var timedOut = false
    @State private var hasStarted = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if !targetEnvironment(simulator)
            if running {
                NeoSpringWebView(started: { hasStarted = true }, failed: { running = false; timedOut = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            #endif
            VStack(spacing: 18) {
                if !timedOut { ProgressView().tint(.white).controlSize(.large) }
                Text(L(timedOut ? "Respring did not finish." : "Refreshing SpringBoard…")).font(.headline)
                Text(L(timedOut ? "This OS build may not support the technique. You can close this screen and try a manual restart later." : "Your device may briefly return to the Lock Screen."))
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
                Button(L(timedOut ? "Close" : "Cancel")) { running = false; dismiss() }
                    .buttonStyle(.bordered).tint(.white).padding(.top, 8)
            }.foregroundStyle(.white).padding(32).frame(maxWidth: 440)
        }
        .task(id: hasStarted) {
            #if targetEnvironment(simulator)
            timedOut = true
            #else
            do {
                running = true
                try await Task.sleep(for: .seconds(hasStarted ? 20 : 10))
                running = false; timedOut = true
            } catch { /* A ready WebView restarts the timeout task. */ }
            #endif
        }
        .onDisappear { running = false }
    }
}
private struct NeoSpringWebView: UIViewRepresentable {
    let started: () -> Void
    let failed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(started: started, failed: failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        let view = VisibleWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.becameVisible = { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.startIfReady(view) }
        }
        view.loadHTMLString(Self.document, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.startIfReady(view) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopped = true
        view.navigationDelegate = nil
        (view as? VisibleWebView)?.becameVisible = nil
        view.stopLoading()
        view.evaluateJavaScript("window.stopNeoSpring && window.stopNeoSpring()", completionHandler: nil)
        view.loadHTMLString("", baseURL: nil)
    }

    private final class VisibleWebView: WKWebView {
        var becameVisible: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); becameVisible?() }
        override func layoutSubviews() { super.layoutSubviews(); becameVisible?() }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let started: () -> Void
        private let failed: () -> Void
        private var loaded = false
        private var requested = false
        var stopped = false

        init(started: @escaping () -> Void, failed: @escaping () -> Void) {
            self.started = started; self.failed = failed
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            startIfReady(webView)
        }
        func startIfReady(_ webView: WKWebView) {
            guard loaded, !requested, !stopped, webView.window != nil,
                  webView.bounds.width > 0, webView.bounds.height > 0 else { return }
            requested = true
            // Start after attachment and a layout/render opportunity, rather than
            // during makeUIView while WebKit still has a zero-sized surface.
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, !self.stopped, webView.window != nil else { return }
                webView.setNeedsLayout()
                webView.layoutIfNeeded()
                CATransaction.flush()
                webView.evaluateJavaScript("window.startNeoSpring()") { [weak self] _, error in
                    guard let self, !self.stopped else { return }
                    if error == nil { self.started() } else { self.failed() }
                }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !stopped { failed() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !stopped { failed() }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if !stopped { failed() }
        }
    }
    private static let document = #"""
    <!DOCTYPE html>
    <html>
      <head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style></head>
      <body>
        <iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
        <script>
          const frame = document.getElementById('frame');
          const payload = `
            <html>
              <body>
                <script>
                  const container = document.createElement('div');
                  container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';
                  document.body.appendChild(container);

                  for (let i = 0; i < 500; i++) {
                    const layer = document.createElement('div');
                    layer.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';
                    container.appendChild(layer);
                  }

                  setInterval(() => {
                    try {
                      if (typeof navigator.share === 'function') {
                        navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});
                      }
                    } catch (_) {}
                    const bytes = new Uint8Array(1024 * 1024 * 10);
                    crypto.getRandomValues(bytes.subarray(0, 65536));
                  }, 0);
                <\/script>
              </body>
            </html>
          `;
          let started = false;
          let generation = 0;
          window.startNeoSpring = () => {
            if (started) return false;
            started = true;
            const run = ++generation;
            requestAnimationFrame(() => requestAnimationFrame(() => {
              if (started && generation === run) frame.srcdoc = payload;
            }));
            return true;
          };
          window.stopNeoSpring = () => {
            started = false;
            generation++;
            frame.srcdoc = '';
          };
        </script>
      </body>
    </html>
    """#
}
