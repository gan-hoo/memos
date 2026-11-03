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
    let session: WebSession
    @EnvironmentObject var server: LocalServer
    @StateObject private var model = BrowserModel()
    @State private var showAccount = false
    @State private var showAbout = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WebView(session: session, model: model)
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
                Divider()
                Button { server.signInAgain() } label: { Label("重新自动登录", systemImage: "person.crop.circle.badge.checkmark") }
                Button { showAccount = true } label: { Label("本地账户", systemImage: "key") }
                Button { showAbout = true } label: { Label("关于与数据", systemImage: "info.circle") }
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
        .onAppear { model.homeURL = session.baseURL }
        .onChange(of: server.restartCount) { _ in model.reload() }
        .alert("本地账户", isPresented: $showAccount) {
            Button("复制密码") { UIPasteboard.general.string = LocalAccount.loadOrCreate().password }
            Button("好", role: .cancel) {}
        } message: {
            let account = LocalAccount.loadOrCreate()
            Text("用户名：\(account.username)\n密码：\(account.password)\n\nApp 会自动登录。如果你在网页里退出了登录，点“重新自动登录”即可。")
        }
        .alert("Memos \(server.version)", isPresented: $showAbout) {
            Button("好", role: .cancel) {}
        } message: {
            Text("所有笔记都保存在本机，无需服务器。\n\n数据库文件 memos_prod.db 位于“文件” App → 我的 iPhone → Memos，可直接拷贝备份。")
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundColor(.secondary)
            Text("页面加载失败").font(.headline)
            Text(message).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("重试") {
                server.ensureAlive()
                model.reload()
            }.buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct WebView: UIViewRepresentable {
    let session: WebSession
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(url: session.baseURL, model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if let script = session.bootstrapScript {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

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
        wv.load(URLRequest(url: session.baseURL))
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
