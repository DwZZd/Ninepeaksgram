import Foundation
import Postbox

// A new local media id forces upload without the source message's cloud TTL.
public func viewOnceMediaCopyReference(_ media: Media) -> AnyMediaReference {
    if let image = media as? TelegramMediaImage {
        return .standalone(media: TelegramMediaImage(
            imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)),
            representations: image.representations,
            videoRepresentations: image.videoRepresentations,
            immediateThumbnailData: image.immediateThumbnailData,
            emojiMarkup: image.emojiMarkup,
            reference: nil,
            partialReference: image.partialReference,
            flags: image.flags,
            video: image.video
        ))
    }
    if let file = media as? TelegramMediaFile {
        return .standalone(media: TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)),
            partialReference: file.partialReference,
            resource: file.resource,
            previewRepresentations: file.previewRepresentations,
            videoThumbnails: file.videoThumbnails,
            videoCover: file.videoCover,
            immediateThumbnailData: file.immediateThumbnailData,
            mimeType: file.mimeType,
            size: file.size,
            attributes: file.attributes,
            alternativeRepresentations: file.alternativeRepresentations
        ))
    }
    return .standalone(media: media)
}
