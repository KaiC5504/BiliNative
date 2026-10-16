import AVFoundation
import CoreImage
import Photos
import UIKit
import DevLog

/// The screenshot button. BTR plays a local HLS playlist, which AVAssetImageGenerator cannot read, so frames
/// come from the video output PlayerHostView attaches to every item.
enum FrameCapture {
    static func capture(from item: AVPlayerItem) -> UIImage? {
        guard let output = item.outputs.lazy.compactMap({ $0 as? AVPlayerItemVideoOutput }).first,
              let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil) else {
            Logger.shared.warn(.player, "no frame to capture")
            return nil
        }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let frame = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: frame)
    }

    static func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            Logger.shared.info(.ui, "photos access refused", ["status": .init(status.rawValue)])
            return false
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            Logger.shared.warn(.ui, "saving the screenshot failed", ["error": .init(String(describing: error))])
            return false
        }
    }
}
