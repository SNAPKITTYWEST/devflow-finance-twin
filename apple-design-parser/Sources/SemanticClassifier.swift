import Foundation

/// Semantic role classification system for design tokens
enum SemanticRole: String, Codable, CaseIterable {
    case background
    case backgroundAlt
    case backgroundInverse
    case text
    case textSecondary
    case textInverse
    case textInverseSecondary
    case textDisabled
    case link
    case linkVisited
    case interactive
    case interactiveHover
    case interactiveActive
    case interactiveDisabled
    case border
    case borderStrong
    case borderSubtle
    case state
    case stateSuccess
    case stateWarning
    case stateError
    case stateInfo
    case accent
    case accentSubtle
    case focus
    case overlay
    case shadow

    var description: String {
        switch self {
        case .background: return "Primary background surface"
        case .backgroundAlt: return "Alternative background surface"
        case .backgroundInverse: return "Inverse background surface"
        case .text: return "Primary text color"
        case .textSecondary: return "Secondary text color"
        case .textInverse: return "Inverse text color"
        case .textInverseSecondary: return "Secondary inverse text color"
        case .textDisabled: return "Disabled text color"
        case .link: return "Link color"
        case .linkVisited: return "Visited link color"
        case .interactive: return "Interactive element color"
        case .interactiveHover: return "Interactive element hover state"
        case .interactiveActive: return "Interactive element active state"
        case .interactiveDisabled: return "Interactive element disabled state"
        case .border: return "Border color"
        case .borderStrong: return "Strong border color"
        case .borderSubtle: return "Subtle border color"
        case .state: return "Generic state color"
        case .stateSuccess: return "Success state color"
        case .stateWarning: return "Warning state color"
        case .stateError: return "Error state color"
        case .stateInfo: return "Information state color"
        case .accent: return "Accent color"
        case .accentSubtle: return "Subtle accent color"
        case .focus: return "Focus indicator color"
        case .overlay: return "Overlay background color"
        case .shadow: return "Shadow color"
        }
    }
}

/// Confidence level for classification
enum ConfidenceLevel: Double, Codable {
    case veryLow = 0.2
    case low = 0.4
    case medium = 0.6
    case high = 0.8
    case veryHigh = 1.0
}

/// Represents a classification decision with trace information
struct ClassificationResult: Codable {
    let token: String
    let role: SemanticRole
    let confidence: Double
    let rulesApplied: [String]
    let explanation: String
    let hints: [String]
    let sources: [ClassificationSource]

    enum ClassificationSource: String, Codable {
        case variableName
        case propertyName
        case selector
        case colorValue
        case context
    }
}

/// Semantic hint extracted from various sources
struct SemanticHint: Codable {
    let value: String
    let source: String
    let weight: Double
    let matchedPatterns: [String]
}

/// Classifier configuration
struct ClassifierConfig: Codable {
    let enableVariableNameAnalysis: Bool
    let enablePropertyNameAnalysis: Bool
    let enableSelectorAnalysis: Bool
    let enablePatternMatching: Bool
    let confidenceThreshold: Double
    let maxHints: Int

    static let `default` = ClassifierConfig(
        enableVariableNameAnalysis: true,
        enablePropertyNameAnalysis: true,
        enableSelectorAnalysis: true,
        enablePatternMatching: true,
        confidenceThreshold: 0.4,
        maxHints: 10
    )
}

/// Semantic classification engine
final class SemanticClassifier {
    private let config: ClassifierConfig
    private var classificationCache: [String: ClassificationResult] = [:]
    private var extractedHints: [String: [SemanticHint]] = [:]

