// BlurHash decoder for macOS
// Based on https://github.com/woltapp/blurhash
//
// Copyright (c) 2018 Wolt Enterprises
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

import AppKit

extension NSImage {
    /// Decodes a blurhash string into an NSImage of the given size.
    static func fromBlurHash(_ blurHash: String, size: CGSize, punch: Float = 1) -> NSImage? {
        guard blurHash.count >= 6 else { return nil }
        let chars = Array(blurHash)

        guard let sizeFlag = decode83(chars[0]) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        guard blurHash.count == 4 + 2 * numX * numY else { return nil }

        guard let quantisedMaximumValue = decode83(chars[1]) else { return nil }
        let maximumValue = Float(quantisedMaximumValue + 1) / 166

        var colours = [(Float, Float, Float)]()
        for i in 0..<(numX * numY) {
            if i == 0 {
                guard let value = decode83(Array(chars[2..<6])) else { return nil }
                colours.append(decodeDC(value))
            } else {
                let start = 4 + i * 2
                guard let value = decode83(Array(chars[start..<start + 2])) else { return nil }
                colours.append(decodeAC(value, maximumValue: maximumValue * punch))
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis = cos(Float.pi * Float(i) * Float(x) / Float(width))
                            * cos(Float.pi * Float(j) * Float(y) / Float(height))
                        let colour = colours[i + j * numX]
                        r += colour.0 * basis
                        g += colour.1 * basis
                        b += colour.2 * basis
                    }
                }
                let offset = 4 * (x + y * width)
                pixels[offset] = UInt8(linearTosRGB(r))
                pixels[offset + 1] = UInt8(linearTosRGB(g))
                pixels[offset + 2] = UInt8(linearTosRGB(b))
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cgImage, size: size)
    }
}

private let decodeCharacters: [Character: Int] = {
    let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-./:;=?@[]^_{|}~")
    return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })
}()

private func decode83(_ chars: [Character]) -> Int? {
    var value = 0
    for c in chars {
        guard let digit = decodeCharacters[c] else { return nil }
        value = value * 83 + digit
    }
    return value
}

private func decode83(_ char: Character) -> Int? {
    decodeCharacters[char]
}

private func decodeDC(_ value: Int) -> (Float, Float, Float) {
    (sRGBToLinear(value >> 16), sRGBToLinear((value >> 8) & 255), sRGBToLinear(value & 255))
}

private func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
    let qR = value / (19 * 19)
    let qG = (value / 19) % 19
    let qB = value % 19
    return (
        signPow((Float(qR) - 9) / 9, 2) * maximumValue,
        signPow((Float(qG) - 9) / 9, 2) * maximumValue,
        signPow((Float(qB) - 9) / 9, 2) * maximumValue
    )
}

private func signPow(_ value: Float, _ exp: Float) -> Float {
    copysign(pow(abs(value), exp), value)
}

private func linearTosRGB(_ value: Float) -> Int {
    let v = max(0, min(1, value))
    return v <= 0.0031308
        ? Int(v * 12.92 * 255 + 0.5)
        : Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
}

private func sRGBToLinear(_ value: Int) -> Float {
    let v = Float(value) / 255
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}
