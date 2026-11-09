import CoreGraphics

/// Assembles an already-determined overlap; it does not estimate the scroll distance.
enum ScrollImageComposer {
    static let maximumPixels = 32_000_000
    static func append(top: CGImage, bottom: CGImage, overlap: Int) throws -> CGImage {
        guard top.width == bottom.width, overlap >= 0, overlap < bottom.height else {
            throw ScreenshotError.processingFailed("The captured window changed size or the overlap is invalid. Start a new capture.")
        }
        let addedHeight = bottom.height - overlap
        let height = top.height + addedHeight
        guard height <= 32_000, top.width <= maximumPixels / height else {
            throw ScreenshotError.processingFailed("Scroll capture reached the image size limit. Capture a shorter section.")
        }
        // CGImage cropping uses top-left image coordinates; CGContext drawing uses bottom-left.
        guard let novel = bottom.cropping(to: CGRect(x: 0, y: overlap, width: bottom.width, height: addedHeight)),
              let context = CGContext(data: nil, width: top.width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenshotError.imageCreationFailed
        }
        context.draw(top, in: CGRect(x: 0, y: addedHeight, width: top.width, height: top.height))
        context.draw(novel, in: CGRect(x: 0, y: 0, width: novel.width, height: novel.height))
        guard let image = context.makeImage() else { throw ScreenshotError.imageCreationFailed }
        return image
    }
}