    private let semanticPatterns: [String: (SemanticRole, Double)] = [
        // Background patterns
        "bg|background|surface|fill": (.background, 0.9),
        "bg-alt|background-alt|surface-alt|alternate": (.backgroundAlt, 0.85),
        "bg-inverse|background-inverse|inverse-bg": (.backgroundInverse, 0.85),

        // Text patterns
        "fg|foreground|text|label": (.text, 0.9),
        "fg-secondary|text-secondary|secondary": (.textSecondary, 0.85),
        "fg-inverse|text-inverse|inverse-text": (.textInverse, 0.85),
        "fg-disabled|text-disabled|disabled": (.textDisabled, 0.8),

        // Link patterns
        "link|href|anchor": (.link, 0.85),
        "link-visited|visited": (.linkVisited, 0.8),

        // Interactive patterns
        "interactive|control|widget|button|input": (.interactive, 0.85),
        "hover|on-hover": (.interactiveHover, 0.8),
        "active|pressed|on-active": (.interactiveActive, 0.8),
        "disabled|disabledstate": (.interactiveDisabled, 0.8),

        // Border patterns
        "border|stroke|outline": (.border, 0.9),
        "border-strong|stroke-strong": (.borderStrong, 0.85),
        "border-subtle|stroke-subtle": (.borderSubtle, 0.85),

        // State patterns
        "success|positive|valid": (.stateSuccess, 0.85),
        "warning|caution|alert": (.stateWarning, 0.85),
        "error|danger|invalid": (.stateError, 0.85),
        "info|information|notice": (.stateInfo, 0.85),
        "state|status": (.state, 0.75),

        // Accent patterns
        "accent|primary|emphasis": (.accent, 0.85),
        "accent-subtle|accent-muted": (.accentSubtle, 0.8),

        // Focus patterns
        "focus|focused|focus-ring": (.focus, 0.9),

        // Overlay patterns
        "overlay|modal|backdrop|scrim": (.overlay, 0.85),

        // Shadow patterns
        "shadow|drop-shadow|box-shadow": (.shadow, 0.9)
    ]

    init(config: ClassifierConfig = .default) {
        self.config = config
    }

    /// Classify a token and return the result
    func classify(token: String, hints: [SemanticHint] = [], context: [String: String]? = nil) -> ClassificationResult {
        if let cached = classificationCache[token] {
            return cached
        }

        var allHints: [SemanticHint] = hints
        var rulesApplied: [String] = []
        var sources: Set<ClassificationResult.ClassificationSource> = []

        // Extract hints from variable name
        if config.enableVariableNameAnalysis {
            let variableHints = extractHintsFromVariableName(token)
            allHints.append(contentsOf: variableHints)
            if !variableHints.isEmpty {
                sources.insert(.variableName)
            }
        }

        // Extract hints from context (property names, selectors)
        if let context = context {
            if config.enablePropertyNameAnalysis, let propertyName = context["property"] {
                let propertyHints = extractHintsFromPropertyName(propertyName)
                allHints.append(contentsOf: propertyHints)
                if !propertyHints.isEmpty {
                    sources.insert(.propertyName)
                }
            }

            if config.enableSelectorAnalysis, let selector = context["selector"] {
                let selectorHints = extractHintsFromSelector(selector)
                allHints.append(contentsOf: selectorHints)
                if !selectorHints.isEmpty {
                    sources.insert(.selector)
                }
            }

            if let colorValue = context["color"] {
                sources.insert(.colorValue)
            }
        }

        // Sort hints by weight
        allHints.sort { $0.weight > $1.weight }

        // Limit hints
        let limitedHints = Array(allHints.prefix(config.maxHints))

        // Find best matching role
        var bestRole: SemanticRole = .state
        var bestConfidence: Double = 0.0

        for hint in limitedHints {
            for (pattern, (role, patternConfidence)) in semanticPatterns {
                if matchesPattern(hint.value, pattern: pattern) {
                    let combinedConfidence = (hint.weight * patternConfidence)
                    if combinedConfidence > bestConfidence {
                        bestConfidence = combinedConfidence
                        bestRole = role
                        rulesApplied.append("Matched pattern '\(pattern)' from hint '\(hint.value)'")
                    }
                }
            }
        }

        // If no match found, apply default based on context
        if bestConfidence < config.confidenceThreshold {
            bestRole = .state
            rulesApplied.append("No pattern match; applied default role")
        }

        // Clamp confidence
        bestConfidence = min(1.0, max(0.0, bestConfidence))

        // Build explanation
        let explanation = buildExplanation(
            role: bestRole,
            hints: limitedHints,
            confidence: bestConfidence,
            rulesApplied: rulesApplied
        )

        let result = ClassificationResult(
            token: token,
            role: bestRole,
            confidence: bestConfidence,
            rulesApplied: rulesApplied,
            explanation: explanation,
            hints: limitedHints.map { $0.value },
            sources: Array(sources).sorted { $0.rawValue < $1.rawValue }
        )

        classificationCache[token] = result
        return result
    }

