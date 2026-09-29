//
//  ProfilePhoto.swift
//  Colony
//
//  Turns any picked or dropped image into a small square JPEG for the profile photo.
//  ImageIO only, so it's the same code on Mac, iPhone, iPad and Vision Pro.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProfilePhoto {
    /// Output edge in pixels. 320 px is sharp at the largest size shown (96 pt @3x ≈ 288 px)
    /// and keeps the JPEG to tens of KB, well within iCloud key-value storage limits.
    static let side = 320

    /// Centre-crops to a square, scales to `side` and re-encodes as JPEG. Honours EXIF
    /// orientation. Returns nil for data that isn't a readable image.
    static func prepare(_ data: Data, side: Int = side) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 3,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let edge = min(image.width, image.height)
        let crop = CGRect(x: (image.width - edge) / 2, y: (image.height - edge) / 2, width: edge, height: edge)
        guard let square = image.cropping(to: crop),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
