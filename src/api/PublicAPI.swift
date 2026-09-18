import Foundation

/// Public API for Apple Color Engine - complete implementation
/// Provides color extraction, normalization, variable resolution, and palette generation

// MARK: - Public Types

/// Represents a color value in multiple formats
public struct Color: Codable, Equatable {
    public let hex: String
    public let rgb: RGB
    public let hsl: HSL
    public let alpha: Double
    public let originalFormat: String
    public let source: String

    public init(hex: String, rgb: RGB, hsl: HSL, alpha: Double = 1.0, originalFormat: String, source: String) {
        self.hex = hex
        self.rgb = rgb
        self.hsl = hsl
        self.alpha = max(0, min(1, alpha))
        self.originalFormat = originalFormat
        self.source = source
    }
}

public struct RGB: Codable, Equatable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = max(0, min(255, red))
        self.green = max(0, min(255, green))
        self.blue = max(0, min(255, blue))
    }

    public func toHex() -> String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

public struct HSL: Codable, Equatable {
    public let hue: Double
    public let saturation: Double
    public let lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = fmod(max(0, hue), 360)
        self.saturation = max(0, min(100, saturation))
        self.lightness = max(0, min(100, lightness))
    }
}

public struct Token: Codable, Equatable {
    public let name: String
    public let value: Color
    public let category: String
    public let semanticRole: String?
    public let dependencies: [String]

    public init(name: String, value: Color, category: String, semanticRole: String? = nil, dependencies: [String] = []) {
        self.name = name
        self.value = value
        self.category = category
        self.semanticRole = semanticRole
        self.dependencies = dependencies
    }
}

public struct PaletteConfig: Codable {
    public let lightColors: [String: String]
    public let darkColors: [String: String]
    public let commonColors: [String: String]

    public init(lightColors: [String: String] = [:], darkColors: [String: String] = [:], commonColors: [String: String] = [:]) {
        self.lightColors = lightColors
        self.darkColors = darkColors
        self.commonColors = commonColors
    }
}

public struct ColorProvenance: Codable {
    public let tokenName: String
    public let source: String
    public let lineNumber: Int?
    public let cssSelector: String?
    public let mediaQuery: String?
    public let specificity: Int
    public let resolvedValue: String

    public init(tokenName: String, source: String, lineNumber: Int?, cssSelector: String?, mediaQuery: String?, specificity: Int, resolvedValue: String) {
        self.tokenName = tokenName
        self.source = source
        self.lineNumber = lineNumber
        self.cssSelector = cssSelector
        self.mediaQuery = mediaQuery
        self.specificity = specificity
        self.resolvedValue = resolvedValue
    }
}

// MARK: - Public API

public class ColorEngine {
    private var tokens: [String: Token] = [:]
    private var variables: [String: String] = [:]
    private var provenance: [String: ColorProvenance] = [:]
    private var semanticMappings: [String: String] = [:]

    public init() {}

