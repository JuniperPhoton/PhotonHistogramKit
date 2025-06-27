//
//  HistogramRenderView.swift
//  PhotonCam
//
//  Created by JuniperPhoton on 2024/11/27.
//
import SwiftUI

/// A `SwiftUI` view that renders a histogram info, which can be calculated from the ``HistogramCalculator`` class.
///
/// The size of this view is specified by the user. The content will be stretched to fill the size.
/// To set the display preference for this view, use the ``HistogramRenderView/Options``.
///
/// ![](hist.jpg)
///
/// > Warning: To get better performance, you shouldn't set `drawingGroup()` to this view.
/// Doing so will result in an increase of memory.
///
/// Sample code:
/// ```swift
/// HistogramRenderView(
///     redInfo: viewModel.redInfo,
///     greenInfo: viewModel.greenInfo,
///     blueInfo: viewModel.blueInfo,
///     options: HistogramRenderView.Options(
///         displayChannels: displayChannels,
///         dynamicRange: dynamicRange,
///         drawAuxiliary: drawAuxiliary,
///         backgroundColor: backgroundColor
///     )
/// ).frame(width: 100, height: 50)
/// ```
public struct HistogramRenderView: View {
    static let sdrPartRatio = 0.7
    static let hdrPartRatio = 0.3
    
    /// Display channels.
    ///
    /// Use this option set to specify which channels to display.
    ///
    /// You can use ``all`` to display all channels, or combine them as you like.
    ///
    /// ```swift
    /// let channels = [DisplayChannel.red, .green]
    /// ```
    public struct DisplayChannel: OptionSet {
        public static var red: DisplayChannel { DisplayChannel(rawValue: 1 << 0) }
        public static var green: DisplayChannel { DisplayChannel(rawValue: 1 << 1) }
        public static var blue: DisplayChannel { DisplayChannel(rawValue: 1 << 2) }
        public static var luminance: DisplayChannel { DisplayChannel(rawValue: 1 << 3) }
        
        public static var all: DisplayChannel { [.red, .green, .blue, .luminance] }
        
        public var rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    public enum DynamicRange {
        /// Standard dynamic range.
        case sdr
        
        /// High dyanmic range with a white point and stops count.
        ///
        /// The parameter should be the fraction of the white point in SDR mode.
        /// It should be in the range of 0 to 1 accordingly.
        ///
        /// For example, if the current HDR stops is 1 stop(with linear headroom of 2), which means that the image can be
        /// two times brighter than the white point in SDR mode, you should set the value to 0.5.
        ///
        /// The final rendering will use intepolation to even the SDR and HDR parts.
        case hdr(sdrWhitePointFraction: CGFloat, stops: Int)
    }
    
    /// Options for rendering the histogram.
    public struct Options {
        /// Display channels. This is a combination of ``HistogramRenderView/DisplayChannel``.
        public var displayChannels: DisplayChannel
        
        /// The dynamic range to render. If the image to calculate in the ``HistogramCalculator/calculateHistogramInfo(ciImage:maxHeadroom:binCount:maxSizeInPixel:)``
        /// is HDR, you should set this to `.hdr` with the correct white point value.
        public var dynamicRange: DynamicRange
        
        /// Whether to draw auxiliary lines.
        public var drawAuxiliary: Bool
        
        /// The background color of the histogram.
        public var backgroundColor: Color
        
        /// The color of the auxiliary lines.
        public var auxliaryColor: Color
        
        /// Creates an options object.
        public init(
            displayChannels: DisplayChannel = .all,
            dynamicRange: DynamicRange = .sdr,
            drawAuxiliary: Bool = true,
            backgroundColor: Color = Color.gray.opacity(0.2),
            auxliaryColor: Color = Color.gray.opacity(0.6)
        ) {
            self.displayChannels = displayChannels
            self.dynamicRange = dynamicRange
            self.drawAuxiliary = drawAuxiliary
            self.backgroundColor = backgroundColor
            self.auxliaryColor = auxliaryColor
        }
    }
    
    private let redInfo: HistogramInfo?
    private let greenInfo: HistogramInfo?
    private let blueInfo: HistogramInfo?
    private let options: Options
    
    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
    }
    
