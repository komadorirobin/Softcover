import Foundation

enum SoftcoverDateFormatting {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .none
        switch AppGroup.defaults.string(forKey: "DateFormatPreference") ?? "regional" {
        case "dmy": formatter.dateFormat = "dd/MM/yyyy"
        case "mdy": formatter.dateFormat = "MM/dd/yyyy"
        case "ymd": formatter.dateFormat = "yyyy-MM-dd"
        default: formatter.dateStyle = .medium
        }
        return formatter.string(from: date)
    }
}
