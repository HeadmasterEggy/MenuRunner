import AppKit

enum TempUnit {
    static var fahrenheit: Bool {
        get { UserDefaults.standard.string(forKey: "tempUnit") == "F" }
        set { UserDefaults.standard.set(newValue ? "F" : "C", forKey: "tempUnit") }
    }
    static func format(_ c: Double, decimals: Int = 1, unit: Bool = true) -> String {
        let v = fahrenheit ? c * 9 / 5 + 32 : c
        return String(format: "%.\(decimals)f", v) + (unit ? (fahrenheit ? "°F" : "°C") : "°")
    }
}
