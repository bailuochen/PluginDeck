import SwiftUI
@preconcurrency import WebKit
import PluginDeckCore

struct ExternalPluginWebView: NSViewRepresentable {
    let plugin: InstalledPlugin
    let registry: PluginRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(plugin: plugin, registry: registry)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(context.coordinator, name: "plugindeck")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let packagePath = plugin.packagePath,
              let entryPoint = plugin.manifest.ui?.entryPoint else {
            webView.loadHTMLString("<p>Plugin interface is unavailable.</p>", baseURL: nil)
            return webView
        }
        let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true)
        let pageURL = packageURL.appendingPathComponent(entryPoint)
        webView.loadFileURL(pageURL, allowingReadAccessTo: packageURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "plugindeck")
        webView.navigationDelegate = nil
    }

    private static let bridgeScript = #"""
    (() => {
      const callbacks = new Map();
      window.PluginDeck = Object.freeze({
        invoke(actionID, payload = {}) {
          return new Promise((resolve, reject) => {
            const callbackID = globalThis.crypto?.randomUUID?.()
              ?? `${Date.now()}-${Math.random()}`;
            callbacks.set(callbackID, { resolve, reject });
            window.webkit.messageHandlers.plugindeck.postMessage({
              callbackID,
              actionID,
              payload
            });
          });
        },
        __receive(callbackID, result, error) {
          const callback = callbacks.get(callbackID);
          if (!callback) return;
          callbacks.delete(callbackID);
          if (error) callback.reject(new Error(error));
          else callback.resolve(result);
        }
      });
      window.dispatchEvent(new CustomEvent("plugindeckready"));
    })();
    """#
}

@MainActor
final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let plugin: InstalledPlugin
    let registry: PluginRegistry
    let runner = ExternalPluginRunner()
    weak var webView: WKWebView?

    init(plugin: InstalledPlugin, registry: PluginRegistry) {
        self.plugin = plugin
        self.registry = registry
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "plugindeck",
              let body = message.body as? [String: Any],
              let callbackID = body["callbackID"] as? String,
              let actionID = body["actionID"] as? String,
              let action = plugin.manifest.actions?.first(where: { $0.id == actionID }) else {
            return
        }
        let payload = normalizePayload(body["payload"] as? [String: Any] ?? [:])
        guard !action.requiresConfirmation || confirm(action: action, payload: payload) else {
            send(callbackID: callbackID, error: "用户已取消")
            return
        }

        let taskID = registry.beginTask(
            pluginID: plugin.id,
            pluginName: plugin.manifest.name,
            kind: .run,
            message: action.title
        )
        Task {
            do {
                let result = try await runner.run(
                    plugin: plugin,
                    action: action,
                    payload: payload
                )
                registry.finishTask(taskID, succeeded: true, message: result.message)
                send(callbackID: callbackID, result: result)
            } catch {
                registry.finishTask(taskID, succeeded: false, message: error.localizedDescription)
                send(callbackID: callbackID, error: error.localizedDescription)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        return url.isFileURL || url.scheme == "about" ? .allow : .cancel
    }

    private func normalizePayload(_ payload: [String: Any]) -> [String: String] {
        payload.reduce(into: [:]) { result, item in
            switch item.value {
            case let value as String:
                result[item.key] = value
            case let value as NSNumber:
                result[item.key] = value.stringValue
            case is NSNull:
                result[item.key] = ""
            default:
                guard JSONSerialization.isValidJSONObject(item.value),
                      let data = try? JSONSerialization.data(withJSONObject: item.value),
                      let value = String(data: data, encoding: .utf8) else { return }
                result[item.key] = value
            }
        }
    }

    private func confirm(
        action: PluginManifest.Action,
        payload: [String: String]
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = action.title
        let details = payload.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        alert.informativeText = details.isEmpty
            ? action.description
            : "\(action.description)\n\n\(details)"
        alert.addButton(withTitle: "执行")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func send(
        callbackID: String,
        result: PluginActionResult? = nil,
        error: String? = nil
    ) {
        var resultObject: [String: Any] = [:]
        if let result {
            if let title = result.title { resultObject["title"] = title }
            resultObject["message"] = result.message
            if let detail = result.detail { resultObject["detail"] = detail }
        }
        let arguments: [Any] = [
            callbackID,
            result == nil ? NSNull() : resultObject,
            error ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.PluginDeck.__receive.apply(null, \(json));")
    }
}
