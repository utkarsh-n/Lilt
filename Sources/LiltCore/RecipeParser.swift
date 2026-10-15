import Foundation

/// An offline description interpreter. It maps explicit requests to a bounded recipe,
/// rather than claiming to understand arbitrary prose with a language model.
public enum RecipeParser {
    public static func parse(_ description: String) -> MazeRecipe {
        let text = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let tokens = tokenize(text)
        let preferences = explicitPreferences(tokens: tokens)
        let difficulty = preferences.difficulty ?? .medium
        let theme = preferences.theme ?? .oak
        let style = preferences.style ?? .switchbacks

        let defaultHoles = difficulty == .easy ? 2 : difficulty == .medium ? 5 : 9
        let holeCount = featureCount(tokens: tokens, aliases: holeAliases,
                                     requestedDefault: defaultHoles, maximum: 24) ?? defaultHoles
        let bumperCount = featureCount(tokens: tokens, aliases: bumperAliases,
                                       requestedDefault: 3, maximum: 18) ?? (style == .pinball ? 3 : 0)
        let magnetCount = featureCount(tokens: tokens, aliases: magnetAliases,
                                       requestedDefault: 2, maximum: 8) ?? 0
        let fanCount = featureCount(tokens: tokens, aliases: fanAliases,
                                    requestedDefault: 2, maximum: 8) ?? 0
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return MazeRecipe(description: cleanDescription.isEmpty ? "A gentle wooden labyrinth" : cleanDescription,
                          difficulty: difficulty, theme: theme, style: style,
                          holeCount: holeCount, bumperCount: bumperCount,
                          magnetCount: magnetCount, fanCount: fanCount)
    }

