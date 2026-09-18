import Foundation

public struct ColorLiteral: Codable, Hashable {
    public enum Format: String, Codable {
        case hex
        case rgb
        case rgba
        case hsl
        case hsla
        case named
        case variable
        case function
    }

    public let value: String
    public let format: Format
    public let location: SourceLocation

    public init(value: String, format: Format, location: SourceLocation) {
        self.value = value
        self.format = format
        self.location = location
    }
}

public struct VariableReference: Codable, Hashable {
    public let variableName: String
    public let fallback: String?
    public let location: SourceLocation

    public init(variableName: String, fallback: String?, location: SourceLocation) {
        self.variableName = variableName
        self.fallback = fallback
        self.location = location
    }
}

public struct PatternMatch: Codable, Hashable {
    public let selector: String?
    public let property: String?
    public let mediaQuery: String?
    public let colorLiterals: [ColorLiteral]
    public let variables: [VariableReference]
    public let rawValue: String
    public let location: SourceLocation
    public let isPseudoClass: Bool

    public init(
        selector: String?,
        property: String?,
        mediaQuery: String?,
        colorLiterals: [ColorLiteral],
        variables: [VariableReference],
        rawValue: String,
        location: SourceLocation,
        isPseudoClass: Bool = false
    ) {
        self.selector = selector
        self.property = property
        self.mediaQuery = mediaQuery
        self.colorLiterals = colorLiterals
        self.variables = variables
        self.rawValue = rawValue
        self.location = location
        self.isPseudoClass = isPseudoClass
    }
}

public struct ExtractionContext {
    public let selector: String?
    public let property: String?
    public let mediaQuery: String?
    public let isPseudoClass: Bool

    public init(selector: String? = nil, property: String? = nil, mediaQuery: String? = nil, isPseudoClass: Bool = false) {
        self.selector = selector
        self.property = property
        self.mediaQuery = mediaQuery
        self.isPseudoClass = isPseudoClass
    }
}

public class PatternExtractor {
    private let rules: [CSSRule]
    private let atRules: [CSSAtRule]
    private let customProperties: [CSSCustomProperty]
    private var patterns: [PatternMatch] = []

    private let hexPattern = try! NSRegularExpression(pattern: "#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", options: [])
    private let rgbPattern = try! NSRegularExpression(pattern: "rgba?\\s*\\(\\s*([^)]+)\\s*\\)", options: [])
    private let hslPattern = try! NSRegularExpression(pattern: "hsla?\\s*\\(\\s*([^)]+)\\s*\\)", options: [])
    private let variablePattern = try! NSRegularExpression(pattern: "var\\s*\\(\\s*--([a-zA-Z0-9-]+)\\s*(?:,\\s*([^)]*))?\\s*\\)", options: [])
    private let namedColorPattern: Set<String> = [
        "red", "green", "blue", "white", "black", "yellow", "cyan", "magenta",
        "silver", "gray", "maroon", "olive", "lime", "aqua", "teal", "navy",
        "fuchsia", "purple", "orange", "brown", "pink", "transparent", "inherit",
        "currentcolor", "currentColor"
    ]

    public init(rules: [CSSRule], atRules: [CSSAtRule], customProperties: [CSSCustomProperty]) {
        self.rules = rules
        self.atRules = atRules
        self.customProperties = customProperties
    }

    public func extractAllPatterns() -> [PatternMatch] {
        patterns.removeAll()

        for rule in rules {
            let context = ExtractionContext(
                selector: rule.selector.selector,
                mediaQuery: rule.media,
                isPseudoClass: rule.selector.isPseudoClass
            )

            for declaration in rule.declarations {
                extractPatternsFromValue(
                    declaration.value,
                    context: ExtractionContext(
                        selector: context.selector,
                        property: declaration.property,
                        mediaQuery: context.mediaQuery,
                        isPseudoClass: context.isPseudoClass
                    ),
                    location: declaration.location
                )
            }
        }

        for atRule in atRules {
            if case .media = atRule.type {
                extractMediaRulePatterns(atRule)
            }
        }

        for customProp in customProperties {
            extractPatternsFromValue(
                customProp.value,
                context: ExtractionContext(selector: customProp.scope),
                location: customProp.location
            )
        }

        return patterns
    }

