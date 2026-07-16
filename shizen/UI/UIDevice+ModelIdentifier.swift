//
//  UIDevice+ModelIdentifier.swift
//  shizen
//

import UIKit

extension UIDevice {
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        if machine == "arm64" {
            return "iPhone17"
        }
        return machine
    }
}
