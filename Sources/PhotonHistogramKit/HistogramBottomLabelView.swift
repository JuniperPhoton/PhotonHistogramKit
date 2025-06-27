//
//  HistogramBottomLabelView.swift
//  PhotonGPUImage
//
//  Created by JuniperPhoton on 2024/12/1.
//
import SwiftUI

/// A view to display the bottom label of the histogram.
///
/// The left part of the label is for the SDR part, and the right part is for the HDR part.
///
/// The width of the SDR part is the width of
///
/// ```swift
/// view.width * sdrWhitePointFraction.
/// ```
///
/// This view uses `GeometryReader` internally, you can use the `fixSize(horizontal:vertical:)`
/// method to fix the size of this view. Normally you would like to fix the vertical size.
///
/// You can use the standard SwiftUI method to set the font and foreground style of the label.
///
/// ```swift
/// HistogramBottomLabelView(barFillStyle: Color.white)
///     .frame(width: 270)
///     .font(.system(size: 9).bold())
///     .fixedSize(horizontal: false, vertical: true)
/// ```
public struct HistogramBottomLabelView<BarFillStyle: ShapeStyle, LabelForegroundStyle: ShapeStyle>: View {
    /// The fill style of the horizontal bar.
    var barFillStyle: BarFillStyle
    
    /// The forground style of the label.
    var labelForegroundStyle: LabelForegroundStyle
    
    /// Whether to display the HDR part or not.
    var displayHDRPart: Bool
    
    @State private var sdrHeight: CGFloat? = nil
    @State private var hdrHeight: CGFloat? = nil
    
    /// Create a view with the given SDR white point fraction.
    ///
    /// - parameter barFillStyle: The fill style of the horizontal bar.
    /// - parameter labelForegroundStyle: The forground style of the label.
    public init(
        barFillStyle: BarFillStyle = .white,
        labelForegroundStyle: LabelForegroundStyle = .clear,
        displayHDRPart: Bool = true
    ) {
        self.barFillStyle = barFillStyle
        self.labelForegroundStyle = labelForegroundStyle
        self.displayHDRPart = displayHDRPart
    }
    
    public var body: some View {
        ZStack {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Text("SDR")
                        .frame(width: (proxy.size.width - gap) * sdrWhitePointFraction)
                        .onGeometryChange(for: CGFloat.self, of: { proxy in
                            proxy.size.height
                        }, action: { newValue in
                            if sdrHeight != newValue {
                                sdrHeight = newValue
                            }
                        })
                    
                    if displayHDRPart {
                        Rectangle().fill(labelForegroundStyle)
                            .frame(width: gap, height: barHeight)
                        
                        Text("HDR")
                            .frame(width: (proxy.size.width - gap) * (1 - sdrWhitePointFraction))
                            .onGeometryChange(for: CGFloat.self, of: { proxy in
                                proxy.size.height
                            }, action: { newValue in
                                if hdrHeight != newValue {
                                    hdrHeight = newValue
                                }
                            })
                    }
                }.foregroundStyle(labelForegroundStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .background {
                        HStack(spacing: gap) {
                            Rectangle().fill(barFillStyle)
                                .frame(width: (proxy.size.width - gap) * sdrWhitePointFraction, height: barHeight)
                            Rectangle().fill(barFillStyle)
                                .frame(width: (proxy.size.width - gap) * (1 - sdrWhitePointFraction), height: barHeight)
                        }
                    }
            }
        }.fixedSize(horizontal: false, vertical: true)
            .animation(.default, value: displayHDRPart)
    }
    
    private var sdrWhitePointFraction: CGFloat {
        displayHDRPart ? HistogramRenderView.sdrPartRatio : 1.0
    }
    
    private var barHeight: CGFloat? {
        if let sdrHeight = sdrHeight, let hdrHeight = hdrHeight {
            return max(sdrHeight, hdrHeight)
        } else {
            return nil
        }
    }
    
    private var gap: CGFloat {
        return sdrWhitePointFraction < 1 ? 1 : 0
    }
}

#Preview {
    VStack {
        HistogramBottomLabelView(
            barFillStyle: .white,
            labelForegroundStyle: .black
        ).fixedSize(horizontal: false, vertical: true)
        
        HistogramBottomLabelView(
            barFillStyle: .black,
            labelForegroundStyle: .white
        ).fixedSize(horizontal: false, vertical: true)
        
        HistogramBottomLabelView(
            barFillStyle: .regularMaterial,
            labelForegroundStyle: Color.primary
        ).fixedSize(horizontal: false, vertical: true)
        
        HistogramBottomLabelView(
            barFillStyle: .regularMaterial,
            labelForegroundStyle: Color.primary
        ).frame(width: 270).fixedSize(horizontal: false, vertical: true)
    }.padding().background(.black).font(.footnote.bold())
}