    private func extractMediaRulePatterns(_ atRule: CSSAtRule) {
        let subParser = CSSParser(css: atRule.content, filename: "")
        let result = subParser.parse()

        for rule in result.rules {
            let context = ExtractionContext(
                selector: rule.selector.selector,
                mediaQuery: atRule.prelude,
                isPseudoClass: rule.selector.isPseudoClass
            )

            for declaration in rule.declarations {
                extractPatternsFromValue(
                    declaration.value,
                    context: ExtractionContext(
                        selector: context.selector,
                        property: declaration.property,
                        mediaQuery: context.mediaQuery,
                        isPseudoClass: context.isPseudoClass
                    ),
                    location: declaration.location
                )
            }
        }
    }

    private func extractPatternsFromValue(_ value: String, context: ExtractionContext, location: SourceLocation) {
        let colorLiterals = extractColorLiterals(from: value, location: location)
        let variables = extractVariables(from: value, location: location)

        if !colorLiterals.isEmpty || !variables.isEmpty {
            let pattern = PatternMatch(
                selector: context.selector,
                property: context.property,
                mediaQuery: context.mediaQuery,
                colorLiterals: colorLiterals,
                variables: variables,
                rawValue: value,
                location: location,
                isPseudoClass: context.isPseudoClass
            )
            patterns.append(pattern)
        }
    }

    private func extractColorLiterals(from value: String, location: SourceLocation) -> [ColorLiteral] {
        var colorLiterals: [ColorLiteral] = []
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)

        hexPattern.enumerateMatches(in: value, options: [], range: range) { match, _, _ in
            if let match = match {
                if let range = Range(match.range, in: value) {
                    let hexValue = String(value[range])
                    colorLiterals.append(ColorLiteral(value: hexValue, format: .hex, location: location))
                }
            }
        }

        rgbPattern.enumerateMatches(in: value, options: [], range: range) { match, _, _ in
            if let match = match {
                if let range = Range(match.range, in: value) {
                    let rgbValue = String(value[range])
                    let format: ColorLiteral.Format = rgbValue.lowercased().contains("rgba") ? .rgba : .rgb
                    colorLiterals.append(ColorLiteral(value: rgbValue, format: format, location: location))
                }
            }
        }

        hslPattern.enumerateMatches(in: value, options: [], range: range) { match, _, _ in
            if let match = match {
                if let range = Range(match.range, in: value) {
                    let hslValue = String(value[range])
                    let format: ColorLiteral.Format = hslValue.lowercased().contains("hsla") ? .hsla : .hsl
                    colorLiterals.append(ColorLiteral(value: hslValue, format: format, location: location))
                }
            }
        }

