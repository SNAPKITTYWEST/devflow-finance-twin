import Foundation

/// Appearance mode enumeration
enum AppearanceMode: String, Codable, CaseIterable {
    case light
    case dark
    case auto
    case contrast

    var isDark: Bool {
        return self == .dark
    }

    var isLight: Bool {
        return self == .light
    }

    var isAuto: Bool {
        return self == .auto
    }
}

/// Color value with appearance context
struct AppearanceAwareColor: Codable {
    let lightValue: String
    let darkValue: String?
    let highContrastValue: String?
    let source: ColorValueSource

    enum ColorValueSource: String, Codable {
        case cssProperty
        case mediaQuery
        case preferencesAttribute
        case directAssignment
        case computed
    }

    func resolve(appearance: AppearanceMode) -> String {
        switch appearance {
        case .light:
            return lightValue
        case .dark:
            return darkValue ?? lightValue
        case .auto:
            return lightValue
        case .contrast:
            return highContrastValue ?? darkValue ?? lightValue
        }
    }

    func hasVariants: Bool {
        return darkValue != nil || highContrastValue != nil
    }
}

/// Media query appearance specification
struct MediaQueryAppearance: Codable {
    let query: String
    let appearance: AppearanceMode
    let colorValue: String
    let selector: String
    let property: String
}

/// Appearance rule and its resolved values
struct AppearanceRule: Codable {
    let identifier: String
    let selector: String
    let property: String
    let lightValue: String
    let darkValue: String?
    let highContrastValue: String?
    let hasMediaQuery: Bool
    let mediaQueryType: String?
    let priority: Int
    let appliedRules: [String]
}

/// Appearance resolution configuration
struct AppearanceResolverConfig: Codable {
    let defaultAppearance: AppearanceMode
    let resolveMediaQueries: Bool
    let handlePrefersColorScheme: Bool
    let handlePrefersContrast: Bool
    let computeMissingVariants: Bool
    let cache: Bool

    static let `default` = AppearanceResolverConfig(
        defaultAppearance: .light,
        resolveMediaQueries: true,
        handlePrefersColorScheme: true,
        handlePrefersContrast: true,
        computeMissingVariants: true,
        cache: true
    )
}

/// Resolves color values across different appearance modes
final class AppearanceResolver {
    private let config: AppearanceResolverConfig
    private var resolvedValues: [String: [String: String]] = [:]
    private var appearanceRules: [AppearanceRule] = []
    private var mediaQueryMappings: [String: MediaQueryAppearance] = [:]
    private var resolutionLog: [String] = []

    init(config: AppearanceResolverConfig = .default) {
        self.config = config
    }

    /// Resolve a color value across all appearance modes
    func resolveAppearances(_ identifier: String, lightValue: String, darkValue: String? = nil, highContrastValue: String? = nil) -> AppearanceAwareColor {
        let key = identifier

        if config.cache, let cached = resolvedValues[key] {
            let resolvedLight = cached["light"] ?? lightValue
            let resolvedDark = cached["dark"] ?? darkValue
            let resolvedContrast = cached["contrast"] ?? highContrastValue
            return AppearanceAwareColor(
                lightValue: resolvedLight,
                darkValue: resolvedDark,
                highContrastValue: resolvedContrast,
                source: .directAssignment
            )
        }

        var resolvedLight = lightValue
        var resolvedDark = darkValue
        var resolvedContrast = highContrastValue

        // Perform deterministic resolution
        logResolution("Resolving appearance for \(identifier)")

        // Apply light mode
        if config.resolveMediaQueries {
            resolvedLight = resolveLightMode(identifier, initial: lightValue)
        }

        // Apply dark mode
        if config.resolveMediaQueries {
            resolvedDark = resolveDarkMode(identifier, initial: darkValue ?? lightValue)
        }

        // Apply contrast mode
        if config.handlePrefersContrast {
            resolvedContrast = resolveContrast(identifier, initial: highContrastValue ?? resolvedDark ?? resolvedLight)
        }

        // Cache if enabled
        if config.cache {
            resolvedValues[key, default: [:]]["light"] = resolvedLight
            if let dark = resolvedDark {
                resolvedValues[key, default: [:]]["dark"] = dark
            }
            if let contrast = resolvedContrast {
                resolvedValues[key, default: [:]]["contrast"] = contrast
            }
        }

        return AppearanceAwareColor(
            lightValue: resolvedLight,
            darkValue: resolvedDark,
            highContrastValue: resolvedContrast,
            source: .computed
        )
    }

