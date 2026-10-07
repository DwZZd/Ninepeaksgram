import Foundation
import Postbox

// MARK: - DeletedMessageAttribute
// This attribute marks a message as "deleted but visible" in the chat
// When anti-delete is enabled, messages are not removed but marked with this attribute

public class DeletedMessageAttribute: MessageAttribute, Equatable {
    public let deletedAt: Int32
    public let deletedByPeerId: Int64?
    
    public var associatedMessageIds: [MessageId] { return [] }
    public var associatedPeerIds: [PeerId] { return [] }
    public var automaticTimestampBasedAttribute: (UInt32, Int32)? { return nil }
    
    public init(deletedAt: Int32, deletedByPeerId: Int64? = nil) {
        self.deletedAt = deletedAt
        self.deletedByPeerId = deletedByPeerId
    }
    
    public required init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
        self.deletedByPeerId = decoder.decodeOptionalInt64ForKey("p")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
        if let peerId = self.deletedByPeerId {
            encoder.encodeInt64(peerId, forKey: "p")
        }
    }
    
    public static func ==(lhs: DeletedMessageAttribute, rhs: DeletedMessageAttribute) -> Bool {
        return lhs.deletedAt == rhs.deletedAt && lhs.deletedByPeerId == rhs.deletedByPeerId
    }
}

// MARK: - Helper extension for Message
public extension Message {
    var isDeletedButVisible: Bool {
        return self.attributes.contains(where: { $0 is DeletedMessageAttribute })
    }
    
    var deletedMessageAttribute: DeletedMessageAttribute? {
        return self.attributes.first(where: { $0 is DeletedMessageAttribute }) as? DeletedMessageAttribute
    }
    
    var ghostgramIsDeleted: Bool {
        if self.isDeletedButVisible {
            return true
        }
        if AntiDeleteManager.shared.isMessageDeleted(peerId: self.id.peerId.toInt64(), messageId: self.id.id) {
            return true
        }
        return AntiDeleteManager.shared.isMessageDeleted(text: self.text)
    }
}
