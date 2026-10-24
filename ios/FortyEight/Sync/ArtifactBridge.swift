import SwiftUI
import WebKit

/// The artifact database has no public API: only the claude.ai viewer runtime can reach it.
/// So the app keeps a WKWebView signed in to claude.ai, opens the artifact, and injects a small
/// script into the artifact's frame that relays `window.claude.use("db")` to native code.
@MainActor
final class ArtifactBridge: NSObject, ObservableObject {
    enum State: Equatable { case connecting, ready, needsSignIn, stalled(String) }

    static let defaultURL = URL(string: "https://claude.ai/artifact/MpF5B74ANDZdGN3MiimVqd")!

    @Published private(set) var state: State = .connecting
    @Published var showWeb = false

    var onDays: (([(id: String, data: Data)], Bool) -> Void)?
    var onProfile: ((Data?) -> Void)?
    var onReady: (() -> Void)?

    let artifactURL: URL
    let webView: WKWebView
    private var frame: WKFrameInfo?
    private var watchdog: Task<Void, Never>?

    override init() {
        // A debug override lets the simulator point at a local harness page.
        if let s = UserDefaults.standard.string(forKey: "artifactURL"), let u = URL(string: s) { artifactURL = u } else { artifactURL = Self.defaultURL }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.relayJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: Self.signInJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        cfg.userContentController = ucc
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        super.init()
        ucc.add(WeakHandler(self), name: "fe48")
        webView.navigationDelegate = self
        webView.isInspectable = true
        webView.backgroundColor = .clear
        webView.isOpaque = false
    }

    func start() { load(artifactURL) }

    func reload() {
        frame = nil
        state = .connecting
        load(artifactURL)
    }

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
        armWatchdog()
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled, self.state == .connecting else { return }
            self.state = .stalled("25 秒内没连上数据库")
        }
    }

    /// Runs one database write inside the artifact frame. Returns nil on success, or an error code.
    func write(path: String, op: String, json: String?) async -> String? {
        guard state == .ready, let frame else { return "not_ready" }
        do {
            let r = try await webView.callAsyncJavaScript(
                "return await window.__fe48.write(path, op, json);",
                arguments: ["path": path, "op": op, "json": json ?? ""],
                in: frame, contentWorld: .page)
            if let d = r as? [String: Any], d["ok"] as? Bool == true { return nil }
            return ((r as? [String: Any])?["code"] as? String) ?? "unknown"
        } catch {
            state = .stalled("网页连接断开")
            return "bridge"
        }
    }

    /// Opens the web composer or Claude review inside the artifact (they need the viewer's consent UI).
    func openWebFeature(_ what: String) {
        showWeb = true
        guard state == .ready, let frame else { return }
        Task { _ = try? await webView.callAsyncJavaScript("window.__fe48.ui(what); return true;", arguments: ["what": what], in: frame, contentWorld: .page) }
    }

    fileprivate func receive(_ msg: WKScriptMessage) {
        guard let body = msg.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            frame = msg.frameInfo
            watchdog?.cancel()
            state = .ready
            onReady?()
        case "days":
            let docs = (body["docs"] as? [[String: Any]] ?? []).compactMap { d -> (id: String, data: Data)? in
                guard let id = d["id"] as? String, let obj = d["data"], let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
                return (id, data)
            }
            onDays?(docs, body["pending"] as? Bool ?? false)
        case "profile":
            if body["exists"] as? Bool == true, let obj = body["data"], let data = try? JSONSerialization.data(withJSONObject: obj) { onProfile?(data) } else { onProfile?(nil) }
        case "signin":
            if state != .ready { state = .needsSignIn; watchdog?.cancel() }
        case "nodb":
            state = .stalled("这个页面拿不到数据库（可能没有访问权限）")
        case "error":
            if body["where"] as? String == "days" { state = .stalled("数据库订阅出错：\(body["code"] as? String ?? "")") }
        default: break
        }
    }

    /// Signed out, claude.ai renders a sign-in wall at the artifact URL itself (no redirect to /login),
    /// so the main frame watches its own text for a few seconds after load.
    static let signInJS = #"""
    (() => {
      let n = 0;
      const t = setInterval(() => {
        n++;
        const txt = (document.body && document.body.innerText) || '';
        const wall = /sign in to view|log in to view|登录后查看|登录以查看/i.test(txt) || location.pathname.startsWith('/login');
        if (wall && !document.querySelector('iframe')) {
          clearInterval(t);
          try { window.webkit.messageHandlers.fe48.postMessage({ type: 'signin' }); } catch (e) {}
        }
        if (n > 40) clearInterval(t);
      }, 500);
    })();
    """#

    /// Injected into every frame at document end. Only the artifact frame has `window.claude.use`.
    static let relayJS = #"""
    (() => {
      if (window.__fe48 || window === window.top) return;
      const c = window.claude;
      if (!c || typeof c.use !== 'function') return;
      const post = m => { try { window.webkit.messageHandlers.fe48.postMessage(m); } catch (e) {} };
      const plain = v => JSON.parse(JSON.stringify(v ?? null));
      window.__fe48 = {};
      (async () => {
        const db = await c.use('db');
        if (!db) { post({ type: 'nodb' }); return; }
        db.collection('days').onSnapshot(
          s => post({ type: 'days', pending: s.metadata.hasPendingWrites, docs: s.docs.map(d => ({ id: d.id, data: plain(d.data()) })) }),
          e => post({ type: 'error', where: 'days', code: e && e.code }));
        db.doc('memory/profile').onSnapshot(
          s => post({ type: 'profile', exists: s.exists, data: s.exists ? plain(s.data()) : null }),
          e => post({ type: 'error', where: 'profile', code: e && e.code }));
        window.__fe48.write = async (path, op, json) => {
          try {
            const ref = db.doc(path), data = json ? JSON.parse(json) : null;
            if (op === 'set') await ref.set(data);
            else if (op === 'update') await ref.update(data);
            else if (op === 'delete') await ref.delete();
            return { ok: true };
          } catch (e) { return { ok: false, code: (e && e.code) || 'unknown' }; }
        };
        window.__fe48.ui = what => {
          const el = document.getElementById(what === 'compose' ? 'openComposer' : 'aiBtn');
          if (el) el.click();
        };
        post({ type: 'ready' });
      })();
    })();
    """#
}

extension ArtifactBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host()?.hasSuffix("claude.ai") == true else { return }
        let path = url.path()
        if path.hasPrefix("/login") || path.hasPrefix("/magic-link") {
            state = .needsSignIn
            watchdog?.cancel()
        } else if !path.hasPrefix("/artifact") && (path == "/" || path.hasPrefix("/new") || path.hasPrefix("/recents") || path.hasPrefix("/chat") || path.hasPrefix("/project")) {
            // Signed in but landed elsewhere (claude.ai's default after login): go back to the artifact.
            state = .connecting
            load(artifactURL)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        state = .stalled("网络错误：\(error.localizedDescription)")
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: ArtifactBridge?
    init(_ t: ArtifactBridge) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.receive(message) }
    }
}

/// Hosts the single bridge WKWebView. The hidden host keeps it alive behind the UI; the sheet host
/// borrows it while visible (sign-in, web composer) and hands it back when dismissed.
struct WebHost: UIViewRepresentable {
    let bridge: ArtifactBridge
    let active: Bool

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ v: UIView, context: Context) {
        guard active, bridge.webView.superview !== v else { return }
        bridge.webView.removeFromSuperview()
        bridge.webView.frame = v.bounds
        bridge.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(bridge.webView)
    }
}
