import Foundation
import Postbox

/// A previous version, stored in this account's Postbox with the message itself.
public final class MessageEditVersion: PostboxCoding {
    public let timestamp: Int32
    public let text: String
    public let entities: TextEntitiesMessageAttribute?
    public let media: [Media]

    public init(message: Message) {
        self.timestamp = (message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date ?? message.timestamp
        self.text = message.text
        self.entities = message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute
        self.media = message.media
    }

    public init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("t", orElse: 0)
        self.text = decoder.decodeStringForKey("x", orElse: "")
        self.entities = decoder.decodeObjectForKey("e") as? TextEntitiesMessageAttribute
        let media: [PostboxCoding] = decoder.decodeObjectArrayForKey("m")
        self.media = media.compactMap { $0 as? Media }
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "t")
        encoder.encodeString(self.text, forKey: "x")
        if let entities = self.entities {
            encoder.encodeObject(entities, forKey: "e")
        }
        // Preserve concrete media type hashes, not the Media protocol metatype.
        // This is the same heterogeneous-array codec used by InstantPage media.
        encoder.encodeGenericObjectArray(self.media.map { $0 as PostboxCoding }, forKey: "m")
    }

    public var mediaDescription: String? {
        return describeNinegramHistoryMedia(self.media)
    }
}

public final class MessageEditHistoryAttribute: MessageAttribute {
    public let versions: [MessageEditVersion]

    public init(versions: [MessageEditVersion]) {
        self.versions = versions
    }

    public init(decoder: PostboxDecoder) {
        self.versions = decoder.decodeObjectArrayForKey("v")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.versions, forKey: "v")
    }
}

public final class BurnedEphemeralMediaMessageAttribute: MessageAttribute {
    public init() {
    }

    public init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(1, forKey: "b")
    }
}

public extension Message {
    var ninegramEditHistory: [MessageEditVersion] {
        return (self.attributes.first(where: { $0 is MessageEditHistoryAttribute }) as? MessageEditHistoryAttribute)?.versions ?? []
    }

    var ninegramMediaBurned: Bool {
        return self.attributes.contains(where: { $0 is BurnedEphemeralMediaMessageAttribute })
    }

    var ninegramHistoryMediaDescription: String? {
        return describeNinegramHistoryMedia(self.media)
    }
}

private func describeNinegramHistoryMedia(_ media: [Media]) -> String? {
    let descriptions: [String] = media.compactMap { media in
        if media is TelegramMediaImage {
            return "Фото"
        } else if let file = media as? TelegramMediaFile {
            if file.isVoice { return "Голосовое сообщение" }
            if file.isInstantVideo { return "Видеосообщение" }
            if file.isVideo { return "Видео" }
            return file.fileName ?? "Файл"
        }
        return nil
    }
    return descriptions.isEmpty ? nil : descriptions.joined(separator: ", ")
}

// One hook covers live edits, differences after reconnect, and history refetches.
// Local flags must survive a server snapshot that does not know about them.
func preserveNinegramMessageMetadata(previous: Message, updated: StoreMessage) -> StoreMessage {
    var attributes = updated.attributes
    let previousHistory = previous.attributes.first(where: { $0 is MessageEditHistoryAttribute }) as? MessageEditHistoryAttribute
    var versions = previousHistory?.versions ?? []
    let previousEdit = (previous.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
    let updatedEdit = (attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date
    let previousEntities = previous.textEntitiesAttribute?.entities ?? []
    let updatedEntities = (attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
    let textChanged = previous.text != updated.text || previousEntities != updatedEntities
    // Compare attachment identities, not fetched previews/poll counters or file
    // metadata. Replacing an attachment twice in one second is still an edit.
    let previousAttachments = previous.media.filter { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
    let updatedAttachments = updated.media.filter { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
    let mediaChanged = previousAttachments.count != updatedAttachments.count || zip(previousAttachments, updatedAttachments).contains(where: { $0.0.id != $0.1.id })
    if let updatedEdit = updatedEdit,
       updatedEdit >= (previousEdit ?? previous.timestamp),
       textChanged || mediaChanged {
        versions.append(MessageEditVersion(message: previous))
    }
    if !versions.isEmpty {
        attributes.removeAll(where: { $0 is MessageEditHistoryAttribute })
        attributes.append(MessageEditHistoryAttribute(versions: versions))
    }
    if previous.ninegramMediaBurned && !attributes.contains(where: { $0 is BurnedEphemeralMediaMessageAttribute }) {
        attributes.append(BurnedEphemeralMediaMessageAttribute())
    }
    return updated.withUpdatedAttributes(attributes)
}
