//
//  ContentView.swift
//  HistogramSampleApp
//
//  Created by juniperphoton on 2025/7/26.
//
import SwiftUI
import PhotonHistogramKit
import PhotonMetalDisplayCore
import AsyncAlgorithms
import CoreImage.CIFilterBuiltins

@Observable
class HistogramInfoState {
    var redInfo: HistogramInfo?
    var greenInfo: HistogramInfo?
    var blueInfo: HistogramInfo?
    
    func update(red: HistogramInfo?, green: HistogramInfo?, blue: HistogramInfo?) {
        self.redInfo = red
        self.greenInfo = green
        self.blueInfo = blue
    }
}

@Observable
class ImageEffects {
    var ev: Float = 0.0
    var contrast: Float = 1.0
    
    var asyncSequence: some AsyncSequence {
        observations { [unowned self] in
            // Any properties that should yield changes must be accessed here.
            // Though we don't actually care about the values, so here we return void.
            let _ = self.ev
            let _ = self.contrast
        }
    }
    
    /// As for histogram purpose, we throttle the sequence to avoid too frequent updates,
    /// which can improve performance and reduce unnecessary calculations.
    var throttledSequence: some AsyncSequence {
        asyncSequence._throttle(for: .milliseconds(1000 / 60))
    }
}

struct ContentView: View {
    @State private var imageEffects = ImageEffects()
    @State private var histogramInfo = HistogramInfoState()
    @State private var inputImage: CIImage?
    @State private var outputImage: CIImage?
    @State private var calculator = HistogramCalculator()
    @StateObject private var renderer = MetalRenderer()

    var body: some View {
        VStack {
            AppHistogramView(histogramInfoState: histogramInfo)
                .aspectRatio(3, contentMode: .fit)
            MetalView(renderer: renderer, renderMode: .renderWhenDirty)
            ImageEffectsAdjustmentsView(imageEffects: imageEffects)
        }
        .padding()
        .task {
            await setupContext()
            await setupImage()
            setupImageEffects()
            requestUpdateImage()
            await calculateHistogram()
            
            Task {
                do {
                    for try await _ in imageEffects.asyncSequence {
                        setupImageEffects()
                        requestUpdateImage()
                    }
                } catch {
                    print("Error in throttled sequence: \(error)")
                }
            }
            
            Task {
                do {
                    for try await _ in imageEffects.throttledSequence {
                        setupImageEffects()
                        await calculateHistogram()
                    }
                } catch {
                    print("Error in throttled sequence: \(error)")
                }
            }
        }
    }
    
    private func setupContext() async {
        renderer.initializeCIContext(colorSpace: nil, name: "preview")
    }
    
    private func setupImage() async {
        guard let url = Bundle.main.url(forResource: "sample01", withExtension: "jpeg") else {
            print("Image not found")
            return
        }
        let inputImage = CIImage(contentsOf: url)
        self.inputImage = inputImage
    }
    
    private func requestUpdateImage() {
        guard let outputImage = outputImage ?? inputImage else {
            print("Input image is not set")
            return
        }
        
        renderer.requestChanged(displayedImage: outputImage)
    }
    
    private func setupImageEffects() {
        guard let inputImage = inputImage else {
            print("Input image is not set")
            return
        }
        
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = inputImage
        filter.ev = imageEffects.ev
        
        guard let evOutputImage = filter.outputImage else {
            return
        }
        
        let controlFilter = CIFilter.colorControls()
        controlFilter.inputImage = evOutputImage
        controlFilter.contrast = imageEffects.contrast
        
        guard let outputImage = controlFilter.outputImage else {
            return
        }
        
        self.outputImage = outputImage
    }
    
    private func calculateHistogram() async {
        guard let outputImage = outputImage else {
            print("Input image is not set")
            return
        }
        
        do {
            let (info, pixelCount) = try await calculator.calculateHistogramInfo(ciImage: outputImage)
            let (r, g, b) = try await calculator.splitNormalized(
                histogramArray: info,
                binCount: HistogramCalculator.defaultBinCount,
                pixelCount: pixelCount
            )
            
            self.histogramInfo.update(red: r, green: g, blue: b)
        } catch {
            print("calculateHistogram error: \(error)")
        }
    }
}

struct ImageEffectsAdjustmentsView: View {
    @Bindable var imageEffects: ImageEffects
    
    var body: some View {
        Slider(value: $imageEffects.ev, in: -1...1) {
            Text("Ev: \(imageEffects.ev, specifier: "%.2f")")
        }
        
        Slider(value: $imageEffects.contrast, in: 0.8...1.2) {
            Text("Contrast: \(imageEffects.contrast, specifier: "%.2f")")
        }
    }
}

struct AppHistogramView: View {
    var histogramInfoState: HistogramInfoState
    
    @State private var showRed = true
    @State private var showGreen = true
    @State private var showBlue = true
    @State private var showLuminance = true
    
    var body: some View {
        VStack {
            HistogramRenderView(
                redInfo: histogramInfoState.redInfo,
                greenInfo: histogramInfoState.greenInfo,
                blueInfo: histogramInfoState.blueInfo,
                options: HistogramRenderView.Options(displayChannels: channels)
            )
            
            HStack {
                Toggle("R", isOn: $showRed)
                Toggle("G", isOn: $showGreen)
                Toggle("B", isOn: $showBlue)
                Toggle("L", isOn: $showLuminance)
            }
        }
    }
    
    private var channels: HistogramRenderView.DisplayChannel {
        var channels: HistogramRenderView.DisplayChannel = []
        if showRed {
            channels.insert(.red)
        }
        if showGreen {
            channels.insert(.green)
        }
        if showBlue {
            channels.insert(.blue)
        }
        if showLuminance {
            channels.insert(.luminance)
        }
        return channels
    }
}
