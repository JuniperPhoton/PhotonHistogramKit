//
//  Observations.swift
//  ObservationTest
//
//  Created by juniperphoton on 2025/7/26.
//
import Foundation
import Observation

/// Provides a way to observe value changes in a closure using ``AsyncSequence``,
/// just like the [Observations](https://developer.apple.com/documentation/observation/observations) introduced in iOS 26 lineup.
///
/// - Parameters:
///     - action: A closure that returns a value to observe. It must read one or more values in an object with `@Observable` macro.
/// - Returns: An `AsyncSequence` that yields the value returned by the action closure when it changes.
@available(iOS 17.0, macOS 14.0, *)
func observations<V>(
    action: @escaping () -> (V)
) -> AsyncStream<V> {
    AsyncStream { continuation in
        var yieldedFirst = false
        withObservationTrackingInLoop(action: action) { value in
            // The first emitted value will be yielded immediately,
            // subsequent values will be yielded on change.
            if !yieldedFirst {
                yieldedFirst = true
            } else {
                continuation.yield(value)
            }
        }
    }
}

/// A withObservationTracking wrapper that will execute the same method in the current loop when the value changes.
@available(iOS 17.0, macOS 14.0, *)
func withObservationTrackingInLoop<V>(
    action: @escaping () -> (V),
    _ onChanged: @escaping (V) -> Void
) {
    // The action will be executed right away and return a value.
    let value = withObservationTracking {
        action()
    } onChange: {
        // This closure will be called whenever the value changes.
        // Then we schedule the onChanged closure to run on the same loop,
        // which will trigger the onChanged closure again.
        RunLoop.current.perform(inModes: [.common]) {
            withObservationTrackingInLoop(action: action, onChanged)
        }
    }
    // Call onChanged with the initial value.
    onChanged(value)
}
