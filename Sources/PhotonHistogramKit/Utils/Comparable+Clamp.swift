//
//  Comparable+Clamp.swift
//  PhotonHistogramKit
//
//  Created by juniperphoton on 2025/6/27.
//
import Foundation

extension Comparable {
    /// Clamps the integer to a specified range.
    /// - Parameter range: The range to clamp to.
    /// - Returns: The clamped value.
    func clamp(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound {
            return range.lowerBound
        } else if self > range.upperBound {
            return range.upperBound
        } else {
            return self
        }
    }
}
