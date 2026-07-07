//
//  HapticsManager.swift
//  Textractor
//
//  NSHaptic feedback for tactile response during extraction.
//

import Cocoa

enum HapticsManager {

    static func light() {
        send(.alignment)
    }

    static func success() {
        send(.levelChange)
    }

    static func error() {
        send(.generic)
    }

    static func ready() {
        send(.generic)
    }

    private static func send(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }
}
