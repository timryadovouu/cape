import Foundation

/// Pulls a reminder time out of a task's text and returns the cleaned title:
/// "позвонить маме в 15:00" → ("позвонить маме", today 15:00).
///
/// Russian phrases are parsed by hand ("в 15:00", "в 3 часа дня", "завтра в 9",
/// "через 20 минут", "через полчаса", number words like "в три"); anything else
/// falls back to the system `NSDataDetector` ("at 3pm", "tomorrow 9am",
/// "in 20 minutes"). Foundation-only so it can be tested on its own.
enum DueParser {
    struct Result: Equatable {
        let title: String
        let due: Date
    }

    static func parse(_ text: String, now: Date = Date(),
                      calendar: Calendar = .current) -> Result? {
        parseRelative(text, now: now)
            ?? parseAbsolute(text, now: now, cal: calendar)
            ?? parseDayOnly(text, now: now, cal: calendar)
            ?? parseDetector(text, now: now, cal: calendar)
    }

    // MARK: - Russian

    private static let numberWords: [String: Int] = [
        "один": 1, "одну": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
        "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10,
        "одиннадцать": 11, "двенадцать": 12, "пятнадцать": 15, "двадцать": 20,
        "тридцать": 30, "сорок": 40, "сорок пять": 45, "пятьдесят": 50,
    ]
    /// `\d{1,3}` or a number word (longest first so "сорок пять" beats "сорок").
    private static let num: String = {
        let words = numberWords.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return "(\\d{1,3}|" + words.joined(separator: "|") + ")"
    }()

    private static let enNumberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty-five": 45,
    ]
    private static let enNum: String = {
        let words = enNumberWords.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return "(\\d{1,3}|" + words.joined(separator: "|") + ")"
    }()

    private static func number(_ s: String) -> Int? {
        let k = s.lowercased()
        return Int(k) ?? numberWords[k] ?? enNumberWords[k]
    }

    /// "через 20 минут" / "через пять мин" / "через час" / "через 2 часа" / "через полчаса",
    /// and English "in 20 minutes" / "in an hour" / "in half an hour".
    private static func parseRelative(_ text: String, now: Date) -> Result? {
        let ru = "(?<![\\p{L}])через\\s+(?:(пол\\s?часа)|(?:\(num)\\s+)?(минут[уы]?|мин\\.?|час(?:а|ов)?|ч\\.?)(?![\\p{L}]))"
        let en = "(?<![\\p{L}])in\\s+(?:(half\\s+an\\s+hour)|(?:\(enNum)\\s+)?(minutes?|mins?|hours?|hrs?)(?![\\p{L}]))"
        guard let m = match(ru, in: text) ?? match(en, in: text) else { return nil }
        let minutes: Int
        if m.group(1) != nil {
            minutes = 30
        } else {
            let n = m.group(2).flatMap(number) ?? 1
            let unit = m.group(3)?.lowercased() ?? ""
            minutes = unit.hasPrefix("ч") || unit.hasPrefix("h") ? n * 60 : n
        }
        guard minutes > 0 else { return nil }
        return Result(title: cleanup(text, removing: m.range),
                      due: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// "[сегодня|завтра|послезавтра] в|к 15:00 / 9.30 / 3 часа дня / три".
    private static func parseAbsolute(_ text: String, now: Date, cal: Calendar) -> Result? {
        let pattern = "(?:(сегодня|завтра|послезавтра)\\s+)?(?<![\\p{L}])(?:в|к)\\s+\(num)"
            + "(?:[:.](\\d{2}))?(?:\\s*час(?:а|ов)?)?(?:\\s+(утра|дня|вечера|ночи))?(?![\\p{L}\\d])"
        guard let m = match(pattern, in: text),
              let h = m.group(2).flatMap(number) else { return nil }
        let minute = m.group(3).flatMap { Int($0) } ?? 0
        guard let due = resolve(day: m.group(1)?.lowercased(), hour: h, minute: minute,
                                qualifier: m.group(4)?.lowercased(), now: now, cal: cal)
        else { return nil }
        return Result(title: cleanup(text, removing: m.range), due: due)
    }

    /// Bare "завтра" / "послезавтра" → 9:00 that day.
    private static func parseDayOnly(_ text: String, now: Date, cal: Calendar) -> Result? {
        guard let m = match("(?<![\\p{L}])(завтра|послезавтра)(?![\\p{L}])", in: text),
              let day = m.group(1)?.lowercased() else { return nil }
        let offset = day == "завтра" ? 1 : 2
        guard let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
              let due = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) else { return nil }
        return Result(title: cleanup(text, removing: m.range), due: due)
    }

    private static func resolve(day: String?, hour h: Int, minute: Int, qualifier q: String?,
                                now: Date, cal: Calendar) -> Date? {
        var hour = h
        switch q {
        case "утра", "ночи": if hour == 12 { hour = 0 }
        case "дня", "вечера": if hour < 12 { hour += 12 }
        default: break
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hr: Int) -> Date? {
            guard let d = cal.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            return cal.date(bySettingHour: hr, minute: minute, second: 0, of: d)
        }

        // 24-hour clock: "в 3" is 03:00 and "в 15" is 15:00 — only an explicit
        // "дня / вечера" (or English "pm") moves an hour into the afternoon.
        switch day {
        case "завтра": return at(1, hour)
        case "послезавтра": return at(2, hour)
        case "сегодня":
            // A time already past today isn't a reminder — leave the task undated.
            return at(0, hour).flatMap { $0 > now ? $0 : nil }
        default:
            // No day: the next occurrence — today if still ahead, else tomorrow.
            return [at(0, hour), at(1, hour)].compactMap { $0 }.first { $0 > now }
        }
    }

    // MARK: - Other languages (system detector)

    private static func parseDetector(_ text: String, now: Date, cal: Calendar) -> Result? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }
        let ns = text as NSString
        guard let m = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              var date = m.date else { return nil }
        // Only accept real times / day words — not a stray weekday or year.
        let found = ns.substring(with: m.range).lowercased()
        let keywords = ["tomorrow", "tonight", "today", "noon", "midnight", "minute", "hour", "am", "pm"]
        guard found.rangeOfCharacter(from: .decimalDigits) != nil
                || keywords.contains(where: found.contains) else { return nil }
        if date <= now {
            // A time earlier today ("at 9am" typed at 10) means tomorrow.
            guard now.timeIntervalSince(date) < 86_400,
                  let next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return Result(title: cleanup(text, removing: m.range), due: date)
    }

    // MARK: - Helpers

    private struct Match {
        let result: NSTextCheckingResult
        let source: NSString
        var range: NSRange { result.range }
        func group(_ i: Int) -> String? {
            let r = result.range(at: i)
            return r.location == NSNotFound ? nil : source.substring(with: r)
        }
    }

    private static func match(_ pattern: String, in text: String) -> Match? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let r = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Match(result: r, source: ns)
    }

    /// Drop the time phrase, tidy spaces / dangling punctuation and prepositions.
    /// Falls back to the original text if nothing meaningful is left.
    private static func cleanup(_ text: String, removing range: NSRange) -> String {
        var s = (text as NSString).replacingCharacters(in: range, with: " ")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let edge = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.;:-—–"))
        s = s.trimmingCharacters(in: edge)
        s = s.replacingOccurrences(of: "\\s+(в|к|at|on|in|by)$", with: "",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.trimmingCharacters(in: edge)
        return s.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : s
    }
}
