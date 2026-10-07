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
    private static var observedAuthorizationIds = Set((UserDefaults.standard.array(forKey: "ninegram.desktopLink.authorizing") ?? []).compactMap { value in
        (value as? NSNumber).map { AccountRecordId(rawValue: $0.int64Value) }
    })
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
            self.enqueueLogin(accountId: accountId)
            self.mirrorPendingLogin()
        }
    }

    private static func enqueueLogin(accountId: AccountRecordId) {
        guard self.handledAccountIds.insert(accountId).inserted else { return }
        if !self.pendingAccountIds.contains(accountId) {
            self.pendingAccountIds.append(accountId)
            self.setStatus(accountId: accountId, "В очереди")
        }
        self.savePendingLogins()
    }

    static func sync(accounts: [Account], authorizingAccountId: AccountRecordId?) {
        DispatchQueue.main.async {
            self.startPasswordForwardingIfNeeded()
            if let id = authorizingAccountId {
                self.observedAuthorizationIds.insert(id)
            }
            let previousLiveIds = Set(self.latestAccounts.map { $0.id })
            self.latestAccounts = accounts
            // Phone logout only clears that phone's pending handoff. Desktop
            // authorizations and profiles are independent and must not be revoked.
            let liveIds = Set(accounts.map { $0.id })
            let removedIds = previousLiveIds.subtracting(liveIds)
            for id in removedIds {
                self.passwords.removeValue(forKey: id)
                self.activeTokens.removeValue(forKey: String(id.int64))
            }
            self.pendingAccountIds.removeAll(where: { removedIds.contains($0) })
            if let activeId = self.activeAccountId, !liveIds.contains(activeId) {
                self.activeAccountId = nil
            }
            // The login screen can be disposed before its authorized callback runs.
            // Observe the actual UnauthorizedAccount -> Account transition instead.
            for account in accounts where self.observedAuthorizationIds.contains(account.id) {
                self.observedAuthorizationIds.remove(account.id)
                self.enqueueLogin(accountId: account.id)
            }
            // Recover a login whose password was captured but whose screen callback
            // was lost, including after installing this update over the old build.
            for account in accounts where self.passwords[account.id] != nil {
                let completed = UserDefaults.standard.bool(forKey: "ninegram.desktopLink.mirrored.\(account.peerId.toInt64())")
                if !completed {
                    self.enqueueLogin(accountId: account.id)
                }
            }
            self.savePendingLogins()
            self.mirrorPendingLogin()
        }
    }

    private static func setStatus(accountId: AccountRecordId, _ status: String) {
        let key = "ninegram.desktopLink.status.\(accountId.int64)"
        guard UserDefaults.standard.string(forKey: key) != status else { return }
        UserDefaults.standard.set(status, forKey: key)
        Logger.shared.log("NinegramDesktopLink", "Account \(accountId.int64): \(status)")
        NotificationCenter.default.post(name: Notification.Name("NinegramDesktopLinkStatusChanged"), object: nil)
    }

    private static func mirrorPendingLogin() {
        guard self.activeAccountId == nil else {
            return
        }
        // A stale, logged-out account at the front must not block current logins.
        guard let account = self.pendingAccountIds.compactMap({ id in
            self.latestAccounts.first(where: { $0.id == id })
        }).first else {
            return
        }
        let secret = NinegramDesktopLinkConfig.readSecret
        guard !secret.isEmpty, !secret.hasPrefix("NINEGRAM_LINK_") else {
            self.setStatus(accountId: account.id, "Связь с ПК не настроена")
            return
        }
        let defaultsKey = "ninegram.desktopLink.mirrored.\(account.peerId.toInt64())"
        self.activeAccountId = account.id
        if let encoded = self.activeTokens[String(account.id.int64)], let token = Data(base64Encoded: encoded) {
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
        NotificationCenter.default.addObserver(forName: Notification.Name("NinegramDesktopLinkRetry"), object: nil, queue: .main, using: { notification in
            guard let rawId = notification.userInfo?["accountId"] as? Int64 else { return }
            let id = AccountRecordId(rawValue: rawId)
            if !self.pendingAccountIds.contains(id) {
                self.pendingAccountIds.append(id)
                self.setStatus(accountId: id, "В очереди")
            }
            self.savePendingLogins()
            self.mirrorPendingLogin()
        })
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
            self.setStatus(accountId: account.id, "Ожидаю связи с ПК")
            self.activeAccountId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                self.mirrorPendingLogin()
            }
            return
        }
        self.fetchToken(secret: secret, completion: { token, status in
            DispatchQueue.main.async {
                guard self.activeAccountId == account.id else {
                    return
                }
                self.setStatus(accountId: account.id, status)
                guard let token, !self.usedTokens.contains(token) else {
                    self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                    return
                }
                self.forwardPassword(accountId: account.id, token: token, secret: secret, completion: { sent in
                    guard self.activeAccountId == account.id else { return }
                    guard sent else {
                        self.setStatus(accountId: account.id, "Не удалось передать зашифрованный пароль")
                        self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                        return
                    }
                    let _ = (acceptDesktopLoginToken(account: account, token: token)
                    |> deliverOnMainQueue).startStandalone(next: { accepted in
                        guard self.activeAccountId == account.id else { return }
                        guard accepted else {
                            self.setStatus(accountId: account.id, "Telegram не подтвердил вход на ПК")
                            self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: attempt)
                            return
                        }
                        self.usedTokens.insert(token)
                        self.activeTokens[String(account.id.int64)] = token.base64EncodedString()
                        self.savePendingLogins()
                        self.setStatus(accountId: account.id, "Подтверждён вход на ПК")
                        self.consumeToken(secret: secret, token: token)
                        self.waitForDesktop(account: account, secret: secret, token: token, defaultsKey: defaultsKey, attempt: 0)
                    })
                })
            }
        })
    }

    private static func waitForDesktop(account: Account, secret: String, token: Data, defaultsKey: String, attempt: Int) {
        guard self.activeAccountId == account.id else { return }
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
                    self.setStatus(accountId: account.id, "Аккаунт добавлен на ПК")
                    UserDefaults.standard.set(true, forKey: defaultsKey)
                    self.passwords.removeValue(forKey: account.id)
                    self.activeTokens.removeValue(forKey: String(account.id.int64))
                    self.pendingAccountIds.removeAll(where: { $0 == account.id })
                    self.savePendingLogins()
                    self.activeAccountId = nil
                    self.mirrorPendingLogin()
                } else if status == "failed" || attempt >= 90 {
                    self.setStatus(accountId: account.id, "Вход на ПК не завершён — повторяю")
                    self.activeTokens.removeValue(forKey: String(account.id.int64))
                    self.savePendingLogins()
                    self.retry(account: account, secret: secret, defaultsKey: defaultsKey, attempt: 0)
                } else {
                    self.setStatus(accountId: account.id, "Ожидаю завершения входа на ПК")
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
        UserDefaults.standard.set(self.observedAuthorizationIds.map { $0.int64 }, forKey: "ninegram.desktopLink.authorizing")
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

    private static func fetchToken(secret: String, completion: @escaping (Data?, String) -> Void) {
        guard let url = URL(string: NinegramDesktopLinkConfig.baseURL + "/v1/token") else {
            completion(nil, "Некорректный адрес сервера")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(secret, forHTTPHeaderField: "X-Ninegram-Key")
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error as NSError? {
                completion(nil, "Ошибка соединения (\(error.code))")
                return
            }
            if (response as? HTTPURLResponse)?.statusCode == 204 {
                completion(nil, "Ожидаю Ninegram на ПК")
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                completion(nil, "Ошибка сервера (\((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let encoded = object["token"] as? String,
                  let token = Data(base64Encoded: encoded) else {
                completion(nil, "Сервер не вернул код входа")
                return
            }
            completion(token, "Подтверждаю вход на ПК")
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
