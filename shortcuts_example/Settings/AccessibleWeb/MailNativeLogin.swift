import Foundation
import WebKit

enum MailLoginResult { case content, needsAddress, rejected, challenge, failed }

/// Holds a secret only until a single origin-checked submission or cancellation.
@MainActor
final class MailNativeLogin {
    private var task: Task<Void, Never>?
    private var secret: String?
    private var completion: ((MailLoginResult) -> Void)?
    private var generation = 0

    func cancel() { generation += 1; secret = nil; completion = nil; task?.cancel(); task = nil }
    func fail() { finish(.failed) }
    func reject() { finish(.rejected) }
    private func finish(_ result: MailLoginResult) {
        let callback = completion
        cancel(); callback?(result)
    }
    func start(view: WKWebView, provider: EasyMailProvider, identifier: String?, password: String?, navigate: () -> Void,
               onForegroundBlocking: @escaping (Bool) -> Void = { _ in }, done: @escaping (MailLoginResult) -> Void) {
        cancel(); secret = password; completion = done
        let version = generation, attempt = UUID().uuidString
        let initialDeadline = Date().addingTimeInterval(35)
        let restore = password == nil
        let foregroundSubmission = provider.id == "naver" && !restore
        func script(submitted: Bool, credentials: [String: String]? = nil) -> String? {
            let config: [String: Any] = ["provider": provider.id, "inboxHosts": Array(provider.nativeInboxHosts),
                                         "submitted": submitted, "credentials": credentials as Any? ?? NSNull()]
            guard let data = try? JSONSerialization.data(withJSONObject: config) else { return nil }
            return MailNativeLoginPage.source.replacingOccurrences(of: "__RIVO_MAIL_LOGIN__", with: String(decoding: data, as: UTF8.self))
        }
        navigate()
        task = Task { [weak self, weak view] in
            var submitted = false
            var waitingForCaptcha = false
            var deadline = initialDeadline
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let view, self.generation == version else { return }
                guard Date() < deadline else {
                    self.finish(foregroundSubmission && submitted ? .challenge : .failed)
                    return
                }
                guard let url = view.url, url.scheme != "about" else { continue }
                guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                      let host = url.host, provider.authHosts.contains(host) || provider.nativeInboxHosts.contains(host) else {
                    if foregroundSubmission && submitted { self.finish(.challenge); return }
                    continue
                }
                guard !view.isLoading else { continue }
                guard let probe = script(submitted: submitted) else { self.finish(.failed); return }
                let status = (try? await view.evaluateJavaScript(probe)) as? String
                guard !Task.isCancelled, self.generation == version else { return }
                switch status {
                case "failed": self.finish(.failed); return
                case "content": self.finish(.content); return
                case "captcha":
                    guard foregroundSubmission && submitted else { self.finish(.challenge); return }
                    if !waitingForCaptcha {
                        waitingForCaptcha = true
                        deadline = Date().addingTimeInterval(120)
                        onForegroundBlocking(false)
                    }
                case "challenge": self.finish(.challenge); return
                case "rejected":
                    if submitted || restore { self.finish(restore ? .needsAddress : .rejected); return }
                case "ready", "retry":
                    if restore { self.finish(.needsAddress); return }
                    let retry = status == "retry"
                    if submitted != retry || (foregroundSubmission && view.window == nil) { continue }
                    guard let passwordValue = self.secret, let identifier,
                          let code = script(submitted: retry, credentials: ["attempt": attempt, "identifier": identifier, "password": passwordValue])
                    else { self.finish(.failed); return }
                    if !foregroundSubmission || retry { self.secret = nil }
                    if foregroundSubmission { onForegroundBlocking(true) }
                    submitted = true
                    let result = (try? await view.evaluateJavaScript(code)) as? String
                    guard !Task.isCancelled, self.generation == version else { return }
                    if foregroundSubmission {
                        if result == "failed" { self.finish(.failed); return }
                        if retry || (result != nil && result != "submitted") { self.finish(.challenge); return }
                        deadline = Date().addingTimeInterval(15)
                        continue
                    }
                    if result != "submitted" { self.finish(.failed); return }
                default: break
                }
            }
        }
    }
}
