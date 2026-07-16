//
//  ExperimentSettings.swift
//  shizen
//
//  User-facing toggles for debug experiments.
//

import Foundation

enum ExperimentSettings {
    private static let soundsEnabledKey = "ExperimentSoundsEnabled"

    /// Success chimes, selection clicks, and incorrect feedback in experiment flows.
    static var soundsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: soundsEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: soundsEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: soundsEnabledKey) }
    }
}