    /// Resolve light mode color value
    private func resolveLightMode(_ identifier: String, initial: String) -> String {
        logResolution("Resolving light mode for \(identifier)")

        var result = initial

        // Check media queries for light mode
        if let mediaQueryResult = findMediaQueryResult(identifier, appearance: .light) {
            result = mediaQueryResult
            logResolution("Found light mode media query: \(mediaQueryResult)")
        }

        return result
    }

    /// Resolve dark mode color value
    private func resolveDarkMode(_ identifier: String, initial: String) -> String {
        logResolution("Resolving dark mode for \(identifier)")

        var result = initial

        // Check media queries for dark mode
        if let mediaQueryResult = findMediaQueryResult(identifier, appearance: .dark) {
            result = mediaQueryResult
            logResolution("Found dark mode media query: \(mediaQueryResult)")
        }

        return result
    }

    /// Resolve high contrast mode color value
    private func resolveContrast(_ identifier: String, initial: String) -> String {
        logResolution("Resolving contrast mode for \(identifier)")

        var result = initial

        // Check media queries for contrast mode
        if let mediaQueryResult = findMediaQueryResult(identifier, appearance: .contrast) {
            result = mediaQueryResult
            logResolution("Found contrast mode media query: \(mediaQueryResult)")
        }

        return result
    }

    /// Find media query result for an identifier in a specific appearance mode
    private func findMediaQueryResult(_ identifier: String, appearance: AppearanceMode) -> String? {
        for (_, mapping) in mediaQueryMappings {
            if mapping.selector.contains(identifier) && mapping.appearance == appearance {
                return mapping.colorValue
            }
        }
        return nil
    }

    /// Register a media query appearance
    func registerMediaQueryAppearance(_ query: String, appearance: AppearanceMode, selector: String, property: String, colorValue: String) {
        let mapping = MediaQueryAppearance(
            query: query,
            appearance: appearance,
            colorValue: colorValue,
            selector: selector,
            property: property
        )

        let key = "\(selector)_\(property)_\(appearance.rawValue)"
        mediaQueryMappings[key] = mapping

        logResolution("Registered media query: \(query) -> \(appearance.rawValue)")
    }

    /// Parse CSS media query and extract appearance information
    func parseMediaQuery(_ query: String) -> (mode: AppearanceMode, value: String)? {
        let lowerQuery = query.lowercased()

        if lowerQuery.contains("prefers-color-scheme") {
            if lowerQuery.contains("dark") {
                return (.dark, "dark")
            } else if lowerQuery.contains("light") {
                return (.light, "light")
            }
        } else if lowerQuery.contains("prefers-contrast") {
            if lowerQuery.contains("more") {
                return (.contrast, "high")
            }
        }

        return nil
    }

    /// Extract appearance-specific rules from CSS
    func extractAppearanceRules(cssSelector: String, cssProperties: [String: String]) -> [AppearanceRule] {
        var rules: [AppearanceRule] = []
        var ruleId = 0

        for (property, value) in cssProperties {
            ruleId += 1
            let identifier = "\(cssSelector)_\(property)_\(ruleId)"

            // Check if this is a media query or regular CSS
            let hasMediaQuery = false
            let mediaQueryType: String? = nil

            let rule = AppearanceRule(
                identifier: identifier,
                selector: cssSelector,
                property: property,
                lightValue: value,
                darkValue: nil,
                highContrastValue: nil,
                hasMediaQuery: hasMediaQuery,
                mediaQueryType: mediaQueryType,
                priority: 10,
                appliedRules: ["cssProperty"]
            )

            rules.append(rule)
        }

        return rules
    }