    /// Stable across launches, platforms, and Swift versions (unlike Swift's Hasher).
    public static func seed(for description: String) -> UInt64 {
        description.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// Apply explicit numbers and exclusions after a language model supplies a recipe.
    /// An unquantified "with bumpers" keeps the model's interpretation; "four bumpers"
    /// or "no holes" is an exact constraint regardless of the model's proposed counts.
    public static func enforcingExplicitCounts(in description: String, on recipe: MazeRecipe) -> MazeRecipe {
        let text = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let tokens = tokenize(text)
        var result = recipe
        if let count = featureCount(tokens: tokens, aliases: holeAliases, requestedDefault: nil, maximum: 24) { result.holeCount = count }
        if let count = featureCount(tokens: tokens, aliases: bumperAliases, requestedDefault: nil, maximum: 18) { result.bumperCount = count }
        if let count = featureCount(tokens: tokens, aliases: magnetAliases, requestedDefault: nil, maximum: 8) { result.magnetCount = count }
        if let count = featureCount(tokens: tokens, aliases: fanAliases, requestedDefault: nil, maximum: 8) { result.fanCount = count }
        return result
    }

    /// Keep the model's inferred choices unless the description positively names a
    /// documented preference. "Tricky" is balanced, rather than the model's idea of expert.
    /// Color themes take priority over wood materials; "wood at night" means midnight.
    public static func enforcingExplicitPreferences(in description: String, on recipe: MazeRecipe) -> MazeRecipe {
        let text = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let preferences = explicitPreferences(tokens: tokenize(text))
        var result = recipe
        if let difficulty = preferences.difficulty { result.difficulty = difficulty }
        if let theme = preferences.theme { result.theme = theme }
        if let style = preferences.style { result.style = style }
        return result
    }

    private static let easyWords: Set<String> = ["easy", "gentle", "simple", "beginner", "relaxed", "calm", "wide", "forgiving"]
    private static let mediumWords: Set<String> = ["tricky", "medium", "moderate", "balanced", "intermediate"]
    private static let hardWords: Set<String> = ["hard", "expert", "difficult", "challenging", "tight", "narrow", "advanced", "brutal"]
    private static let oakWords: Set<String> = ["oak", "wood", "wooden", "maple", "timber", "classic", "brass"]
    private static let jadeWords: Set<String> = ["jade", "green", "garden", "zen", "moss", "bamboo", "emerald"]
    private static let midnightWords: Set<String> = ["midnight", "dark", "neon", "space", "cosmic", "black", "night"]

    private static func explicitPreferences(tokens: [String]) -> (difficulty: MazeDifficulty?, theme: MazeTheme?, style: MazeStyle?) {
        // Excluded words are not positive choices. This deliberately does not infer a
        // replacement style from "no spiral"; a model's broader interpretation survives.
        var positive: [String] = []
        for index in tokens.indices {
            var negated = false
            if index > 0 {
                for previous in stride(from: index - 1, through: max(0, index - 3), by: -1) {
                    let token = tokens[previous]
                    if clauseBreaks.contains(token) { break }
                    if negations.contains(token) || token == "not" { negated = true; break }
                }
            }
            if !negated { positive.append(tokens[index]) }
        }
        var difficulty: MazeDifficulty?
        for word in positive {
            if easyWords.contains(word) { difficulty = .easy }
            if mediumWords.contains(word) { difficulty = .medium }
            if hardWords.contains(word) { difficulty = .hard }
        }
        let words = Set(positive)
        var theme: MazeTheme?
        if !words.isDisjoint(with: oakWords) { theme = .oak }
        if !words.isDisjoint(with: jadeWords) { theme = .jade }
        if !words.isDisjoint(with: midnightWords) { theme = .midnight }
        var style: MazeStyle?
        if !words.isDisjoint(with: ["garden", "open", "grove", "courtyard", "zen"]) { style = .garden }
        if !words.isDisjoint(with: ["pinball", "arcade"]) { style = .pinball }
        if !words.isDisjoint(with: ["spiral", "coil", "concentric", "coiled"]) { style = .spiral }
        if !words.isDisjoint(with: ["switchbacks", "switchback", "zigzag", "serpentine"]) { style = .switchbacks }
        return (difficulty, theme, style)
    }

    private static let holeAliases: Set<String> = ["hole", "holes", "pit", "pits", "trap", "traps"]
    private static let bumperAliases: Set<String> = ["bumper", "bumpers"]
    private static let magnetAliases: Set<String> = ["magnet", "magnets", "magnetic"]
    private static let fanAliases: Set<String> = ["fan", "fans", "wind", "windy", "breeze", "breezes"]
    private static let featureNouns: Set<String> = holeAliases.union(bumperAliases)
        .union(["magnet", "magnets", "fan", "fans", "wind", "breeze", "breezes"])
    private static let negations: Set<String> = ["no", "without", "avoid", "exclude", "remove", "zero"]
    private static let clauseBreaks: Set<String> = [",", ".", ";", ":", "\n", "but", "with", "then", "plus", "add", "include", "including"]
    private static let listLinks: Set<String> = ["and", "or", ",", "any", "small", "big", "large", "tiny", "deadly", "spring", "strong", "gentle", "powerful"]

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = [], current = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { current.unicodeScalars.append(scalar) }
            else {
                if !current.isEmpty { tokens.append(current); current = "" }
                if [",", ".", ";", ":", "\n"].contains(String(scalar)) { tokens.append(String(scalar)) }
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func featureCount(tokens: [String], aliases: Set<String>,
                                     requestedDefault: Int?, maximum: Int) -> Int? {
        let numbers: [String: Int] = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
                                      "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
                                      "ten": 10, "eleven": 11, "twelve": 12, "few": 2,
                                      "several": 4, "many": 8, "lots": 10]
        func context(at index: Int) -> (preceding: [String], previousFeature: Int?) {
            var preceding: [String] = [], previousFeature: Int?
            if index > 0 {
                for previous in stride(from: index - 1, through: 0, by: -1) {
                    let token = tokens[previous]
                    if featureNouns.contains(token) { previousFeature = previous; break }
                    if clauseBreaks.contains(token) {
                        if token == ",", previous > 0 {
                            previousFeature = stride(from: previous - 1, through: 0, by: -1).first { featureNouns.contains(tokens[$0]) }
                        }
                        break
                    }
                    if preceding.count < 6 { preceding.append(token) }
                }
            }
            return (preceding, previousFeature)
        }
        func isNegated(at index: Int) -> Bool {
            let context = context(at: index)
            if context.preceding.contains(where: negations.contains) { return true }
            // An explicit new quantity begins a new request, even after a negated list.
            if context.preceding.contains(where: { Int($0) != nil || numbers[$0] != nil }) { return false }
            guard let previous = context.previousFeature else { return false }
            let between = tokens[(previous + 1)..<index]
            guard !between.isEmpty, between.allSatisfy(listLinks.contains) else { return false }
            return isNegated(at: previous)
        }
        var result: Int?
        for index in tokens.indices where aliases.contains(tokens[index]) {
            // "one magnetic magnet" names one feature; the adjective is not a second noun.
            if tokens[index] == "magnetic", index + 1 < tokens.count,
               ["magnet", "magnets"].contains(tokens[index + 1]) { continue }
            let preceding = context(at: index).preceding
            let followsFree = index + 1 < tokens.count && ["free", "less", "disabled"].contains(tokens[index + 1])
            if followsFree || isNegated(at: index) {
                result = 0
            } else if let amount = preceding.compactMap({ Int($0) ?? numbers[$0] }).first {
                result = min(maximum, max(0, amount))
            } else if let requestedDefault {
                result = requestedDefault
            }
        }
        return result
    }
}
