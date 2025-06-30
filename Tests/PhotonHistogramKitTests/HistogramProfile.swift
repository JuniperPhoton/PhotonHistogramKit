//
//  HistogramProfile.swift
//  PhotonHistogramKit
//
//  Created by juniperphoton on 2025/6/30.
//
import PhotonHistogramKit
import CoreImage
import Foundation
import Testing

/// You can use this test to profile the performance of the histogram calculation.
/// Right-click the testing checkmark and select "Profile" to run the test in Instruments.
@Test
func profileSampleImage() async throws {
    // Note: `Bundle.module` won't be generated unless you use the `process` method when declaring the resources.
    let imageURL = try #require(Bundle.module.url(forResource: "sample", withExtension: "jpg"))
    let ciImage = try #require(CIImage(contentsOf: imageURL))
    let originalSize = ciImage.extent.size
    let calculator = HistogramCalculator()
    let (histogramInfo, pixelCount) = try await calculator.calculateHistogramInfo(ciImage: ciImage)
    #expect(histogramInfo.count == 256 * 3)
    #expect(CGFloat(pixelCount) < CGFloat(originalSize.width * originalSize.height))
}