    /// Build appearance-aware palette from rules
    func buildAppearancePalette(_ rules: [AppearanceRule]) -> [String: [String: String]] {
        var palette: [String: [String: String]] = [:]

        for rule in rules {
            let key = "\(rule.selector)_\(rule.property)"

            var modeValues: [String: String] = [:]
            modeValues["light"] = rule.lightValue

            if let darkValue = rule.darkValue {
                modeValues["dark"] = darkValue
            } else {
                modeValues["dark"] = rule.lightValue
            }

            if let contrastValue = rule.highContrastValue {
                modeValues["contrast"] = contrastValue
            } else {
                modeValues["contrast"] = rule.darkValue ?? rule.lightValue
            }

            palette[key] = modeValues
        }

        return palette
    }

    /// Determine which rule produced a specific value
    func traceValueOrigin(_ value: String, appearance: AppearanceMode) -> AppearanceRule? {
        for rule in appearanceRules {
            switch appearance {
            case .light:
                if rule.lightValue == value {
                    return rule
                }
            case .dark:
                if rule.darkValue == value || (rule.darkValue == nil && rule.lightValue == value) {
                    return rule
                }
            case .contrast:
                if rule.highContrastValue == value {
                    return rule
                }
            case .auto:
                if rule.lightValue == value {
                    return rule
                }
            }
        }
        return nil
    }

    /// Check if a color needs dark mode variant
    func needsDarkModeVariant(_ lightValue: String) -> Bool {
        // Extract RGB values from color (simplified)
        if lightValue.contains("rgb") {
            return true
        }
        if lightValue.contains("hsl") {
            return true
        }
        if lightValue.contains("hex") || lightValue.hasPrefix("#") {
            return true
        }
        return false
    }

    /// Compute a dark mode variant from light mode value
    func computeDarkModeVariant(_ lightValue: String) -> String? {
        // For now, return a placeholder indicating computation needed
        if needsDarkModeVariant(lightValue) {
            return "computed-dark(\(lightValue))"
        }
        return nil
    }

    /// Check if a color needs contrast variant
    func needsContrastVariant(_ standardValue: String) -> Bool {
        return !standardValue.isEmpty
    }

    /// Compute a contrast variant from standard value
    func computeContrastVariant(_ standardValue: String) -> String? {
        if needsContrastVariant(standardValue) {
            return "computed-contrast(\(standardValue))"
        }
        return nil
    }

    /// Register an appearance rule
    func registerAppearanceRule(_ rule: AppearanceRule) {
        appearanceRules.append(rule)
        logResolution("Registered rule: \(rule.identifier)")
    }

    /// Get all registered rules
    func getAppearanceRules() -> [AppearanceRule] {
        return appearanceRules
    }

    /// Get resolution log
    func getResolutionLog() -> [String] {
        return resolutionLog
    }

    /// Clear resolution log
    func clearResolutionLog() {
        resolutionLog.removeAll()
    }

    /// Log a resolution step
    private func logResolution(_ message: String) {
        if !config.cache {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        resolutionLog.append("[\(timestamp)] \(message)")
    }

    /// Get statistics about resolutions
    func getStatistics() -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["totalResolvedValues"] = resolvedValues.count
        stats["totalRules"] = appearanceRules.count
        stats["totalMediaQueries"] = mediaQueryMappings.count

        var appearanceStats: [String: Int] = [:]
        for mode in AppearanceMode.allCases {
            appearanceStats[mode.rawValue] = 0
        }

        for rule in appearanceRules {
            if rule.darkValue != nil {
                appearanceStats["dark", default: 0] += 1
            }
            if rule.highContrastValue != nil {
                appearanceStats["contrast", default: 0] += 1
            }
        }

        stats["appearanceVariants"] = appearanceStats
        stats["logEntries"] = resolutionLog.count

        return stats
    }