    /// Creates a histogram render view. Each information for channel contains the normalized value of the histogram.
    /// That's, the value should be in the range of 0 to 255.
    ///
    /// - parameters redInfo: The information of the red channel.
    /// - parameters greenInfo: The information of the green channel.
    /// - parameters blueInfo: The information of the blue channel.
    /// - parameters options: The options for rendering the histogram.
    public init(
        redInfo: HistogramInfo?,
        greenInfo: HistogramInfo?,
        blueInfo: HistogramInfo?,
        options: Options = Options()
    ) {
        self.redInfo = redInfo
        self.greenInfo = greenInfo
        self.blueInfo = blueInfo
        self.options = options
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(options.backgroundColor)
                
                if let redInfo, options.displayChannels.contains(.red) {
                    let path = createPath(for: redInfo, size: proxy.size)
                    path.stroke(.red, style: strokeStyle)
                    path.fill(.red.opacity(0.2))
                }
                
                if let greenInfo, options.displayChannels.contains(.green) {
                    let path = createPath(for: greenInfo, size: proxy.size)
                    path.stroke(.green, style: strokeStyle)
                    path.fill(.green.opacity(0.2))
                }
                
                if let blueInfo, options.displayChannels.contains(.blue) {
                    let path = createPath(for: blueInfo, size: proxy.size)
                    path.stroke(.blue, style: strokeStyle)
                    path.fill(.blue.opacity(0.2))
                }
                
                if let redInfo, let greenInfo, let blueInfo, options.displayChannels.contains(.luminance) {
                    if let path = createPath(for: redInfo, for: greenInfo, for: blueInfo, size: proxy.size) {
                        path.stroke(.white, style: strokeStyle)
                        path.fill(.white.opacity(0.2))
                    }
                }
                
                if options.drawAuxiliary {
                    switch options.dynamicRange {
                    case .hdr(_, let stopsCount) where stopsCount >= 1:
                        createWhitePointPath(size: proxy.size, HistogramRenderView.sdrPartRatio)
                            .stroke(options.auxliaryColor, style: .init(lineWidth: 1, dash: []))
                        
                        ForEach(createHDRStops(HistogramRenderView.sdrPartRatio, stops: stopsCount), id: \.self) { position in
                            createLine(size: proxy.size, at: position)
                                .stroke(options.auxliaryColor, style: .init(lineWidth: 1, dash: [2]))
                        }
                    default:
                        ForEach([0.2, 0.5, 0.8], id: \.self) { position in
                            createLine(size: proxy.size, at: position)
                                .stroke(options.auxliaryColor, style: .init(lineWidth: 1, dash: [2]))
                        }
                    }
                }
            }
        }
    }
    
    private func createLine(size: CGSize, at position: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: size.width * position, y: 0))
        path.addLine(to: CGPoint(x: size.width * position, y: size.height))
        return path
    }
    
    private func createHDRStops(_ sdrWhitePointFraction: CGFloat, stops: Int) -> [CGFloat] {
        if sdrWhitePointFraction == 1.0 || stops <= 2 {
            return []
        }
        let hdrRange = 1 - sdrWhitePointFraction
        let gap = hdrRange / CGFloat(stops)
        var positions = [CGFloat]()
        for i in 1...(stops - 1) {
            positions.append(sdrWhitePointFraction + gap * CGFloat(i))
        }
        return positions
    }
    
    private func createWhitePointPath(size: CGSize, _ sdrWhitePointFraction: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: size.width * sdrWhitePointFraction, y: 0))
        path.addLine(to: CGPoint(x: size.width * sdrWhitePointFraction, y: size.height))
        return path
    }
    
    private func createPath(count: Int, size: CGSize, getFraction: (Int) -> CGFloat) -> Path {
        var path = Path()
        
        var x = 0.0
        path.move(to: CGPoint(x: x, y: size.height))
        
        let barWidth = size.width / CGFloat(count)
        
        for i in 0..<count {
            let fraction = getFraction(i)
            path.addLine(to: CGPoint(x: x, y: size.height - size.height * fraction))
            x += barWidth
        }
        
        path.addLine(to: CGPoint(x: x, y: size.height))
        
        return path
    }
    
    private func createPath(for infoData: [UInt32], size: CGSize) -> Path {
        switch options.dynamicRange {
        case .hdr(let whitePointFraction, let stopsCount) where whitePointFraction < 1 && stopsCount >= 1:
            let sdrCount = Int(CGFloat(infoData.count) * whitePointFraction)
            let hdrCount = infoData.count - Int(sdrCount)
            if hdrCount == 0 {
                fallthrough
            }
            let sdrRange = 0...(sdrCount - 1)
            let hdrRange = sdrCount...(infoData.count - 1)
            let allCount = (sdrCount + hdrCount) / 2
            
            return createPath(count: allCount, size: size) { i in
                let f = CGFloat(i) / CGFloat(allCount)
                if f < HistogramRenderView.sdrPartRatio {
                    let sdrF = CGFloat(sdrCount) * (f / HistogramRenderView.sdrPartRatio)
                    return infoData.normalized(at: sdrF, range: sdrRange)
                } else {
                    let hdrF = CGFloat(sdrCount) + CGFloat(hdrCount) * ((f - HistogramRenderView.sdrPartRatio) / HistogramRenderView.hdrPartRatio)
                    return infoData.normalized(at: hdrF, range: hdrRange)
                }
            }
        default:
            return createPath(count: infoData.count, size: size) { i in
                CGFloat(infoData[i]) / 255.0
            }
        }
    }
    
    private func createPath(for redInfo: [UInt32], for greenInfo: [UInt32], for blueInfo: [UInt32], size: CGSize) -> Path? {
        guard redInfo.count == greenInfo.count, greenInfo.count == blueInfo.count, redInfo.count > 0 else {
            return nil
        }
        
        switch options.dynamicRange {
        case .hdr(let whitePointFraction, let stopsCount) where whitePointFraction < 1 && stopsCount >= 1:
            // The whitePointFraction may be too big for the current histogram.
            // To make the view look better, we use intepolation to even the SDR and HDR parts.
            let sdrCount = Int(CGFloat(redInfo.count) * whitePointFraction)
            let hdrCount = redInfo.count - Int(sdrCount)
            
            if hdrCount == 0 {
                fallthrough
            }
            
            let sdrRange = 0...(sdrCount - 1)
            let hdrRange = sdrCount...(redInfo.count - 1)
            
            let allCount = (sdrCount + hdrCount) / 2
            
            return createPath(count: allCount, size: size) { i in
                let f = CGFloat(i) / CGFloat(allCount)
                if f < HistogramRenderView.sdrPartRatio {
                    let sdrF = CGFloat(sdrCount) * (f / HistogramRenderView.sdrPartRatio)
                    let red = redInfo.normalized(at: sdrF, range: sdrRange)
                    let green = greenInfo.normalized(at: sdrF, range: sdrRange)
                    let blue = blueInfo.normalized(at: sdrF, range: sdrRange)
                    return toL(red: red, green: green, blue: blue)
                } else {
                    let hdrF = CGFloat(sdrCount) + CGFloat(hdrCount) * ((f - HistogramRenderView.sdrPartRatio) / HistogramRenderView.hdrPartRatio)
                    let red = redInfo.normalized(at: hdrF, range: hdrRange)
                    let green = greenInfo.normalized(at: hdrF, range: hdrRange)
                    let blue = blueInfo.normalized(at: hdrF, range: hdrRange)
                    return toL(red: red, green: green, blue: blue)
                }
            }
        default:
            return createPath(count: greenInfo.count, size: size) { i in
                let red = CGFloat(redInfo[i]) / 255.0
                let green = CGFloat(greenInfo[i]) / 255.0
                let blue = CGFloat(blueInfo[i]) / 255.0
                return toL(red: red, green: green, blue: blue)
            }
        }
    }
    
    private func toL(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

extension [UInt32] {
    func normalized(at index: CGFloat, range: ClosedRange<Int>) -> CGFloat {
        let intIndex = Int(index).clamp(to: range)
        
        if abs(index - CGFloat(intIndex)) < 0.0001 {
            return CGFloat(self[intIndex]) / 255.0
        }
        
        let beforeIndex = (intIndex - 1).clamp(to: range)
        let afterIndex = (intIndex + 1).clamp(to: range)
        
        let beforeValue = CGFloat(self[beforeIndex])
        let currentValue = CGFloat(self[intIndex])
        let afterValue = CGFloat(self[afterIndex])
        
        return (beforeValue + currentValue + afterValue) / 3.0 / 255.0
    }
}

@available(iOS 17, macOS 14, *)
#Preview {
    @Previewable @State var red: [UInt32] = []
    @Previewable @State var green: [UInt32] = []
    @Previewable @State var blue: [UInt32] = []
    
    VStack(spacing: 0) {
        HistogramRenderView(
            redInfo: red,
            greenInfo: green,
            blueInfo: blue,
            options: .init(
                displayChannels: [.red, .green, .blue],
                dynamicRange: .sdr,
                drawAuxiliary: true,
                backgroundColor: Color.gray.opacity(0.2),
                auxliaryColor: Color.gray.opacity(0.6)
            )
        ).frame(width: 300, height: 50)
        
        HistogramBottomLabelView(
            barFillStyle: .black,
            labelForegroundStyle: .white,
            displayHDRPart: false
        )
        .frame(width: 300)
    }.onAppear {
        red = Array(repeating: 0, count: 30).map { _ in UInt32.random(in: 0...255) }
        green = Array(repeating: 0, count: 30).map { _ in UInt32.random(in: 0...255) }
        blue = Array(repeating: 0, count: 30).map { _ in UInt32.random(in: 0...255) }
    }
}
