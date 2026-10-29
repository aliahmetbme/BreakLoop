import Foundation

// Compile actual catalogs and exercise Foundation lookup, independent of the development language.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("Localization: \(message)") }
}
func localizedBundle(_ bundle: String, _ language: String) -> Bundle {
    let url = directory.appendingPathComponent("\(bundle).bundle/\(language).lproj")
    return Bundle(url: url)!
}
let tr = localizedBundle("App", "tr")
let en = localizedBundle("App", "en")
let shieldTR = localizedBundle("Shield", "tr")
let shieldEN = localizedBundle("Shield", "en")
check(String(localized: "Start BreakLoop", bundle: tr) == "BreakLoop’u Başlat", "custom button call-site lookup")
check(String(localized: "Start BreakLoop", bundle: en) == "Start BreakLoop", "English preserved")
check(String(localized: "setup.formula", defaultValue: "\(20) min use → \(15) min break", bundle: tr) == "20 dk kullanım → 15 dk mola", "two integer parameters")
check(String(localized: "focus.launch", defaultValue: "Launch Deep Focus (\("2 sa"))", bundle: tr) == "Derin Odaklanmayı Başlat (2 sa)", "duration in full sentence")
check(String(localized: "shield.focusUntil", defaultValue: "Selected apps are paused until \("19:50").", bundle: shieldTR) == "Seçilen uygulamalar 19:50 saatine kadar engellendi.", "extension deadline in Turkish")
check(String(localized: "shield.focusUntil", defaultValue: "Selected apps are paused until \("7:50 PM").", bundle: shieldEN) == "Selected apps are paused until 7:50 PM.", "extension preserves regional time")
for (key, expected) in [("A little space.", "Biraz nefes al."), ("Protect your focus.", "Odağını koru."), ("A moment away.", "Kısa bir ara."), ("Close App", "Uygulamayı Kapat")] {
    check(String(localized: String.LocalizationValue(key), bundle: shieldTR) == expected, "shield state: \(key)")
}
for count in [0, 1, 4, 50] {
    let english = String(localized: "dashboard.selection", defaultValue: "\(count) apps · \(1) categories · \(0) websites", bundle: en)
    check(english == "\(count) \(count == 1 ? "app" : "apps") · 1 category · 0 websites", "independent English plurals: \(english)")
    let turkish = String(localized: "dashboard.selection", defaultValue: "\(count) apps · \(1) categories · \(0) websites", bundle: tr)
    check(turkish == "\(count) uygulama · 1 kategori · 0 web sitesi", "Turkish counted nouns: \(turkish)")
}
check(String(localized: "error.websites", defaultValue: "This selection includes \(1) websites. BreakLoop v1.0 supports apps and categories only. Remove websites in the picker before saving or starting.", table: "SharedErrors", bundle: en).contains("1 website."), "shared validation singular")
check(String(localized: "The monitoring duration is not supported.", table: "SharedErrors", bundle: shieldTR) == "Bu izleme süresi desteklenmiyor.", "shared errors in extension bundle")
check(String(localized: "error.interrupted", defaultValue: "BreakLoop monitoring was interrupted. \("Sistem, istenen izleme aralığını planlayamadı.") Fix the problem and start BreakLoop again.", table: "SharedErrors", bundle: tr) == "BreakLoop izlemesi kesintiye uğradı. Sistem, istenen izleme aralığını planlayamadı. Sorunu giderip BreakLoop’u yeniden başlat.", "interrupted monitoring message in Turkish")

// Every catalog entry must have approved English and Turkish text, including plural leaves.
func units(_ value: Any) -> [String] {
    if let dictionary = value as? [String: Any] {
        if let unit = dictionary["stringUnit"] as? [String: String] {
            check(unit["state"] == "translated", "unreviewed unit")
            return [unit["value"] ?? ""]
        }
        return dictionary.values.flatMap(units)
    }
    return []
}
let catalogs = ["BreakLoop/Localizable.xcstrings", "BreakLoop/SharedErrors.xcstrings", "ShieldConfigurationExtension/Localizable.xcstrings"]
var total = 0
for path in catalogs {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let catalog = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    check(catalog["sourceLanguage"] as? String == "en", "source language")
    let strings = catalog["strings"] as! [String: [String: Any]]
    total += strings.count
    for (key, entry) in strings {
        let localizations = entry["localizations"] as! [String: Any]
        for language in ["en", "tr"] {
            let values = units(localizations[language] ?? [:])
            check(!values.isEmpty && values.allSatisfy { !$0.isEmpty }, "missing \(language): \(key)")
            let bundle = path.hasPrefix("Shield") ? localizedBundle("Shield", language) : localizedBundle("App", language)
            let table = path.contains("SharedErrors") ? "SharedErrors" : "Localizable"
            let resolved = bundle.localizedString(forKey: key, value: "__MISSING__", table: table)
            check(resolved != "__MISSING__", "compiled resource absent: \(key)")
        }
    }
}
// Catalogs used by shared errors must remain members of all extension targets.
let project = try String(contentsOfFile: "BreakLoop.xcodeproj/project.pbxproj", encoding: .utf8)
check(project.components(separatedBy: "SharedErrors.xcstrings,").count - 1 == 3, "all three extension resource memberships")
check(project.contains("\n\t\t\t\ttr,"), "Turkish project region")
print("Localization: \(checks) checks passed; \(total) catalog entries (including bundle-specific duplicates), no missing English/Turkish translations")
