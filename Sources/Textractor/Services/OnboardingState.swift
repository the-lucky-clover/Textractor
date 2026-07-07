//
//  OnboardingState.swift
//  Textractor
//
//  Tracks whether the user has dismissed the first-run onboarding tour.
//  Persisted as a single UserDefaults flag — re-opening the tour always
//  starts from page 1, but the user's skip/complete choice is remembered.
//

import Foundation
import Combine

@MainActor
public final class OnboardingState: ObservableObject {

    public static let flagKey = "com.textractor.onboarding.dismissed.v1"

    @Published public private(set) var isDismissed: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isDismissed = defaults.bool(forKey: Self.flagKey)
    }

    public func dismiss(completed: Bool) {
        isDismissed = true
        defaults.set(true, forKey: Self.flagKey)
    }

    public func resetForReRun() {
        isDismissed = false
        defaults.set(false, forKey: Self.flagKey)
    }
}
