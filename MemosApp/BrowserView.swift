import SwiftUI
import WebKit

final class BrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var loadError: String?
    weak var webView: WKWebView?

    func reload() {
        loadError = nil
        if let wv = webView, wv.url != nil { wv.reload() }
        else { goHome() }
    }

    var homeURL: URL?
    func goHome() {
        loadError = nil
        if let url = homeURL { webView?.load(URLRequest(url: url)) }
    }
}

struct BrowserView: View {
    let serverURL: URL
    @EnvironmentObject var settings: AppSettings
    @StateObject private var model = BrowserModel()
    @State private var confirmChange = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WebView(url: serverURL, model: model)
                .edgesIgnoringSafeArea(.bottom)

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if let err = model.loadError {
                errorView(err)
            }

            Menu {
                Button { model.goHome() } label: { Label("首页", systemImage: "house") }
                Button { model.reload() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Button { if let u = model.webView?.url { UIApplication.shared.open(u) } } label: {
                    Label("在 Safari 中打开", systemImage: "safari")
                }
                Divider()
                Button(role: .destructive) { confirmChange = true } label: {
                    Label("更换服务器", systemImage: "server.rack")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .opacity(0.7)
            }
            .padding(.leading, 12)
            .padding(.bottom, 28)
        }
        .onAppear { model.homeURL = serverURL }
        .alert("更换服务器？", isPresented: $confirmChange) {
            Button("取消", role: .cancel) {}
            Button("更换") { settings.serverURL = nil }
        } message: {
            Text("当前：\(serverURL.absoluteString)")
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundColor(.secondary)
            Text("无法连接到服务器").font(.headline)
            Text(message).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text(serverURL.absoluteString).font(.footnote.monospaced()).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("重试") { model.reload() }.buttonStyle(.borderedProminent)
                Button("更换服务器") { settings.serverURL = nil }.buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(url: url, model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = .systemBackground
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh

        model.webView = wv
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let url: URL
        let model: BrowserModel

        init(url: URL, model: BrowserModel) {
            self.url = url
            self.model = model
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            model.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sender.endRefreshing() }
        }

        private func isInternal(_ target: URL) -> Bool {
            guard let scheme = target.scheme?.lowercased() else { return true }
            if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
            return target.host?.lowercased() == url.host?.lowercased()
        }

        // Keep the Memos server in-app; open everything else (links in memos, etc.) externally.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { return decisionHandler(.allow) }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame && !isInternal(target) && navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(target)
                return decisionHandler(.cancel)
            }
            if let scheme = target.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(scheme) {
                UIApplication.shared.open(target)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // target="_blank" links
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = navigationAction.request.url {
                if isInternal(target) { webView.load(navigationAction.request) }
                else { UIApplication.shared.open(target) }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            model.loadError = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handle(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handle(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func handle(_ error: Error) {
            model.isLoading = false
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // frame load interrupted
            model.loadError = error.localizedDescription
        }

        // JS dialogs (window.alert / confirm / prompt) used by the Memos web UI
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            present(UIAlertController(title: nil, message: message, preferredStyle: .alert).with {
                $0.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            }, from: webView, fallback: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            present(UIAlertController(title: nil, message: message, preferredStyle: .alert).with {
                $0.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
                $0.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            }, from: webView, fallback: { completionHandler(false) })
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            present(alert, from: webView, fallback: { completionHandler(nil) })
        }

        private func present(_ alert: UIAlertController, from view: UIView, fallback: () -> Void) {
            guard var top = view.window?.rootViewController else { return fallback() }
            while let next = top.presentedViewController { top = next }
            top.present(alert, animated: true)
        }
    }
}

private extension UIAlertController {
    func with(_ configure: (UIAlertController) -> Void) -> UIAlertController {
        configure(self)
        return self
    }
}
