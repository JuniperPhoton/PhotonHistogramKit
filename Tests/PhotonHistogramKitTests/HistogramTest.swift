//
//  HistogramTest.swift
//  PhotonGPUImage
//
//  Created by juniperphoton on 2025/6/27.
//
import PhotonHistogramKit
import CoreImage
import Foundation
import Testing

@Test
func testHistogramCalculatorBasic() async throws {
    let calculator = HistogramCalculator()
    let ciImage = makeSolidCIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
    let (histogramInfo, pixelCount) = try await calculator.calculateHistogramInfo(
        ciImage: ciImage,
        binCount: 16
    )
    #expect(histogramInfo.count == 16 * 3)
    #expect(pixelCount == 100)
}

@Test
func testHistogramCalculatorSplitNormalized() async throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let calculator = HistogramCalculator()
    let ciImage = makeSolidCIImage(
        color: CIColor(
            red: 0,
            green: 1,
            blue: 0,
            alpha: 1,
            colorSpace: colorSpace
        )!,
    )
    let (histogramInfo, pixelCount) = try await calculator.calculateHistogramInfo(
        ciImage: ciImage,
        targetColorSpace: colorSpace,
        binCount: 8
    )
    let (red, green, blue) = try await calculator.splitNormalized(
        histogramArray: histogramInfo,
        binCount: 8,
        pixelCount: pixelCount
    )
    #expect(red.count == 8)
    #expect(green.count == 8)
    #expect(blue.count == 8)
    #expect(red == [255, 0, 0, 0, 0, 0, 0, 0])
    #expect(green == [0, 0, 0, 0, 0, 0, 0, 255])
    #expect(blue == [255, 0, 0, 0, 0, 0, 0, 0])
}

@Test
func testHistogramCalculatorColorSpaceNotMatching() async throws {
    let calculator = HistogramCalculator()
    let ciImage = makeSolidCIImage(
        color: CIColor(
            red: 0,
            green: 1,
            blue: 0,
            alpha: 1,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )!,
    )
    let (histogramInfo, pixelCount) = try await calculator.calculateHistogramInfo(
        ciImage: ciImage,
        targetColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
        binCount: 8
    )
    let (red, green, blue) = try await calculator.splitNormalized(
        histogramArray: histogramInfo,
        binCount: 8,
        pixelCount: pixelCount
    )
    #expect(red.count == 8)
    #expect(green.count == 8)
    #expect(blue.count == 8)
    
    // Converting sRGB green to Display P3 will result in a different distribution.
    // sRGB Green (R=0,G=255,B=0) -> Display P3 Green (R=117,G=251,B=76)
    #expect(red == [0, 0, 0, 255, 0, 0, 0, 0])
    #expect(green == [0, 0, 0, 0, 0, 0, 0, 255])
    #expect(blue == [0, 0, 255, 0, 0, 0, 0, 0])
}

private func makeSolidCIImage(color: CIColor, size: CGSize = CGSize(width: 10, height: 10)) -> CIImage {
    return CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
}
