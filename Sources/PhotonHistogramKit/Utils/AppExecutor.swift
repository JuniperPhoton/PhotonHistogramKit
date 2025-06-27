//
//  AppExecutor.swift
//  PhotonGPUImage
//
//  Created by JuniperPhoton on 2024/11/28.
//
import Foundation

final class AppExecutor: SerialExecutor {
    private let name: String
    private let queue: DispatchQueue
    
    init(name: String) {
        self.name = name
        // Don't use concurrent, which will hang on iPhone 12 with iOS 17.0.
        self.queue = DispatchQueue(label: name, qos: .userInteractive)
    }
    
    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
    
    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