    /// Extract semantic hints from variable name
    private func extractHintsFromVariableName(_ name: String) -> [SemanticHint] {
        var hints: [SemanticHint] = []

        // Convert camelCase/kebab-case to components
        let components = parseNameComponents(name)

        for (index, component) in components.enumerated() {
            let weight = Double(components.count - index) / Double(components.count)

            let hint = SemanticHint(
                value: component,
                source: "variableName",
                weight: weight * 0.9,
                matchedPatterns: findMatchingPatterns(component)
            )
            hints.append(hint)
        }

        return hints
    }

    /// Extract semantic hints from property name
    private func extractHintsFromPropertyName(_ name: String) -> [SemanticHint] {
        let components = parseNameComponents(name)
        var hints: [SemanticHint] = []

        for (index, component) in components.enumerated() {
            let weight = Double(components.count - index) / Double(components.count)

            let hint = SemanticHint(
                value: component,
                source: "propertyName",
                weight: weight * 0.85,
                matchedPatterns: findMatchingPatterns(component)
            )
            hints.append(hint)
        }

        return hints
    }

    /// Extract semantic hints from CSS selector
    private func extractHintsFromSelector(_ selector: String) -> [SemanticHint] {
        var hints: [SemanticHint] = []

        // Parse class names
        let classPattern = try! NSRegularExpression(pattern: "\\.([a-zA-Z0-9_-]+)", options: [])
        let range = NSRange(selector.startIndex..., in: selector)
        let matches = classPattern.matches(in: selector, options: [], range: range)

        for (index, match) in matches.enumerated() {
            if let range = Range(match.range(at: 1), in: selector) {
                let className = String(selector[range])
                let weight = Double(matches.count - index) / Double(matches.count)

                let hint = SemanticHint(
                    value: className,
                    source: "selector",
                    weight: weight * 0.8,
                    matchedPatterns: findMatchingPatterns(className)
                )
                hints.append(hint)
            }
        }

        // Parse pseudo-classes
        let pseudoPattern = try! NSRegularExpression(pattern: ":([a-z-]+)", options: [])
        let pseudoMatches = pseudoPattern.matches(in: selector, options: [], range: range)

        for match in pseudoMatches {
            if let range = Range(match.range(at: 1), in: selector) {
                let pseudoClass = String(selector[range])

                let hint = SemanticHint(
                    value: pseudoClass,
                    source: "selector",
                    weight: 0.6,
                    matchedPatterns: findMatchingPatterns(pseudoClass)
                )
                hints.append(hint)
            }
        }

        return hints
    }

