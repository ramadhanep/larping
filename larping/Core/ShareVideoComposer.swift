import AVFoundation
import CoreLocation
import UIKit

/// Renders the route draw-in as an actual video file: reuses
/// `ShareImageComposer.compose(...routeRevealFraction:)` frame-by-frame (same
/// plain space-dark background + accent route line as the default template,
/// not a live map — snapshotting map tiles per frame would mean hundreds of
/// network fetches for one export) and encodes with `AVAssetWriter`.
enum ShareVideoComposer {
    static let duration: TimeInterval = 6
    static let frameRate: Int32 = 60

    enum ComposeError: Error {
        case writerFailed
    }

    static func composeVideo(coordinates: [CLLocationCoordinate2D], stats: ShareImageComposer.Stats) async throws -> URL {
        let size = ShareImageComposer.canvasSize
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("larping-share-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw ComposeError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(frameRate))
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let progress = Double(frame) / Double(totalFrames - 1)
            let image = ShareImageComposer.compose(photo: nil, coordinates: coordinates, stats: stats, routeRevealFraction: progress)
            guard let buffer = pixelBuffer(from: image, size: size) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ComposeError.writerFailed }
        return url
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        guard let context, let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
