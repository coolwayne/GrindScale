import UIKit

struct GrayImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

enum ImageProcessing {
    static func grayscale(_ image: UIImage, maxDimension: Int = 1024) -> GrayImage? {
        guard let cgImage = image.cgImage else { return nil }
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        let scale = min(1.0, Double(maxDimension) / Double(max(srcWidth, srcHeight)))
        let width = max(1, Int(Double(srcWidth) * scale))
        let height = max(1, Int(Double(srcHeight) * scale))

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    static func boxBlur(_ image: GrayImage, radius: Int = 1) -> GrayImage {
        if radius <= 0 { return image }
        let w = image.width
        let h = image.height
        var out = image.pixels
        let src = image.pixels
        let window = (radius * 2 + 1) * (radius * 2 + 1)

        for y in 0..<h {
            for x in 0..<w {
                var sum = 0
                for ky in -radius...radius {
                    for kx in -radius...radius {
                        let nx = min(max(0, x + kx), w - 1)
                        let ny = min(max(0, y + ky), h - 1)
                        sum += Int(src[ny * w + nx])
                    }
                }
                out[y * w + x] = UInt8(sum / window)
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    static func otsuThreshold(_ image: GrayImage) -> UInt8 {
        var hist = [Int](repeating: 0, count: 256)
        for px in image.pixels {
            hist[Int(px)] += 1
        }

        let total = image.width * image.height
        var sum = 0.0
        for i in 0..<256 {
            sum += Double(i * hist[i])
        }

        var sumB = 0.0
        var wB = 0
        var maxVariance = 0.0
        var threshold = 127

        for i in 0..<256 {
            wB += hist[i]
            if wB == 0 { continue }
            let wF = total - wB
            if wF == 0 { break }

            sumB += Double(i * hist[i])
            let mB = sumB / Double(wB)
            let mF = (sum - sumB) / Double(wF)
            let variance = Double(wB * wF) * (mB - mF) * (mB - mF)
            if variance > maxVariance {
                maxVariance = variance
                threshold = i
            }
        }
        return UInt8(threshold)
    }

    static func binaryMask(_ image: GrayImage, threshold: UInt8) -> [UInt8] {
        image.pixels.map { px in
            px < threshold ? 1 : 0
        }
    }
}
