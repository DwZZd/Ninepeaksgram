import Foundation

/// Менеджер для сохранения удалённых сообщений
/// Перехватывает сообщения перед удалением и архивирует их локально
public final class AntiDeleteManager {
    
    public static let shared = AntiDeleteManager()
    
    // MARK: - Settings
    
    private let defaults = UserDefaults.standard
    private let enabledKey = "antiDelete.enabled"
    private let archiveMediaKey = "antiDelete.archiveMedia"
    private let deletedMessageTransparencyKey = "antiDelete.deletedMessageTransparency"
    private let archiveKey = "antiDelete.archive"
    private let deletedIdsKey = "antiDelete.deletedIds"
    
    /// Включено ли сохранение удалённых сообщений
    public var isEnabled: Bool {
        get {
            if defaults.object(forKey: enabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: enabledKey)
        }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
    
    /// Сохранять ли медиа-контент
    public var archiveMedia: Bool {
        get { defaults.bool(forKey: archiveMediaKey) }
        set { defaults.set(newValue, forKey: archiveMediaKey) }
    }
    
    /// Минимальное значение прозрачности удалённого сообщения
    public static let minDeletedMessageTransparency: Double = 0.0
    
    /// Максимальное значение прозрачности удалённого сообщения
    public static let maxDeletedMessageTransparency: Double = 0.8
    
    /// Значение прозрачности удалённого сообщения по умолчанию
    public static let defaultDeletedMessageTransparency: Double = 0.45
    
    /// Прозрачность удалённых сообщений (0.0 = непрозрачно, 0.8 = максимально прозрачно)
    public var deletedMessageTransparency: Double {
        get {
            let value = defaults.object(forKey: deletedMessageTransparencyKey) as? NSNumber
            let resolvedValue = value?.doubleValue ?? Self.defaultDeletedMessageTransparency
            return max(Self.minDeletedMessageTransparency, min(Self.maxDeletedMessageTransparency, resolvedValue))
        }
        set {
            let clampedValue = max(Self.minDeletedMessageTransparency, min(Self.maxDeletedMessageTransparency, newValue))
            defaults.set(clampedValue, forKey: deletedMessageTransparencyKey)
        }
    }
    
    /// Альфа для отображения удалённых сообщений
    public var deletedMessageDisplayAlpha: Double {
        return 1.0 - self.deletedMessageTransparency
    }
    
    // MARK: - Deleted Message IDs Storage
    
    private var deletedMessageIds: Set<String> = []
    private let deletedIdsLock = NSLock()
    
    /// Пометить сообщение как удалённое
    public func markAsDeleted(peerId: Int64, messageId: Int32) {
        let key = "\(peerId)_\(messageId)"
        deletedIdsLock.lock()
        deletedMessageIds.insert(key)
        deletedIdsLock.unlock()
        saveDeletedIds()
    }
    
    /// Проверить, является ли сообщение удалённым
    public func isMessageDeleted(peerId: Int64, messageId: Int32) -> Bool {
        guard isEnabled else { return false }
        let key = "\(peerId)_\(messageId)"
        deletedIdsLock.lock()
        defer { deletedIdsLock.unlock() }
        return deletedMessageIds.contains(key)
    }
    
    /// Проверить, является ли сообщение удалённым (по тексту - legacy)
    public func isMessageDeleted(text: String) -> Bool {
        guard isEnabled else { return false }
        // Legacy: проверяем наличие дефолтного префикса для обратной совместимости
        let defaultPrefix = "🗑️ "
        return text.hasPrefix(defaultPrefix)
    }
    
    private func saveDeletedIds() {
        deletedIdsLock.lock()
        let ids = Array(deletedMessageIds)
        deletedIdsLock.unlock()
        defaults.set(ids, forKey: deletedIdsKey)
    }
    
    private func loadDeletedIds() {
        if let ids = defaults.stringArray(forKey: deletedIdsKey) {
            deletedIdsLock.lock()
            deletedMessageIds = Set(ids)
            deletedIdsLock.unlock()
        }
    }
    
    // MARK: - Archived Messages Storage
    
    /// Структура архивированного сообщения
    public struct ArchivedMessage: Codable {
        public let globalId: Int32
        public let peerId: Int64
        public let messageId: Int32
        public let timestamp: Int32
        public let deletedAt: Int32
        public let authorId: Int64?
        public let text: String
        public let forwardAuthorId: Int64?
        public let mediaDescription: String?
        
        public init(
            globalId: Int32,
            peerId: Int64,
            messageId: Int32,
            timestamp: Int32,
            deletedAt: Int32,
            authorId: Int64?,
            text: String,
            forwardAuthorId: Int64?,
            mediaDescription: String?
        ) {
            self.globalId = globalId
            self.peerId = peerId
            self.messageId = messageId
            self.timestamp = timestamp
            self.deletedAt = deletedAt
            self.authorId = authorId
            self.text = text
            self.forwardAuthorId = forwardAuthorId
            self.mediaDescription = mediaDescription
        }
    }
    
    private var archivedMessages: [ArchivedMessage] = []
    private let archiveLock = NSLock()
    
    private init() {
        // Set default values
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
        if defaults.object(forKey: archiveMediaKey) == nil {
            defaults.set(true, forKey: archiveMediaKey)
        }
        if defaults.object(forKey: "antiDelete.keepAllV2") == nil {
            defaults.set(true, forKey: enabledKey)
            defaults.set(true, forKey: archiveMediaKey)
            defaults.set(true, forKey: "antiDelete.keepAllV2")
        }
        if defaults.object(forKey: deletedMessageTransparencyKey) == nil {
            defaults.set(Self.defaultDeletedMessageTransparency, forKey: deletedMessageTransparencyKey)
        }
        loadArchive()
        loadDeletedIds()
    }
    
    // MARK: - Archive Operations
    
    /// Архивировать сообщение перед удалением
    /// - Parameters:
    ///   - globalId: Глобальный ID сообщения
    ///   - peerId: ID чата
    ///   - messageId: Локальный ID сообщения
    ///   - timestamp: Время отправки
    ///   - authorId: ID автора
    ///   - text: Текст сообщения
    ///   - forwardAuthorId: ID автора пересланного сообщения
    ///   - mediaDescription: Описание медиа (тип, размер)
    public func archiveMessage(
        globalId: Int32,
        peerId: Int64,
        messageId: Int32,
        timestamp: Int32,
        authorId: Int64?,
        text: String,
        forwardAuthorId: Int64? = nil,
        mediaDescription: String? = nil
    ) {
        guard isEnabled else { return }
        
        let archived = ArchivedMessage(
            globalId: globalId,
            peerId: peerId,
            messageId: messageId,
            timestamp: timestamp,
            deletedAt: Int32(Date().timeIntervalSince1970),
            authorId: authorId,
            text: text,
            forwardAuthorId: forwardAuthorId,
            mediaDescription: mediaDescription
        )
        
        archiveLock.lock()
        defer { archiveLock.unlock() }
        
        // Avoid duplicates
        if !archivedMessages.contains(where: { $0.globalId == globalId }) {
            archivedMessages.append(archived)
            saveArchive()
        }
    }
    
    /// Получить все архивированные сообщения
    public func getAllArchivedMessages() -> [ArchivedMessage] {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        return archivedMessages.sorted { $0.deletedAt > $1.deletedAt }
    }
    
    /// Получить архивированные сообщения для конкретного чата
    /// - Parameter peerId: ID чата
    public func getArchivedMessages(forPeerId peerId: Int64) -> [ArchivedMessage] {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        return archivedMessages
            .filter { $0.peerId == peerId }
            .sorted { $0.deletedAt > $1.deletedAt }
    }
    
    /// Количество архивированных сообщений
    public var archivedCount: Int {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        return archivedMessages.count
    }
    
    /// Получить данные архивированных сообщений для удаления из диалогов
    /// Возвращает массив (peerId, messageId)
    public func getArchivedMessageData() -> [(peerId: Int64, messageId: Int32)] {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        return archivedMessages.map { (peerId: $0.peerId, messageId: $0.messageId) }
    }
    
    /// Очистить архив
    public func clearArchive() {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        archivedMessages.removeAll()
        saveArchive()
    }
    
    /// Удалить конкретное сообщение из архива
    public func removeFromArchive(globalId: Int32) {
        archiveLock.lock()
        defer { archiveLock.unlock() }
        archivedMessages.removeAll { $0.globalId == globalId }
        saveArchive()
    }
    
    // MARK: - Persistence
    
    private func saveArchive() {
        do {
            let data = try JSONEncoder().encode(archivedMessages)
            defaults.set(data, forKey: archiveKey)
        } catch {
            print("[AntiDelete] Failed to save archive: \(error)")
        }
    }
    
    private func loadArchive() {
        guard let data = defaults.data(forKey: archiveKey) else { return }
        do {
            archivedMessages = try JSONDecoder().decode([ArchivedMessage].self, from: data)
        } catch {
            print("[AntiDelete] Failed to load archive: \(error)")
            archivedMessages = []
        }
    }
}
