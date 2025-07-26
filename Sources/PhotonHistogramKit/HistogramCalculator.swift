//
//  HistCalculator.swift
//  PhotonCam
//
//  Created by JuniperPhoton on 2024/11/27.
//
import CoreImage
import MetalPerformanceShaders
import SwiftUI

/// A type representing the histogram info.
/// It should be an array of `binCount` * 3 elements, where the first `binCount` elements represent the red channel,
/// the next `binCount` represent the green channel, and the last `binCount` represent the blue channel.
///
/// To know more about the underlying class, see `MPSImageHistogramInfo`.
public typealias HistogramInfo = [UInt32]

/// A class that calculates the histogram of a CIImage.
///
/// Use ``calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)`` to calculate the histogram info.
/// Then use ``split(histogramArray:binCount:pixelCount:)`` to split the result into red, green, and blue channels.
///
/// If you are rendering the histogram, you can use ``HistogramRenderView``.
///
/// Sample code:
/// ```swift
/// // Create and cache the calculator.
/// let calculator = HistogramCalculator()
///
/// // Calculate the histogram info.
/// let (histogramInfo, pixelCount) = try await calculator.calculateHistogramInfo(ciImage: ciImage)
///
/// // Split the histogram info into red, green, and blue channels.
/// let (red, green, blue) = try calculator.split(histogramArray: histogramInfo, pixelCount: pixelCount)
/// ```
///
/// The split result can be rendered using ``HistogramRenderView``.
///
/// > Note: This actor caches the reference of ``CIContext``, as it's a heavy object that can be reused.
public actor HistogramCalculator {
    /// The default bin count for the histogram.
    /// May be used in ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``
    public static let defaultBinCount = 256
    
    /// The default maximum size in pixel for the histogram calculation.
    /// May be used in ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``
    public static let defaultMaxSizeInPixel: CGFloat = 1000
    
    /// The default target color space to convert to when rendering the original CIImage to a Metal texture.
    /// When displaying the histogram, the target color space should be non-linear, as we are viewing the image in a
    /// non-linear display.
    public static let defaultTargetColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)!
    
    public struct IllegalStateException: Error {
        public let message: String
        
        init(message: String) {
            self.message = message
        }
    }
    
    /// A boolean value indicating whether the calculator is currently loading.
    /// This property is isolated to this actor, thus it is safe to access it from any task.
    public private(set) var isLoading = false
    
    private let device = MTLCreateSystemDefaultDevice()!
    private let ciContext: CIContext
    
    private var sourceTexture: MTLTexture?
    
    private let executor = AppExecutor(name: "hist_cal")
    
    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        self.executor.asUnownedSerialExecutor()
    }
    
    /// Create a new histogram calculator.
    public init() {
        ciContext = CIContext(mtlDevice: device)
    }
    
    /// Calculate and return the histogram info running on the GPU.
    ///
    /// This process runs on GPU, the result is copied from the GPU memory, which is safe to use on CPU.
    /// To check whether is loading a task, use the ``isLoading`` property.
    ///
    /// After getting the ``HistogramInfo``, you can use the ``splitNormalized(histogramArray:binCount:pixelCount:)``
    /// method to get the per-channel histogram info and use ``HistogramRenderView`` to display the result.
    ///
    /// - parameter ciImage: The CIImage to calculate the histogram of.
    /// - parameter targetColorSpace: See ``HistogramCalculator.defaultTargetColorSpace`` for more details.
    /// To avoid color matching, use the same color space of the input ciImage.
    /// - parameter maxHeadroom: The maximum headroom value in linear space. Default is `1.0`.
    /// - parameter maxSizeInPixel: The maximum size of the image for the histogram calculation. Default is `1000px`.
    /// The `CIImage` will be scaled down to a maximum of `maxSizeInPixel` for the longest side.
    /// Thus, the returned pixel count is the number of pixels in the scaled image (width x height).
    ///
    /// - parameter binCount: The bin count for the histogram calculation. Default is `256`.
    /// To getting better performance, you can set the `binCount` to a lower value.
    /// If you are drawing the histogram in a smaller view size, you can keep the bin count to a lower value like 32.
    ///
    /// - returns: A ``HistogramInfo`` containing the histogram info and the pixel count.
    /// The ``HistogramInfo`` is an array of 3 * `binCount`, where the first `binCount` elements represent the red channel,
    /// the next `binCount` represent the green channel, and the last `binCount` represent the blue channel.
    /// Each element represents the absolute count of that pixel in a bin.
    /// To normalize the result, use ``splitNormalized(histogramArray:binCount:pixelCount:)``.
    /// ![](HistInfo.jpg)
    ///
    /// - throws: An error if the calculation fails. To cancel the task, call `task.cancel()`.
    public func calculateHistogramInfo(
        ciImage: CIImage,
        targetColorSpace: CGColorSpace = HistogramCalculator.defaultTargetColorSpace,
        maxHeadroom: Float = 1.0,
        binCount: Int = HistogramCalculator.defaultBinCount,
        maxSizeInPixel: CGFloat = HistogramCalculator.defaultMaxSizeInPixel
    ) async throws -> (histogramInfo: HistogramInfo, pixelCount: Int) {
        self.isLoading = true
        
        defer {
            self.isLoading = false
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            guard let commandQueue = device.makeCommandQueue() else {
                LibLogger.defaultLogger.error("Failed to create Metal command queue")
                continuation.resume(throwing: IllegalStateException(message: "failed to create metal command queue"))
                return
            }
            
            let isHDR = maxHeadroom > 1
            
            guard let sourceTexture = createMetalTexture(
                from: ciImage,
                device: device,
                commandQueue: commandQueue,
                maxSizeInPixel: maxSizeInPixel,
                isHDR: isHDR,
                targetColorSpace: targetColorSpace
            ) else {
                LibLogger.defaultLogger.error("Failed to create Metal texture")
                continuation.resume(throwing: IllegalStateException(message: "Failed to create metal texture"))
                return
            }
            
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            self.sourceTexture = sourceTexture
            
            let maxPixelValue = max(log2(maxHeadroom), 1.0)
            
            var histogramInfo = MPSImageHistogramInfo(
                numberOfHistogramEntries: binCount,
                histogramForAlpha: false,
                minPixelValue: vector_float4(0, 0, 0, 0),
                maxPixelValue: vector_float4(
                    maxPixelValue,
                    maxPixelValue,
                    maxPixelValue,
                    1.0
                )
            )
            
            let calculation = MPSImageHistogram(
                device: device,
                histogramInfo: &histogramInfo
            )
            
            let bufferLength = calculation.histogramSize(forSourceFormat: sourceTexture.pixelFormat)
            let histogramInfoBuffer = device.makeBuffer(
                length: bufferLength,
                options: [.storageModeShared]
            )
            
            guard let histogramInfoBuffer else {
                LibLogger.defaultLogger.error("Failed to create Metal buffer")
                continuation.resume(throwing: IllegalStateException(message: "Failed to create metal buffer"))
                return
            }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                LibLogger.defaultLogger.error("Failed to create Metal command buffer")
                continuation.resume(throwing: IllegalStateException(message: "Failed to create metal command buffer"))
                return
            }
            
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            calculation.encode(
                to: commandBuffer,
                sourceTexture: sourceTexture,
                histogram: histogramInfoBuffer,
                histogramOffset: 0
            )
            
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            // Don't block the current thread wait for the command buffer to complete.
            // Instead, using the addCompletedHandler to get the result.
            // This way, during the commit call and the addCompletedHandler callback,
            // the current thread can continue to commit commands to the GPU.
            // See https://developer.apple.com/documentation/metalperformanceshaders/tuning_hints for more information.
            // Must add before the commit call: https://forums.developer.apple.com/forums/thread/729351
            commandBuffer.addCompletedHandler { _ in
                let histogramData = histogramInfoBuffer.contents().assumingMemoryBound(to: UInt32.self)
                
                let arrayPointer = UnsafeBufferPointer(start: histogramData, count: 3 * binCount)
                let histogramArray = Array(arrayPointer)
                
                continuation.resume(returning: (histogramArray, sourceTexture.width * sourceTexture.height))
            }
            
            commandBuffer.commit()
        }
    }
    
    /// Split and normalize the `HistogramInfo` into red, green, and blue channels.
    /// Each result channel will be normalized to the range of 0 to 255 and have count of `binCount`.
    /// ![](HistInfo.jpg)
    ///
    /// - parameter histogramArray: The histogram info to split returned by ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``.
    /// - parameter binCount: The bin count used in the histogram calculation. Must be the same as ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``.
    /// - parameter pixelCount: The pixel count returned by ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``.
    public nonisolated func splitNormalized(
        histogramArray: HistogramInfo,
        binCount: Int,
        pixelCount: Int
    ) async throws -> (red: HistogramInfo, green: HistogramInfo, blue: HistogramInfo) {
        guard histogramArray.count == binCount * 3 else {
            throw IllegalStateException(message: "Invalid histogram array size")
        }
        let redInfo = normalized(
            histogramArray: histogramArray,
            range: 0..<binCount,
            pixelCount: pixelCount,
            binCount: binCount
        )
        let greenInfo = normalized(
            histogramArray: histogramArray,
            range: binCount..<binCount * 2,
            pixelCount: pixelCount,
            binCount: binCount
        )
        let blueInfo = normalized(
            histogramArray: histogramArray,
            range: binCount * 2..<binCount * 3,
            pixelCount: pixelCount,
            binCount: binCount
        )
        return (redInfo, greenInfo, blueInfo)
    }
    
    private nonisolated func normalized(
        histogramArray: HistogramInfo,
        range: Range<Int>,
        pixelCount: Int,
        binCount: Int
    ) -> HistogramInfo {
        let averageBinCount = Float(pixelCount) / Float(binCount)
        var subArray = histogramArray[range]
        
        // We don't want to actually normalize the histogram by its total pixel count,
        // otherwise the histogram will be too small to see.
        // Some optimizations can be done here to improve the histogram viewport.
        let range = averageBinCount * 5
        
        for i in subArray.indices {
            let r = subArray[i]
            let fraction = (Double(r) - 0) / Double(range)
            subArray[i] = UInt32(255 * fraction.clamp(to: 0...1))
        }
        
        return Array(subArray)
    }
    
    private func createMetalTexture(
        from ciImage: CIImage,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        maxSizeInPixel: CGFloat,
        isHDR: Bool,
        targetColorSpace: CGColorSpace
    ) -> MTLTexture? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        let pixelFormat: MTLPixelFormat
        if isHDR {
            // For HDR images, use 16-bit float format.
            // This is a format without linear -> non-linear conversions.
            pixelFormat = MTLPixelFormat.rgba16Float
        } else {
            // Not a linear texture, so no conversion will be done when reading/writing to the texture.
            // This is a format without linear -> non-linear conversions.
            pixelFormat = MTLPixelFormat.bgra8Unorm
        }
        
        let scale = min(maxSizeInPixel / ciImage.extent.width, maxSizeInPixel / ciImage.extent.height)
        
        let scaledImage: CIImage
        if scale < 1.0 {
            scaledImage = ciImage.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale),
                highQualityDownsample: false
            )
        } else {
            scaledImage = ciImage
        }
        
        let width = Int(scaledImage.extent.width)
        let height = Int(scaledImage.extent.height)
        
        let outputTexture: MTLTexture?
        if let sourceTexture, sourceTexture.width == width && sourceTexture.height == height && sourceTexture.pixelFormat == pixelFormat {
            outputTexture = sourceTexture
        } else {
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.pixelFormat = pixelFormat
            textureDescriptor.width = width
            textureDescriptor.height = height
            textureDescriptor.storageMode = .private
            textureDescriptor.usage = [.shaderWrite, .shaderRead]
            outputTexture = device.makeTexture(descriptor: textureDescriptor)
        }
        
        guard let outputTexture else {
            LibLogger.defaultLogger.error("Failed to create Metal texture")
            return nil
        }
        
        ciContext.render(
            scaledImage,
            to: outputTexture,
            commandBuffer: commandBuffer,
            bounds: scaledImage.extent,
            // We should always render to a non-linear color space, (the MTLPixelFormat should also match this)
            // since we see the image on the display in a non-linear color space.
            colorSpace: targetColorSpace
        )
        
        // No need to wait for the command buffer to complete
        commandBuffer.commit()
        return outputTexture
    }
    
    private func create2x1MetalTexture(
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = pixelFormat
        textureDescriptor.width = 2
        textureDescriptor.height = 1
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            LibLogger.defaultLogger.error("Failed to create Metal texture")
            return nil
        }
        
        return texture
    }
    
    private func get2x1TextureBytes(texture: MTLTexture) -> [UInt8]? {
        // Ensure the texture is in the `bgra8Unorm` format
        guard texture.pixelFormat == .bgra8Unorm, texture.storageMode == .shared else {
            print("Unsupported pixel format")
            return nil
        }
        
        // Get texture dimensions
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4 // For bgra8Unorm, each pixel is 4 bytes
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height
        
        // Create a Swift array to hold the data
        var pixelData = [UInt8](repeating: 0, count: bufferSize)
        
        // Define the region to read from (entire texture)
        let region = MTLRegion(
            origin: MTLOrigin(
                x: 0,
                y: 0,
                z: 0
            ),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        
        // Copy the texture data into the array
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )
        
        return pixelData
    }
}
