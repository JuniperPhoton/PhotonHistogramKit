//
//  ContentView.swift
//  HistogramSampleApp
//
//  Created by juniperphoton on 2025/7/26.
//
import SwiftUI
import PhotonHistogramKit
import CoreImage.CIFilterBuiltins
import Combine

class HistogramInfoState: ObservableObject {
    @Published var redInfo: HistogramInfo?
    @Published var greenInfo: HistogramInfo?
    @Published var blueInfo: HistogramInfo?
    
    func update(red: HistogramInfo?, green: HistogramInfo?, blue: HistogramInfo?) {
        self.redInfo = red
        self.greenInfo = green
        self.blueInfo = blue
    }
}

class ImageEffects: ObservableObject {
    @Published var ev: Float = 0.0
    
    var throttled: some Publisher<(), Never> {
        self.objectWillChange.throttle(
            for: .milliseconds(1000 / 60),
            scheduler: DispatchQueue.main,
            latest: true
        )
    }
}

struct ContentView: View {
    @StateObject private var imageEffects = ImageEffects()
    @StateObject private var histogramInfo = HistogramInfoState()
    @State private var inputImage: CIImage?
    @State private var calculator = HistogramCalculator()
    
    var body: some View {
        VStack {
            AppHistogramView(histogramInfoState: histogramInfo)
                .aspectRatio(3, contentMode: .fit)
            
            Slider(value: $imageEffects.ev, in: -1...1) {
                Text("Ev: \(imageEffects.ev, specifier: "%.2f")")
            }
        }
        .padding()
        .onReceive(imageEffects.throttled) { _ in
            Task {
                await calculateHistogram()
            }
        }
        .task {
            await setupImage()
            await calculateHistogram()
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
            guard let outputImage = filter.outputImage else {
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
    @ObservedObject var histogramInfoState: HistogramInfoState
    
    var body: some View {
        HistogramRenderView(
            redInfo: histogramInfoState.redInfo,
            greenInfo: histogramInfoState.greenInfo,
            blueInfo: histogramInfoState.blueInfo
        )
    }
}
