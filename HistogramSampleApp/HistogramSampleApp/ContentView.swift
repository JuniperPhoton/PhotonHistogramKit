//
//  ContentView.swift
//  HistogramSampleApp
//
//  Created by juniperphoton on 2025/7/26.
//
import SwiftUI
import PhotonHistogramKit
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
    @State private var calculator = HistogramCalculator()
    
    var body: some View {
        VStack {
            AppHistogramView(histogramInfoState: histogramInfo)
                .aspectRatio(3, contentMode: .fit)
            
            Slider(value: $imageEffects.ev, in: -1...1) {
                Text("Ev: \(imageEffects.ev, specifier: "%.2f")")
            }
            
            Slider(value: $imageEffects.contrast, in: 0.8...1.2) {
                Text("Contrast: \(imageEffects.contrast, specifier: "%.2f")")
            }
        }
        .padding()
        .task {
            await setupImage()
            await calculateHistogram()
            
            do {
                // Observe changes in image effects and update histogram accordingly.
                // If you need to observe changes in other async sequence,
                // you should create a new task using `Task { @MainActor in ... }` to do the same logic below.
                for try await _ in imageEffects.throttledSequence {
                    await calculateHistogram()
                }
            } catch {
                print("Error in throttled sequence: \(error)")
            }
        }
    }
    
    private func setupImage() async {
        guard let url = Bundle.main.url(forResource: "sample01", withExtension: "jpeg") else {
            print("Image not found")
            return
        }
        let inputImage = CIImage(contentsOf: url)
        self.inputImage = inputImage
    }
    
    private func calculateHistogram() async {
        guard let inputImage = inputImage else {
            print("Input image is not set")
            return
        }
        
        do {
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

struct AppHistogramView: View {
    var histogramInfoState: HistogramInfoState
    
    var body: some View {
        HistogramRenderView(
            redInfo: histogramInfoState.redInfo,
            greenInfo: histogramInfoState.greenInfo,
            blueInfo: histogramInfoState.blueInfo
        )
    }
}
