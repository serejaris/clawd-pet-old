import Foundation
import CoreGraphics
import ImageIO

public struct AnimationFrame {
    public let image: CGImage
    public let duration: TimeInterval
}

public final class AnimatedAsset {
    public let name: String
    public let frames: [AnimationFrame]
    public let totalDuration: TimeInterval

    public init(name: String, frames: [AnimationFrame]) {
        self.name = name
        self.frames = frames
        self.totalDuration = frames.reduce(0) { $0 + $1.duration }
    }

    public func frame(at time: TimeInterval, loop: Bool = true) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard totalDuration > 0 else { return frames[0].image }

        var t = time
        if loop {
            t = t.truncatingRemainder(dividingBy: totalDuration)
        } else if t >= totalDuration {
            return frames.last?.image
        }

        var elapsed: TimeInterval = 0
        for frame in frames {
            elapsed += frame.duration
            if t < elapsed {
                return frame.image
            }
        }
        return frames.last?.image
    }
}

public final class AssetManager {
    public static let shared = AssetManager()

    public private(set) var assetsDirectory: URL?
    private var imageCache: [String: CGImage] = [:]
    private var animationCache: [String: AnimatedAsset] = [:]

    public private(set) var stillImage: CGImage?
    public private(set) var noEyesImage: CGImage?
    public private(set) var blinkImage: CGImage?

    // Eye coordinates relative to cropped sprite (1200 x 1499)
    // Left eye: x: 300, y: 600, w: 100, h: 100 (in bottom-up Cocoa coords)
    // Right eye: x: 800, y: 600, w: 100, h: 100 (in bottom-up Cocoa coords)
    public let leftEyeRect = CGRect(x: 300, y: 600, width: 100, height: 100)
    public let rightEyeRect = CGRect(x: 800, y: 600, width: 100, height: 100)

    public let spriteSize = CGSize(width: 1200, height: 1499)

    private init() {
        findAssetsDirectory()
        loadBaseSprites()
    }

    private func findAssetsDirectory() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("assets"),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("assets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("../assets"),
            URL(fileURLWithPath: NSString(string: "~/Documents/GitHub/clawd-pet/assets").expandingTildeInPath)
        ]

        for url in candidates.compactMap({ $0 }) {
            let probe = url.appendingPathComponent("Clawd-Still.png")
            if FileManager.default.fileExists(atPath: probe.path) {
                self.assetsDirectory = url
                return
            }
        }

        // Fallback to current working directory
        self.assetsDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
    }

    public func assetURL(for filename: String) -> URL? {
        guard let dir = assetsDirectory else { return nil }
        let url = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadBaseSprites() {
        guard let url = assetURL(for: "Clawd-Still.png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        // Crop character from canvas (x: 736, y: 351, w: 1200, h: 1499 in top-left bitmap coords)
        let crop = CGRect(x: 736, y: 351, width: 1200, height: 1499)
        guard let cropped = fullImage.cropping(to: crop) else { return }
        self.stillImage = cropped

        // Generate noEyesImage and blinkImage
        let w = cropped.width
        let h = cropped.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        // In CGContext (bottom-up), eye Y is 600
        let eyeColor = CGColor(red: 217/255.0, green: 119/255.0, blue: 87/255.0, alpha: 1.0)
        let lidColor = CGColor(red: 163/255.0, green: 89/255.0, blue: 65/255.0, alpha: 1.0)

        // 1. noEyesImage
        if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info) {
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(eyeColor)
            ctx.fill(leftEyeRect)
            ctx.fill(rightEyeRect)
            self.noEyesImage = ctx.makeImage()
        }

        // 2. blinkImage (noEyes + eyelid line across center of each eye)
        if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info) {
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(eyeColor)
            ctx.fill(leftEyeRect)
            ctx.fill(rightEyeRect)

            ctx.setFillColor(lidColor)
            let leftLid = CGRect(x: leftEyeRect.minX, y: leftEyeRect.midY - 10, width: leftEyeRect.width, height: 20)
            let rightLid = CGRect(x: rightEyeRect.minX, y: rightEyeRect.midY - 10, width: rightEyeRect.width, height: 20)
            ctx.fill(leftLid)
            ctx.fill(rightLid)
            self.blinkImage = ctx.makeImage()
        }
    }

    public func loadGIF(named filename: String, crop: CGRect? = nil) -> AnimatedAsset? {
        if let cached = animationCache[filename] {
            return cached
        }

        guard let url = assetURL(for: filename),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [AnimationFrame] = []

        for i in 0..<count {
            guard let fullImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            let frameImage: CGImage
            if let crop = crop, let cropped = fullImage.cropping(to: crop) {
                frameImage = cropped
            } else {
                frameImage = fullImage
            }

            var delay: TimeInterval = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProps = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber, unclamped.doubleValue > 0.01 {
                    delay = unclamped.doubleValue
                } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? NSNumber, clamped.doubleValue > 0.01 {
                    delay = clamped.doubleValue
                }
            }

            if delay < 0.02 {
                delay = 0.1
            }

            frames.append(AnimationFrame(image: frameImage, duration: delay))
        }

        let asset = AnimatedAsset(name: filename, frames: frames)
        animationCache[filename] = asset
        return asset
    }

    // Standard animation accessors
    public func walkAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-CrabWalking.gif", crop: CGRect(x: 736, y: 351, width: 1200, height: 1499))
    }

    public func jumpAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-JumpingHappy.gif", crop: CGRect(x: 736, y: 351, width: 1200, height: 1499))
    }

    public func waveAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-Waving.gif", crop: CGRect(x: 736, y: 351, width: 1200, height: 1499))
    }

    public func danceAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-Dancing.gif", crop: CGRect(x: 14, y: 18, width: 226, height: 209))
    }

    public func workAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-Working.gif", crop: CGRect(x: 22, y: 24, width: 372, height: 205))
    }

    public func cookAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-Cooking.gif", crop: CGRect(x: 0, y: 14, width: 482, height: 347))
    }

    public func cookIntroAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-CookIntro.gif", crop: nil)
    }

    public func lurkAnimation() -> AnimatedAsset? {
        return loadGIF(named: "Clawd-Lurking.gif", crop: CGRect(x: 736, y: 351, width: 1200, height: 1499))
    }
}