        let cleanValue = value.lowercased()
        for namedColor in namedColorPattern {
            if cleanValue.contains(namedColor) {
                let pattern = "\\b\(namedColor)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    regex.enumerateMatches(in: value, options: [], range: range) { match, _, _ in
                        if let match = match {
                            if let range = Range(match.range, in: value) {
                                let colorName = String(value[range])
                                colorLiterals.append(ColorLiteral(value: colorName, format: .named, location: location))
                            }
                        }
                    }
                }
            }
        }

        return colorLiterals
    }

    private func extractVariables(from value: String, location: SourceLocation) -> [VariableReference] {
        var variables: [VariableReference] = []
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)

        variablePattern.enumerateMatches(in: value, options: [], range: range) { match, _, _ in
            if let match = match, match.numberOfRanges > 1 {
                if let varNameRange = Range(match.range(at: 1), in: value) {
                    let varName = String(value[varNameRange])
                    var fallback: String? = nil

                    if match.numberOfRanges > 2 {
                        if let fallbackRange = Range(match.range(at: 2), in: value) {
                            fallback = String(value[fallbackRange]).trimmingCharacters(in: .whitespaces)
                        }
                    }

                    variables.append(VariableReference(variableName: varName, fallback: fallback, location: location))
                }
            }
        }

        return variables
    }

    public func extractColorPatternsOnly() -> [PatternMatch] {
        return patterns.filter { !$0.colorLiterals.isEmpty }
    }

    public func extractVariableReferencesOnly() -> [PatternMatch] {
        return patterns.filter { !$0.variables.isEmpty }
    }

    public func extractPatternsForSelector(_ selector: String) -> [PatternMatch] {
        return patterns.filter { $0.selector == selector }
    }

    public func extractPatternsForProperty(_ property: String) -> [PatternMatch] {
        return patterns.filter { $0.property == property }
    }

    public func extractPatternsForMediaQuery(_ mediaQuery: String) -> [PatternMatch] {
        return patterns.filter { $0.mediaQuery == mediaQuery }
    }

    public func buildFallbackChain(for variableRef: VariableReference) -> [String] {
        var chain: [String] = []
        var current: String? = variableRef.variableName

        while let varName = current {
            chain.append(varName)

            if let customProp = customProperties.first(where: { $0.name == "--\(varName)" }) {
                let variables = extractVariables(from: customProp.value, location: customProp.location)
                if let nextVar = variables.first?.variableName {
                    current = nextVar
                } else {
                    current = nil
                }
            } else {
                current = nil
            }
        }

        return chain
    }

    public func getPatternMetadata() -> [String: Int] {
        var metadata: [String: Int] = [:]

        let colorPatterns = patterns.filter { !$0.colorLiterals.isEmpty }.count
        let variablePatterns = patterns.filter { !$0.variables.isEmpty }.count
        let mediaQueryPatterns = patterns.filter { $0.mediaQuery != nil }.count
        let pseudoClassPatterns = patterns.filter { $0.isPseudoClass }.count

        metadata["total_patterns"] = patterns.count
        metadata["color_patterns"] = colorPatterns
        metadata["variable_patterns"] = variablePatterns
        metadata["media_query_patterns"] = mediaQueryPatterns
        metadata["pseudo_class_patterns"] = pseudoClassPatterns

        var propertyFrequency: [String: Int] = [:]
        for pattern in patterns {
            if let property = pattern.property {
                propertyFrequency[property, default: 0] += 1
            }
        }

        for (property, count) in propertyFrequency {
            metadata["property_\(property)"] = count
        }

        return metadata
    }
}

public class ExtractorPipeline {
    public let htmlParser: HTMLParser
    public let cssParser: CSSParser
    public let patternExtractor: PatternExtractor

    public init(htmlContent: String, cssContent: String, htmlFilename: String = "unknown.html", cssFilename: String = "unknown.css") {
        htmlParser = HTMLParser(html: htmlContent, filename: htmlFilename)
        cssParser = CSSParser(css: cssContent, filename: cssFilename)

        let htmlResult = htmlParser.parse()
        let cssResult = cssParser.parse()

        patternExtractor = PatternExtractor(
            rules: cssResult.rules,
            atRules: cssResult.atRules,
            customProperties: cssResult.customProperties
        )
    }

    public func run() -> [PatternMatch] {
        return patternExtractor.extractAllPatterns()
    }

    public func getHtmlElements() -> [HTMLElement] {
        return htmlParser.parse().elements
    }

    public func getInlineStyles() -> [HTMLElement] {
        return htmlParser.parse().inlineStyles
    }

    public func getCssRules() -> [CSSRule] {
        return cssParser.parse().rules
    }

    public func getSummary() -> [String: Any] {
        let htmlResult = htmlParser.parse()
        let cssResult = cssParser.parse()
        let patterns = patternExtractor.extractAllPatterns()

        return [
            "html_elements": htmlResult.elements.count,
            "inline_styles": htmlResult.inlineStyles.count,
            "style_blocks": htmlResult.styleBlocks.count,
            "css_rules": cssResult.rules.count,
            "css_at_rules": cssResult.atRules.count,
            "css_custom_properties": cssResult.customProperties.count,
            "total_declarations": cssResult.declarations.count,
            "patterns_extracted": patterns.count,
            "color_patterns": patterns.filter { !$0.colorLiterals.isEmpty }.count,
            "variable_patterns": patterns.filter { !$0.variables.isEmpty }.count,
            "media_queries": cssResult.mediaQueries.count,
            "pseudo_elements": cssResult.pseudoElements.count,
            "pseudo_classes": cssResult.pseudoClasses.count,
            "parse_errors": htmlResult.errors.count + cssResult.errors.count
        ]
    }
}