    /// Parse name into components (handles camelCase, kebab-case, snake_case)
    private func parseNameComponents(_ name: String) -> [String] {
        var components: [String] = []
        var current = ""

        for (index, char) in name.enumerated() {
            if char == "-" || char == "_" {
                if !current.isEmpty {
                    components.append(current.lowercased())
                    current = ""
                }
            } else if char.isUppercase && index > 0 {
                if !current.isEmpty {
                    components.append(current.lowercased())
                }
                current = String(char).lowercased()
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            components.append(current.lowercased())
        }

        return components
    }

    /// Find matching semantic patterns for a term
    private func findMatchingPatterns(_ term: String) -> [String] {
        let lowerTerm = term.lowercased()
        var matched: [String] = []

        for pattern in semanticPatterns.keys {
            if matchesPattern(lowerTerm, pattern: pattern) {
                matched.append(pattern)
            }
        }

        return matched
    }

    /// Check if a term matches a pattern
    private func matchesPattern(_ term: String, pattern: String) -> Bool {
        let patterns = pattern.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        let lowerTerm = term.lowercased()

        for p in patterns {
            let cleanPattern = p.trimmingCharacters(in: .whitespaces)
            if lowerTerm == cleanPattern || lowerTerm.contains(cleanPattern) || cleanPattern.contains(lowerTerm) {
                return true
            }
        }

        return false
    }

    /// Build explanation string for classification
    private func buildExplanation(role: SemanticRole, hints: [SemanticHint], confidence: Double, rulesApplied: [String]) -> String {
        var explanation = "Classified as \(role.rawValue) (\(role.description)) with \(String(format: "%.1f", confidence * 100))% confidence. "

        if !hints.isEmpty {
            explanation += "Matched hints: \(hints.prefix(3).map { $0.value }.joined(separator: ", ")). "
        }

        if !rulesApplied.isEmpty {
            explanation += "Rules: \(rulesApplied.prefix(2).joined(separator: "; "))."
        }

        return explanation
    }

    /// Get classification for multiple tokens
    func classifyBatch(_ tokens: [String], context: [String: [String: String]]? = nil) -> [ClassificationResult] {
        return tokens.map { token in
            let tokenContext = context?[token] ?? [:]
            return classify(token: token, context: tokenContext)
        }
    }

    /// Get cached classification
    func getCachedClassification(_ token: String) -> ClassificationResult? {
        return classificationCache[token]
    }

    /// Clear cache
    func clearCache() {
        classificationCache.removeAll()
        extractedHints.removeAll()
    }

    /// Get statistics about classifications
    func getStatistics() -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["totalClassifications"] = classificationCache.count

        var roleDistribution: [String: Int] = [:]
        var confidenceSum: Double = 0.0
        var maxConfidence: Double = 0.0
        var minConfidence: Double = 1.0

        for result in classificationCache.values {
            roleDistribution[result.role.rawValue, default: 0] += 1
            confidenceSum += result.confidence
            maxConfidence = max(maxConfidence, result.confidence)
            minConfidence = min(minConfidence, result.confidence)
        }

        stats["roleDistribution"] = roleDistribution
        stats["averageConfidence"] = classificationCache.isEmpty ? 0.0 : confidenceSum / Double(classificationCache.count)
        stats["maxConfidence"] = maxConfidence
        stats["minConfidence"] = classificationCache.isEmpty ? 0.0 : minConfidence

        return stats
    }

    /// Export classifications as JSON
    func exportClassifications() -> Data? {
        let results = Array(classificationCache.values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(results)
    }

    /// Import classifications from JSON
    func importClassifications(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        if let results = try? decoder.decode([ClassificationResult].self, from: data) {
            for result in results {
                classificationCache[result.token] = result
            }
            return true
        }
        return false
    }
}

// MARK: - Semantic Classification Utilities

extension SemanticRole {
    var isBackground: Bool {
        switch self {
        case .background, .backgroundAlt, .backgroundInverse, .overlay:
            return true
        default:
            return false
        }
    }

    var isText: Bool {
        switch self {
        case .text, .textSecondary, .textInverse, .textInverseSecondary, .textDisabled:
            return true
        default:
            return false
        }
    }

    var isInteractive: Bool {
        switch self {
        case .interactive, .interactiveHover, .interactiveActive, .interactiveDisabled, .link, .linkVisited:
            return true
        default:
            return false
        }
    }

    var isState: Bool {
        switch self {
        case .state, .stateSuccess, .stateWarning, .stateError, .stateInfo:
            return true
        default:
            return false
        }
    }

    var isBorder: Bool {
        switch self {
        case .border, .borderStrong, .borderSubtle:
            return true
        default:
            return false
        }
    }
}

// MARK: - Advanced Classification Rules

/// Advanced semantic classification engine with rule composition
final class AdvancedSemanticClassifier {
    private let baseClassifier: SemanticClassifier
    private var customRules: [ClassificationRule] = []
    private var ruleChain: ClassificationRuleChain?