    /// Export resolver state as JSON
    func exportState() -> Data? {
        struct ExportData: Codable {
            let rules: [AppearanceRule]
            let mediaQueries: [MediaQueryAppearance]
            let resolutionLog: [String]
        }

        let export = ExportData(
            rules: appearanceRules,
            mediaQueries: Array(mediaQueryMappings.values),
            resolutionLog: resolutionLog
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(export)
    }

    /// Import resolver state from JSON
    func importState(_ data: Data) -> Bool {
        struct ImportData: Codable {
            let rules: [AppearanceRule]
            let mediaQueries: [MediaQueryAppearance]
            let resolutionLog: [String]
        }

        let decoder = JSONDecoder()
        if let imported = try? decoder.decode(ImportData.self, from: data) {
            appearanceRules = imported.rules
            mediaQueryMappings = imported.mediaQueries.reduce(into: [:]) { dict, mq in
                dict["\(mq.selector)_\(mq.property)_\(mq.appearance.rawValue)"] = mq
            }
            resolutionLog = imported.resolutionLog
            return true
        }
        return false
    }

    /// Clear all state
    func clearState() {
        resolvedValues.removeAll()
        appearanceRules.removeAll()
        mediaQueryMappings.removeAll()
        resolutionLog.removeAll()
    }

    /// Resolve a token across all appearance modes
    func resolveToken(_ token: String, lightValue: String, darkValue: String? = nil, contrastValue: String? = nil) -> [String: String] {
        let resolved = resolveAppearances(token, lightValue: lightValue, darkValue: darkValue, highContrastValue: contrastValue)

        var result: [String: String] = [:]
        result["light"] = resolved.lightValue
        if let dark = resolved.darkValue {
            result["dark"] = dark
        }
        if let contrast = resolved.highContrastValue {
            result["contrast"] = contrast
        }

        return result
    }

    /// Batch resolve multiple tokens
    func resolveTokensBatch(_ tokens: [(String, String, String?, String?)]) -> [[String: String]] {
        return tokens.map { token, lightValue, darkValue, contrastValue in
            resolveToken(token, lightValue: lightValue, darkValue: darkValue, contrastValue: contrastValue)
        }
    }
}

// MARK: - Appearance Resolution Utilities

extension AppearanceMode {
    var displayName: String {
        switch self {
        case .light:
            return "Light Mode"
        case .dark:
            return "Dark Mode"
        case .auto:
            return "Auto (System)"
        case .contrast:
            return "High Contrast"
        }
    }

    var cssMediaQuery: String {
        switch self {
        case .light:
            return "(prefers-color-scheme: light)"
        case .dark:
            return "(prefers-color-scheme: dark)"
        case .auto:
            return ""
        case .contrast:
            return "(prefers-contrast: more)"
        }
    }
}

extension AppearanceAwareColor {
    var allValues: [String] {
        var values = [lightValue]
        if let dark = darkValue, !values.contains(dark) {
            values.append(dark)
        }
        if let contrast = highContrastValue, !values.contains(contrast) {
            values.append(contrast)
        }
        return values
    }

    var uniqueValueCount: Int {
        return Set(allValues).count
    }

    func needsInversion: Bool {
        return darkValue != nil && darkValue != lightValue
    }
}

// MARK: - Advanced Appearance Resolution

/// Advanced appearance resolution with variant computation
final class AdvancedAppearanceResolver {
    private let baseResolver: AppearanceResolver
    private var variantComputations: [String: VariantComputationRule] = [:]

    init(baseResolver: AppearanceResolver = AppearanceResolver()) {
        self.baseResolver = baseResolver
    }

    /// Register a variant computation rule
    func registerVariantRule(_ rule: VariantComputationRule) {
        variantComputations[rule.name] = rule
    }

    /// Compute dark variant from light value
    func computeDarkVariant(_ lightValue: String, rule: String? = nil) -> String {
        if let rule = rule, let computation = variantComputations[rule] {
            return computation.compute(lightValue)
        }

        // Default computation
        return "color-invert(\(lightValue))"
    }

    /// Compute contrast variant
    func computeContrastVariant(_ standardValue: String, rule: String? = nil) -> String {
        if let rule = rule, let computation = variantComputations[rule] {
            return computation.compute(standardValue)
        }

        // Default computation
        return "color-enhance-contrast(\(standardValue))"
    }

