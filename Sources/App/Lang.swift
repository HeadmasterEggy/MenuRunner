import AppKit

enum Lang {
    static var mode: String {
        get { UserDefaults.standard.string(forKey: "lang") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "lang") }
    }
    static var isZh: Bool {
        switch mode {
        case "zh": return true
        case "en": return false
        default:   return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }
}
extension Lang {
    static var locale: Locale { Locale(identifier: isZh ? "zh_CN" : "en_US") }
}

func L(_ zh: String, _ en: String) -> String { Lang.isZh ? zh : en }