    init(baseClassifier: SemanticClassifier = SemanticClassifier()) {
        self.baseClassifier = baseClassifier
    }

    /// Add a custom classification rule
    func addCustomRule(_ rule: ClassificationRule) {
        customRules.append(rule)
    }

    /// Classify using custom rules with fallback
    func classifyWithRules(token: String, hints: [SemanticHint] = [], context: [String: String]? = nil) -> ClassificationResult {
        // Try custom rules first
        for rule in customRules {
            if rule.matches(token: token, context: context) {
                let baseResult = baseClassifier.classify(token: token, hints: hints, context: context)
                return ClassificationResult(
                    token: baseResult.token,
                    role: rule.targetRole,
                    confidence: rule.confidence,
                    rulesApplied: baseResult.rulesApplied + ["CustomRule: \(rule.name)"],
                    explanation: "Applied custom rule: \(rule.name)",
                    hints: baseResult.hints,
                    sources: baseResult.sources
                )
            }
        }

        // Fall back to base classifier
        return baseClassifier.classify(token: token, hints: hints, context: context)
    }

    /// Build a classification rule chain
    func buildRuleChain() -> ClassificationRuleChain {
        let chain = ClassificationRuleChain()
        for rule in customRules {
            chain.addRule(rule)
        }
        self.ruleChain = chain
        return chain
    }

    /// Get all custom rules
    func getCustomRules() -> [ClassificationRule] {
        return customRules
    }

    /// Clear custom rules
    func clearCustomRules() {
        customRules.removeAll()
    }
}

/// Represents a single classification rule
struct ClassificationRule: Codable {
    let name: String
    let pattern: String
    let targetRole: SemanticRole
    let confidence: Double
    let priority: Int
    let description: String

    /// Check if this rule matches a token
    func matches(token: String, context: [String: String]? = nil) -> Bool {
        let lowerToken = token.lowercased()
        let lowerPattern = pattern.lowercased()

        if lowerToken == lowerPattern {
            return true
        }

        if lowerToken.contains(lowerPattern) || lowerPattern.contains(lowerToken) {
            return true
        }

        return false
    }
}

/// Classification rule chain for ordered rule evaluation
final class ClassificationRuleChain {
    private var rules: [ClassificationRule] = []

    /// Add a rule to the chain
    func addRule(_ rule: ClassificationRule) {
        rules.append(rule)
        rules.sort { $0.priority > $1.priority }
    }

    /// Evaluate the chain against a token
    func evaluate(token: String) -> ClassificationRule? {
        for rule in rules {
            if rule.matches(token: token) {
                return rule
            }
        }
        return nil
    }

    /// Get all rules
    func getAllRules() -> [ClassificationRule] {
        return rules
    }

    /// Get rules for a specific role
    func getRulesForRole(_ role: SemanticRole) -> [ClassificationRule] {
        return rules.filter { $0.targetRole == role }
    }

    /// Clear all rules
    func clearRules() {
        rules.removeAll()
    }

    /// Get statistics
    func getStatistics() -> [String: Any] {
        var stats: [String: Any] = [:]
        stats["totalRules"] = rules.count

        var roleDistribution: [String: Int] = [:]
        for rule in rules {
            roleDistribution[rule.targetRole.rawValue, default: 0] += 1
        }
        stats["roleDistribution"] = roleDistribution

        var priorityStats: [String: Int] = [:]
        for rule in rules {
            priorityStats[String(rule.priority), default: 0] += 1
        }
        stats["priorityDistribution"] = priorityStats

        return stats
    }
}

// MARK: - Semantic Hint Analysis

/// Analyzes semantic hints and provides insights
final class SemanticHintAnalyzer {
    /// Analyze multiple hints and extract patterns
    static func analyzeHints(_ hints: [SemanticHint]) -> [String: Any] {
        var analysis: [String: Any] = [:]

        analysis["totalHints"] = hints.count
        analysis["averageWeight"] = hints.isEmpty ? 0.0 : hints.map { $0.weight }.reduce(0, +) / Double(hints.count)

        var sources: [String: Int] = [:]
        for hint in hints {
            sources[hint.source, default: 0] += 1
        }
        analysis["sourceDistribution"] = sources

        var patterns: Set<String> = []
        for hint in hints {
            for pattern in hint.matchedPatterns {
                patterns.insert(pattern)
            }
        }
        analysis["uniquePatterns"] = patterns.count
        analysis["patterns"] = Array(patterns).sorted()

        let weightedHints = hints.sorted { $0.weight > $1.weight }
        analysis["topHints"] = weightedHints.prefix(5).map { $0.value }

        return analysis
    }