    /// Parse HTML/CSS content and extract color definitions
    /// - Parameters:
    ///   - html: HTML content containing style tags or CSS
    ///   - cssContent: Raw CSS content
    /// - Returns: Dictionary of parsed styles and color references
    public func parseHTML(_ html: String) -> [String: String] {
        var styles: [String: String] = [:]

        // Extract style tags
        let stylePattern = "<style[^>]*>([^<]*)</style>"
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsString = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let css = String(html[range])
                    let parsed = parseCSS(css)
                    styles.merge(parsed) { _, new in new }
                }
            }
        }

        // Extract inline style attributes
        let inlinePattern = "style=\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: inlinePattern) {
            let nsString = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let styleStr = String(html[range])
                    let pairs = styleStr.split(separator: ";")
                    for pair in pairs {
                        let components = pair.split(separator: ":", maxSplits: 1)
                        if components.count == 2 {
                            let key = components[0].trimmingCharacters(in: .whitespaces)
                            let value = components[1].trimmingCharacters(in: .whitespaces)
                            styles[key] = value
                        }
                    }
                }
            }
        }

        return styles
    }

    /// Parse raw CSS content
    /// - Parameter css: CSS content string
    /// - Returns: Dictionary of parsed CSS rules
    public func parseCSS(_ css: String) -> [String: String] {
        var rules: [String: String] = [:]

        let lines = css.split(separator: ";")
        for line in lines {
            let components = line.split(separator: ":", maxSplits: 1)
            if components.count == 2 {
                let property = components[0].trimmingCharacters(in: .whitespaces)
                let value = components[1].trimmingCharacters(in: .whitespaces)
                rules[property] = value
            }
        }

        return rules
    }

    /// Extract colors from CSS values
    /// - Parameter cssContent: CSS content to search for color values
    /// - Returns: Array of extracted Color objects
    public func extractColors(from cssContent: String) -> [Color] {
        var colors: [Color] = []
        let colorPatterns: [(pattern: String, format: String)] = [
            (#"#([0-9a-fA-F]{8})"#, "RGBA"),
            (#"#([0-9a-fA-F]{6})"#, "RGB"),
            (#"#([0-9a-fA-F]{4})"#, "RGBA_SHORT"),
            (#"#([0-9a-fA-F]{3})"#, "RGB_SHORT"),
            (#"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)"#, "RGBA_FUNC"),
            (#"hsl\s*\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\)"#, "HSL")
        ]

        for (pattern, format) in colorPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = cssContent as NSString
                let matches = regex.matches(in: cssContent, range: NSRange(location: 0, length: nsString.length))

                for match in matches {
                    if let color = parseColorMatch(match, format: format, in: cssContent) {
                        colors.append(color)
                    }
                }
            }
        }

        return colors
    }

    /// Normalize color tokens from raw values
    /// - Parameter rawTokens: Raw color definitions
    /// - Returns: Array of normalized Token objects
    public func normalizeTokens(_ rawTokens: [String: String]) -> [Token] {
        var normalized: [Token] = []

        for (name, value) in rawTokens {
            if let color = parseColorValue(value) {
                let token = Token(
                    name: name,
                    value: color,
                    category: categorizeToken(name),
                    semanticRole: nil,
                    dependencies: extractDependencies(value)
                )
                normalized.append(token)
                self.tokens[name] = token
            }
        }

        return normalized
    }

    /// Resolve CSS variables (custom properties) in color definitions
    /// - Parameters:
    ///   - cssContent: CSS content with variable definitions
    ///   - fallback: Default color if variable not found
    /// - Returns: Dictionary of resolved variable names to color values
    public func resolveVariables(_ cssContent: String, fallback: String = "#000000") -> [String: String] {
        var resolved: [String: String] = [:]

        // Parse var() declarations
        let varPattern = #"--([a-zA-Z0-9-]+)\s*:\s*([^;]+)"#
        if let regex = try? NSRegularExpression(pattern: varPattern) {
            let nsString = cssContent as NSString
            let matches = regex.matches(in: cssContent, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: cssContent),
                   let valueRange = Range(match.range(at: 2), in: cssContent) {
                    let varName = String(cssContent[nameRange])
                    let varValue = String(cssContent[valueRange]).trimmingCharacters(in: .whitespaces)
                    self.variables[varName] = varValue
                    resolved[varName] = varValue
                }
            }
        }

        // Resolve nested variables
        for (name, value) in resolved {
            resolved[name] = resolveNestedVariables(value)
        }

        return resolved
    }

    /// Apply semantic mappings (e.g., primary, secondary, danger)
    /// - Parameters:
    ///   - tokens: Input tokens
    ///   - mappings: Semantic role mappings
    /// - Returns: Array of tokens with semantic roles applied
    public func applySemanticMappings(_ tokens: [Token], mappings: [String: String]) -> [Token] {
        var semanticTokens: [Token] = []
        self.semanticMappings = mappings

        for var token in tokens {
            if let semanticRole = findSemanticRole(for: token.name, in: mappings) {
                token = Token(
                    name: token.name,
                    value: token.value,
                    category: token.category,
                    semanticRole: semanticRole,
                    dependencies: token.dependencies
                )
            }
            semanticTokens.append(token)
        }

        return semanticTokens
    }

    /// Generate color palettes for light and dark modes
    /// - Parameters:
    ///   - tokens: Input tokens
    ///   - includeLight: Whether to generate light mode palette
    ///   - includeDark: Whether to generate dark mode palette
    /// - Returns: PaletteConfig containing light/dark/common colors
    public func generatePalettes(_ tokens: [Token], includeLight: Bool = true, includeDark: Bool = true) -> PaletteConfig {
        var lightColors: [String: String] = [:]
        var darkColors: [String: String] = [:]
        var commonColors: [String: String] = [:]

        for token in tokens {
            let hexValue = token.value.hex

            if token.name.contains("dark") || token.name.contains("bg-dark") {
                if includeDark {
                    darkColors[token.name] = "#\(hexValue)"
                }
            } else if token.name.contains("light") || token.name.contains("bg-light") {
                if includeLight {
                    lightColors[token.name] = "#\(hexValue)"
                }
            } else {
                commonColors[token.name] = "#\(hexValue)"
            }
        }

        return PaletteConfig(
            lightColors: lightColors,
            darkColors: darkColors,
            commonColors: commonColors
        )
    }

    /// Validate color definitions for consistency and correctness
    /// - Parameter tokens: Tokens to validate
    /// - Returns: Array of validation errors (empty if valid)
    public func validateColors(_ tokens: [Token]) -> [String] {
        var errors: [String] = []

        for token in tokens {
            // Check color value range
            if token.value.rgb.red < 0 || token.value.rgb.red > 255 {
                errors.append("Token '\(token.name)': Invalid red value \(token.value.rgb.red)")
            }
            if token.value.rgb.green < 0 || token.value.rgb.green > 255 {
                errors.append("Token '\(token.name)': Invalid green value \(token.value.rgb.green)")
            }
            if token.value.rgb.blue < 0 || token.value.rgb.blue > 255 {
                errors.append("Token '\(token.name)': Invalid blue value \(token.value.rgb.blue)")
            }
            if token.value.alpha < 0 || token.value.alpha > 1 {
                errors.append("Token '\(token.name)': Invalid alpha value \(token.value.alpha)")
            }

            // Check HSL ranges
            if token.value.hsl.saturation < 0 || token.value.hsl.saturation > 100 {
                errors.append("Token '\(token.name)': Invalid saturation \(token.value.hsl.saturation)")
            }
            if token.value.hsl.lightness < 0 || token.value.hsl.lightness > 100 {
                errors.append("Token '\(token.name)': Invalid lightness \(token.value.hsl.lightness)")
            }
        }

        return errors
    }

    /// Retrieve provenance information for a color token
    /// - Parameter tokenName: Name of the token
    /// - Returns: ColorProvenance object with source and context
    public func getProvenance(for tokenName: String) -> ColorProvenance? {
        return provenance[tokenName]
    }

    /// Set provenance information for a token
    /// - Parameters:
    ///   - tokenName: Name of the token
    ///   - provenance: ColorProvenance object
    public func setProvenance(_ provenance: ColorProvenance, for tokenName: String) {
        self.provenance[tokenName] = provenance
    }

    /// Serialize color tokens to JSON
    /// - Parameter tokens: Tokens to serialize
    /// - Returns: JSON string representation
    public func serializeToJSON(_ tokens: [Token]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(tokens)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Serialize to custom text format
    /// - Parameter tokens: Tokens to serialize
    /// - Returns: Formatted text representation
    public func serializeToText(_ tokens: [Token]) -> String {
        var output = ""

        for token in tokens {
            output += "Token: \(token.name)\n"
            output += "  Hex: #\(token.value.hex)\n"
            output += "  RGB: rgb(\(token.value.rgb.red), \(token.value.rgb.green), \(token.value.rgb.blue))\n"
            output += "  HSL: hsl(\(Int(token.value.hsl.hue)), \(Int(token.value.hsl.saturation))%, \(Int(token.value.hsl.lightness))%)\n"
            output += "  Category: \(token.category)\n"
            if let semantic = token.semanticRole {
                output += "  Semantic: \(semantic)\n"
            }
            output += "\n"
        }

        return output
    }

    // MARK: - Private Helpers

    private func parseColorMatch(_ match: NSTextCheckingResult, format: String, in text: String) -> Color? {
        let nsString = text as NSString

        switch format {
        case "RGB":
            if let range = Range(match.range(at: 1), in: text) {
                let hex = String(text[range])
                return parseHexColor(hex)
            }
        case "RGBA":
            if let range = Range(match.range(at: 1), in: text) {
                let hex = String(text[range])
                return parseHexColor(hex)
            }
        case "RGB_SHORT":
            if let range = Range(match.range(at: 1), in: text) {
                let hex = String(text[range])
                let expanded = hex.map { String($0) + String($0) }.joined()
                return parseHexColor(expanded)
            }
        case "RGBA_SHORT":
            if let range = Range(match.range(at: 1), in: text) {
                let hex = String(text[range])
                let expanded = hex.map { String($0) + String($0) }.joined()
                return parseHexColor(expanded)
            }
        case "RGBA_FUNC":
            if match.numberOfRanges >= 4,
               let r = Int(nsString.substring(with: match.range(at: 1))),
               let g = Int(nsString.substring(with: match.range(at: 2))),
               let b = Int(nsString.substring(with: match.range(at: 3))) {
                let alpha = match.numberOfRanges > 4 ? Double(nsString.substring(with: match.range(at: 4))) ?? 1.0 : 1.0
                return createColor(from: RGB(red: r, green: g, blue: b), alpha: alpha, format: "rgba()")
            }
        case "HSL":
            if match.numberOfRanges >= 4,
               let h = Double(nsString.substring(with: match.range(at: 1))),
               let s = Double(nsString.substring(with: match.range(at: 2))),
               let l = Double(nsString.substring(with: match.range(at: 3))) {
                return createColor(fromHSL: HSL(hue: h, saturation: s, lightness: l), format: "hsl()")
            }
        default:
            break
        }

        return nil
    }

    private func parseHexColor(_ hex: String) -> Color? {
        let cleanHex = hex.count == 8 ? hex : hex.count == 6 ? hex : nil
        guard let clean = cleanHex else { return nil }

        let alpha: Double
        let rgbHex: String

        if clean.count == 8 {
            rgbHex = String(clean.prefix(6))
            let alphaHex = String(clean.suffix(2))
            if let alphaByte = UInt8(alphaHex, radix: 16) {
                alpha = Double(alphaByte) / 255.0
            } else {
                alpha = 1.0
            }
        } else {
            rgbHex = clean
            alpha = 1.0
        }

        guard let rgb = hexToRGB(rgbHex) else { return nil }
        return createColor(from: rgb, alpha: alpha, format: "hex")
    }

    private func hexToRGB(_ hex: String) -> RGB? {
        guard hex.count == 6 else { return nil }

        if let value = UInt32(hex, radix: 16) {
            let r = Int((value >> 16) & 0xFF)
            let g = Int((value >> 8) & 0xFF)
            let b = Int(value & 0xFF)
            return RGB(red: r, green: g, blue: b)
        }

        return nil
    }

    private func createColor(from rgb: RGB, alpha: Double = 1.0, format: String) -> Color {
        let hsl = rgbToHSL(rgb)
        return Color(
            hex: rgb.toHex(),
            rgb: rgb,
            hsl: hsl,
            alpha: alpha,
            originalFormat: format,
            source: "extracted"
        )
    }

    private func createColor(fromHSL hsl: HSL, format: String) -> Color {
        let rgb = hslToRGB(hsl)
        return Color(
            hex: rgb.toHex(),
            rgb: rgb,
            hsl: hsl,
            alpha: 1.0,
            originalFormat: format,
            source: "extracted"
        )
    }

    private func rgbToHSL(_ rgb: RGB) -> HSL {
        let r = Double(rgb.red) / 255.0
        let g = Double(rgb.green) / 255.0
        let b = Double(rgb.blue) / 255.0

        let max = [r, g, b].max() ?? 0
        let min = [r, g, b].min() ?? 0
        let l = (max + min) / 2

        guard max != min else {
            return HSL(hue: 0, saturation: 0, lightness: l * 100)
        }

        let d = max - min
        let s = l > 0.5 ? d / (2 - max - min) : d / (max + min)

        let h: Double
        switch max {
        case r: h = fmod((g - b) / d + (g < b ? 6 : 0), 6)
        case g: h = (b - r) / d + 2
        case b: h = (r - g) / d + 4
        default: h = 0
        }

        return HSL(hue: h * 60, saturation: s * 100, lightness: l * 100)
    }

    private func hslToRGB(_ hsl: HSL) -> RGB {
        let h = hsl.hue / 360
        let s = hsl.saturation / 100
        let l = hsl.lightness / 100

        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs(fmod(h * 6, 2) - 1))
        let m = l - c / 2

        let (r, g, b): (Double, Double, Double)
        switch h * 6 {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }

        return RGB(
            red: Int(round((r + m) * 255)),
            green: Int(round((g + m) * 255)),
            blue: Int(round((b + m) * 255))
        )
    }

    private func parseColorValue(_ value: String) -> Color? {
        if value.hasPrefix("#") {
            return parseHexColor(String(value.dropFirst()))
        }

        if value.hasPrefix("rgb") {
            let pattern = #"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = value as NSString
                if let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: nsString.length)) {
                    if let r = Int(nsString.substring(with: match.range(at: 1))),
                       let g = Int(nsString.substring(with: match.range(at: 2))),
                       let b = Int(nsString.substring(with: match.range(at: 3))) {
                        let alpha = match.numberOfRanges > 4 ? Double(nsString.substring(with: match.range(at: 4))) ?? 1.0 : 1.0
                        return createColor(from: RGB(red: r, green: g, blue: b), alpha: alpha, format: "rgb()")
                    }
                }
            }
        }

        if value.hasPrefix("hsl") {
            let pattern = #"hsl\s*\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = value as NSString
                if let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: nsString.length)) {
                    if let h = Double(nsString.substring(with: match.range(at: 1))),
                       let s = Double(nsString.substring(with: match.range(at: 2))),
                       let l = Double(nsString.substring(with: match.range(at: 3))) {
                        return createColor(fromHSL: HSL(hue: h, saturation: s, lightness: l), format: "hsl()")
                    }
                }
            }
        }

        return nil
    }

    private func categorizeToken(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("primary") { return "primary" }
        if lower.contains("secondary") { return "secondary" }
        if lower.contains("danger") || lower.contains("error") { return "danger" }
        if lower.contains("success") { return "success" }
        if lower.contains("warning") { return "warning" }
        if lower.contains("info") { return "info" }
        if lower.contains("background") || lower.contains("bg") { return "background" }
        if lower.contains("text") || lower.contains("foreground") { return "text" }
        if lower.contains("border") { return "border" }
        return "neutral"
    }

    private func extractDependencies(_ value: String) -> [String] {
        var deps: [String] = []

        if let regex = try? NSRegularExpression(pattern: #"var\(--?([a-zA-Z0-9-]+)"#) {
            let nsString = value as NSString
            let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: value) {
                    deps.append(String(value[range]))
                }
            }
        }

        return deps
    }

    private func resolveNestedVariables(_ value: String) -> String {
        var result = value
        var attempts = 0
        let maxAttempts = 10

        while result.contains("var(") && attempts < maxAttempts {
            attempts += 1
            if let regex = try? NSRegularExpression(pattern: #"var\(--?([a-zA-Z0-9-]+)"#) {
                let nsString = result as NSString
                if let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: nsString.length)) {
                    if let varRange = Range(match.range(at: 1), in: result) {
                        let varName = String(result[varRange])
                        if let resolvedValue = self.variables[varName] {
                            if let fullRange = Range(match.range, in: result) {
                                result.replaceSubrange(fullRange, with: resolvedValue)
                            }
                        } else {
                            break
                        }
                    }
                } else {
                    break
                }
            }
        }

        return result
    }

    private func findSemanticRole(for tokenName: String, in mappings: [String: String]) -> String? {
        let lower = tokenName.lowercased()

        for (pattern, role) in mappings {
            if lower.contains(pattern.lowercased()) {
                return role
            }
        }

        return nil
    }
}