    /// Batch resolve with variant computation
    func resolveBatchWithVariants(_ tokens: [(String, String)]) -> [String: [String: String]] {
        var results: [String: [String: String]] = [:]

        for (tokenId, lightValue) in tokens {
            let darkValue = computeDarkVariant(lightValue)
            let contrastValue = computeContrastVariant(lightValue)

            let resolved = baseResolver.resolveAppearances(
                tokenId,
                lightValue: lightValue,
                darkValue: darkValue,
                highContrastValue: contrastValue
            )

            var modeValues: [String: String] = [:]
            modeValues["light"] = resolved.lightValue
            modeValues["dark"] = resolved.darkValue ?? lightValue
            modeValues["contrast"] = resolved.highContrastValue ?? darkValue

            results[tokenId] = modeValues
        }

        return results
    }

    /// Get variant computation statistics
    func getVariantStatistics() -> [String: Any] {
        var stats: [String: Any] = [:]
        stats["registeredRules"] = variantComputations.count
        stats["ruleNames"] = Array(variantComputations.keys)
        return stats
    }
}

/// Represents a variant computation rule
struct VariantComputationRule: Codable {
    let name: String
    let description: String
    let computationType: ComputationType

    enum ComputationType: String, Codable {
        case invert
        case lighten
        case darken
        case saturate
        case desaturate
        case custom
    }

    /// Compute a variant value
    func compute(_ baseValue: String) -> String {
        switch computationType {
        case .invert:
            return "invert(\(baseValue))"
        case .lighten:
            return "lighten(\(baseValue), 20%)"
        case .darken:
            return "darken(\(baseValue), 20%)"
        case .saturate:
            return "saturate(\(baseValue), 30%)"
        case .desaturate:
            return "desaturate(\(baseValue), 30%)"
        case .custom:
            return baseValue
        }
    }
}

// MARK: - Appearance Resolution Validator

/// Validates appearance resolutions for consistency
final class AppearanceResolutionValidator {
    /// Validate appearance palette
    static func validatePalette(_ palette: [String: [String: String]]) -> ValidationResult {
        var issues: [String] = []
        var warnings: [String] = []

        // Check for empty modes
        for (tokenId, modeValues) in palette {
            if modeValues["light"] == nil {
                issues.append("Token \(tokenId) missing light mode")
            }
        }

        // Check for value consistency
        var darkVariants = 0
        var contrastVariants = 0

        for (_, modeValues) in palette {
            if let light = modeValues["light"], let dark = modeValues["dark"], light != dark {
                darkVariants += 1
            }
            if let contrast = modeValues["contrast"] {
                contrastVariants += 1
            }
        }

        if darkVariants == 0 {
            warnings.append("No dark mode variants found")
        }

        if contrastVariants == 0 {
            warnings.append("No contrast mode variants found")
        }

        return ValidationResult(
            isValid: issues.isEmpty,
            errors: issues,
            warnings: warnings,
            summary: "Palette validation \(issues.isEmpty ? "passed" : "failed")"
        )
    }

    /// Validate appearance rules
    static func validateRules(_ rules: [AppearanceRule]) -> ValidationResult {
        var issues: [String] = []
        var warnings: [String] = []

        // Check for duplicate identifiers
        let ids = rules.map { $0.identifier }
        let uniqueIds = Set(ids)
        if ids.count != uniqueIds.count {
            issues.append("Duplicate rule identifiers found")
        }

        // Check for missing light values
        for rule in rules {
            if rule.lightValue.isEmpty {
                issues.append("Rule \(rule.identifier) has empty light value")
            }
        }

        // Check for orphaned rules
        if rules.isEmpty {
            warnings.append("No appearance rules registered")
        }

        return ValidationResult(
            isValid: issues.isEmpty,
            errors: issues,
            warnings: warnings,
            summary: "Rules validation \(issues.isEmpty ? "passed" : "failed")"
        )
    }

    /// Validate color scheme consistency
    static func validateColorSchemeConsistency(_ tokens: [String: [String: String]]) -> [String] {
        var inconsistencies: [String] = []

        for (tokenId, modeValues) in tokens {
            let values = modeValues.values.map { $0.lowercased() }
            let uniqueValues = Set(values)

            if uniqueValues.count == 1 {
                inconsistencies.append("Token \(tokenId) has identical values across all appearances")
            }
        }

        return inconsistencies
    }
}

/// Validation result
struct ValidationResult: Codable {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let summary: String

    var hasIssues: Bool {
        return !errors.isEmpty || !warnings.isEmpty
    }
}