    /// Compare two sets of hints
    static func compareHints(_ hints1: [SemanticHint], _ hints2: [SemanticHint]) -> [String: Any] {
        var comparison: [String: Any] = [:]

        comparison["hints1Count"] = hints1.count
        comparison["hints2Count"] = hints2.count

        let values1 = Set(hints1.map { $0.value })
        let values2 = Set(hints2.map { $0.value })

        comparison["common"] = values1.intersection(values2).count
        comparison["unique1"] = values1.subtracting(values2).count
        comparison["unique2"] = values2.subtracting(values1).count

        let weight1 = hints1.map { $0.weight }.reduce(0, +)
        let weight2 = hints2.map { $0.weight }.reduce(0, +)
        comparison["weightDifference"] = abs(weight1 - weight2)

        return comparison
    }

    /// Find semantic hint outliers
    static func findOutliers(_ hints: [SemanticHint]) -> [SemanticHint] {
        let avgWeight = hints.isEmpty ? 0.0 : hints.map { $0.weight }.reduce(0, +) / Double(hints.count)
        let stdDev = calculateStandardDeviation(hints.map { $0.weight }, mean: avgWeight)

        return hints.filter { abs($0.weight - avgWeight) > stdDev }
    }

    /// Calculate standard deviation
    private static func calculateStandardDeviation(_ values: [Double], mean: Double) -> Double {
        if values.isEmpty { return 0 }
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - Semantic Classification Batch Processor

/// Processes large batches of tokens efficiently
final class SemanticClassificationBatchProcessor {
    private let classifier: SemanticClassifier
    private let batchSize: Int

    init(classifier: SemanticClassifier = SemanticClassifier(), batchSize: Int = 100) {
        self.classifier = classifier
        self.batchSize = batchSize
    }

    /// Process tokens in batches
    func processBatch(_ tokens: [String], context: [String: [String: String]]? = nil) -> [ClassificationResult] {
        var results: [ClassificationResult] = []

        for batchStart in stride(from: 0, to: tokens.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tokens.count)
            let batch = Array(tokens[batchStart..<batchEnd])

            let batchContext = context.flatMap { ctx -> [String: [String: String]]? in
                var batchCtx: [String: [String: String]] = [:]
                for token in batch {
                    if let tokenCtx = ctx[token] {
                        batchCtx[token] = tokenCtx
                    }
                }
                return batchCtx.isEmpty ? nil : batchCtx
            }

            let batchResults = classifier.classifyBatch(batch, context: batchContext)
            results.append(contentsOf: batchResults)
        }

        return results
    }

    /// Get processing statistics
    func getProcessingStats(for results: [ClassificationResult]) -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["totalProcessed"] = results.count
        stats["averageConfidence"] = results.isEmpty ? 0.0 : results.map { $0.confidence }.reduce(0, +) / Double(results.count)
        stats["batchSize"] = batchSize
        stats["batchesProcessed"] = (results.count + batchSize - 1) / batchSize

        var confidenceBuckets: [String: Int] = [:]
        for result in results {
            let bucket: String
            if result.confidence >= 0.8 {
                bucket = "0.8-1.0"
            } else if result.confidence >= 0.6 {
                bucket = "0.6-0.8"
            } else if result.confidence >= 0.4 {
                bucket = "0.4-0.6"
            } else {
                bucket = "0.0-0.4"
            }
            confidenceBuckets[bucket, default: 0] += 1
        }
        stats["confidenceBuckets"] = confidenceBuckets

        return stats
    }
}
