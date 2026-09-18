import Foundation

/// Enumeration of supported color formats
enum ColorFormatType: String, Codable {
    case hex
    case rgb
    case rgba
    case hsl
    case hsla
    case cssVariable
    case named
    case unknown
}

/// Represents a parsed color with format information and component values
struct ParsedColor: Codable {
    let format: ColorFormatType
    let originalString: String
    let red: Int?
    let green: Int?
    let blue: Int?
    let alpha: Double?
    let hue: Double?
    let saturation: Double?
    let lightness: Double?
    let variableName: String?
    let fallback: String?
    let namedColor: String?

    var hasAlpha: Bool {
        alpha != nil && alpha != 1.0
    }

    var alphaValue: Double {
        alpha ?? 1.0
    }
}

/// ColorFormat handles detection and parsing of various color format types
class ColorFormat {
    private static let hexPattern = "^#(?:[0-9a-fA-F]{3}){1,2}([0-9a-fA-F]{2})?$"
    private static let rgbPattern = "^rgba?\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*(?:,\\s*([0-9.]+)\\s*)?\\)$"
    private static let hslPattern = "^hsla?\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)%\\s*,\\s*([0-9.]+)%\\s*(?:,\\s*([0-9.]+)\\s*)?\\)$"
    private static let cssVarPattern = "^var\\s*\\(\\s*--([a-zA-Z0-9_-]+)\\s*(?:,\\s*(.+)\\s*)?\\)$"

    private static let namedColors: [String: (r: Int, g: Int, b: Int)] = [
        "red": (255, 0, 0),
        "green": (0, 128, 0),
        "blue": (0, 0, 255),
        "white": (255, 255, 255),
        "black": (0, 0, 0),
        "gray": (128, 128, 128),
        "grey": (128, 128, 128),
        "silver": (192, 192, 192),
        "maroon": (128, 0, 0),
        "olive": (128, 128, 0),
        "lime": (0, 255, 0),
        "aqua": (0, 255, 255),
        "teal": (0, 128, 128),
        "navy": (0, 0, 128),
        "fuchsia": (255, 0, 255),
        "purple": (128, 0, 128),
        "yellow": (255, 255, 0),
        "orange": (255, 165, 0),
        "pink": (255, 192, 203),
        "brown": (165, 42, 42),
        "cyan": (0, 255, 255),
        "magenta": (255, 0, 255),
        "transparent": (0, 0, 0),
    ]

    /// Detects the format type of a color string
    /// - Parameter colorString: The color string to analyze
    /// - Returns: The detected ColorFormatType
    static func detectFormat(_ colorString: String) -> ColorFormatType {
        let trimmed = colorString.trimmingCharacters(in: .whitespaces)

        if isHexFormat(trimmed) {
            return .hex
        }

        if isRGBFormat(trimmed) {
            return trimmed.lowercased().hasPrefix("rgba") ? .rgba : .rgb
        }

        if isHSLFormat(trimmed) {
            return trimmed.lowercased().hasPrefix("hsla") ? .hsla : .hsl
        }

        if isCSSVariable(trimmed) {
            return .cssVariable
        }

        if isNamedColor(trimmed) {
            return .named
        }

        return .unknown
    }

    /// Parses a color string and returns structured color information
    /// - Parameter colorString: The color string to parse
    /// - Returns: ParsedColor with extracted components, or nil if parsing fails
    static func parseColor(_ colorString: String) -> ParsedColor? {
        let trimmed = colorString.trimmingCharacters(in: .whitespaces)
        let format = detectFormat(trimmed)

        switch format {
        case .hex:
            return parseHexColor(trimmed)
        case .rgb:
            return parseRGBColor(trimmed, isRGBA: false)
        case .rgba:
            return parseRGBColor(trimmed, isRGBA: true)
        case .hsl:
            return parseHSLColor(trimmed, isHSLA: false)
        case .hsla:
            return parseHSLColor(trimmed, isHSLA: true)
        case .cssVariable:
            return parseCSSVariable(trimmed)
        case .named:
            return parseNamedColor(trimmed)
        case .unknown:
            return nil
        }
    }

    // MARK: - Private Helper Methods

    private static func isHexFormat(_ color: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: hexPattern) else {
            return false
        }
        let range = NSRange(color.startIndex..., in: color)
        return regex.firstMatch(in: color, range: range) != nil
    }

    private static func parseHexColor(_ color: String) -> ParsedColor? {
        var hex = color
        if hex.hasPrefix("#") {
            hex = String(hex.dropFirst())
        }

        var red: Int?
        var green: Int?
        var blue: Int?
        var alpha: Double?

        if hex.count == 3 {
            // #RGB format
            if let r = Int(String(hex[hex.index(hex.startIndex, offsetBy: 0)]), radix: 16),
               let g = Int(String(hex[hex.index(hex.startIndex, offsetBy: 1)]), radix: 16),
               let b = Int(String(hex[hex.index(hex.startIndex, offsetBy: 2)]), radix: 16) {
                red = r * 17
                green = g * 17
                blue = b * 17
                alpha = 1.0
            } else {
                return nil
            }
        } else if hex.count == 4 {
            // #RGBA format
            if let r = Int(String(hex[hex.index(hex.startIndex, offsetBy: 0)]), radix: 16),
               let g = Int(String(hex[hex.index(hex.startIndex, offsetBy: 1)]), radix: 16),
               let b = Int(String(hex[hex.index(hex.startIndex, offsetBy: 2)]), radix: 16),
               let a = Int(String(hex[hex.index(hex.startIndex, offsetBy: 3)]), radix: 16) {
                red = r * 17
                green = g * 17
                blue = b * 17
                alpha = Double(a) / 15.0
            } else {
                return nil
            }
        } else if hex.count == 6 {
            // #RRGGBB format
            if let r = Int(String(hex.prefix(2)), radix: 16),
               let g = Int(String(hex.dropFirst(2).prefix(2)), radix: 16),
               let b = Int(String(hex.dropFirst(4).prefix(2)), radix: 16) {
                red = r
                green = g
                blue = b
                alpha = 1.0
            } else {
                return nil
            }
        } else if hex.count == 8 {
            // #RRGGBBAA format
            if let r = Int(String(hex.prefix(2)), radix: 16),
               let g = Int(String(hex.dropFirst(2).prefix(2)), radix: 16),
               let b = Int(String(hex.dropFirst(4).prefix(2)), radix: 16),
               let a = Int(String(hex.dropFirst(6).prefix(2)), radix: 16) {
                red = r
                green = g
                blue = b
                alpha = Double(a) / 255.0
            } else {
                return nil
            }
        } else {
            return nil
        }

        return ParsedColor(
            format: .hex,
            originalString: color,
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            hue: nil,
            saturation: nil,
            lightness: nil,
            variableName: nil,
            fallback: nil,
            namedColor: nil
        )
    }

    private static func isRGBFormat(_ color: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: rgbPattern) else {
            return false
        }
        let range = NSRange(color.startIndex..., in: color)
        return regex.firstMatch(in: color, range: range) != nil
    }

    private static func parseRGBColor(_ color: String, isRGBA: Bool) -> ParsedColor? {
        guard let regex = try? NSRegularExpression(pattern: rgbPattern) else {
            return nil
        }

        let range = NSRange(color.startIndex..., in: color)
        guard let match = regex.firstMatch(in: color, range: range) else {
            return nil
        }

        var red: Int?
        var green: Int?
        var blue: Int?
        var alpha: Double = 1.0

        if match.numberOfRanges >= 4 {
            if let rRange = Range(match.range(at: 1), in: color),
               let r = Int(String(color[rRange])) {
                red = min(max(r, 0), 255)
            }

            if let gRange = Range(match.range(at: 2), in: color),
               let g = Int(String(color[gRange])) {
                green = min(max(g, 0), 255)
            }

            if let bRange = Range(match.range(at: 3), in: color),
               let b = Int(String(color[bRange])) {
                blue = min(max(b, 0), 255)
            }

            if isRGBA, match.numberOfRanges >= 5, match.range(at: 4).length > 0 {
                if let aRange = Range(match.range(at: 4), in: color),
                   let a = Double(String(color[aRange])) {
                    alpha = min(max(a, 0), 1.0)
                }
            }
        }

        return ParsedColor(
            format: isRGBA ? .rgba : .rgb,
            originalString: color,
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            hue: nil,
            saturation: nil,
            lightness: nil,
            variableName: nil,
            fallback: nil,
            namedColor: nil
        )
    }

    private static func isHSLFormat(_ color: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: hslPattern) else {
            return false
        }
        let range = NSRange(color.startIndex..., in: color)
        return regex.firstMatch(in: color, range: range) != nil
    }

    private static func parseHSLColor(_ color: String, isHSLA: Bool) -> ParsedColor? {
        guard let regex = try? NSRegularExpression(pattern: hslPattern) else {
            return nil
        }

        let range = NSRange(color.startIndex..., in: color)
        guard let match = regex.firstMatch(in: color, range: range) else {
            return nil
        }

        var hue: Double?
        var saturation: Double?
        var lightness: Double?
        var alpha: Double = 1.0

        if match.numberOfRanges >= 4 {
            if let hRange = Range(match.range(at: 1), in: color),
               let h = Double(String(color[hRange])) {
                hue = h.truncatingRemainder(dividingBy: 360)
                if hue! < 0 { hue! += 360 }
            }

            if let sRange = Range(match.range(at: 2), in: color),
               let s = Double(String(color[sRange])) {
                saturation = min(max(s, 0), 100)
            }

            if let lRange = Range(match.range(at: 3), in: color),
               let l = Double(String(color[lRange])) {
                lightness = min(max(l, 0), 100)
            }

            if isHSLA, match.numberOfRanges >= 5, match.range(at: 4).length > 0 {
                if let aRange = Range(match.range(at: 4), in: color),
                   let a = Double(String(color[aRange])) {
                    alpha = min(max(a, 0), 1.0)
                }
            }
        }

        return ParsedColor(
            format: isHSLA ? .hsla : .hsl,
            originalString: color,
            red: nil,
            green: nil,
            blue: nil,
            alpha: alpha,
            hue: hue,
            saturation: saturation,
            lightness: lightness,
            variableName: nil,
            fallback: nil,
            namedColor: nil
        )
    }

    private static func isCSSVariable(_ color: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: cssVarPattern) else {
            return false
        }
        let range = NSRange(color.startIndex..., in: color)
        return regex.firstMatch(in: color, range: range) != nil
    }

    private static func parseCSSVariable(_ color: String) -> ParsedColor? {
        guard let regex = try? NSRegularExpression(pattern: cssVarPattern) else {
            return nil
        }

        let range = NSRange(color.startIndex..., in: color)
        guard let match = regex.firstMatch(in: color, range: range) else {
            return nil
        }

        var variableName: String?
        var fallback: String?

        if match.numberOfRanges >= 2 {
            if let nameRange = Range(match.range(at: 1), in: color) {
                variableName = String(color[nameRange])
            }
        }

        if match.numberOfRanges >= 3, match.range(at: 2).length > 0 {
            if let fallbackRange = Range(match.range(at: 2), in: color) {
                fallback = String(color[fallbackRange]).trimmingCharacters(in: .whitespaces)
            }
        }

        return ParsedColor(
            format: .cssVariable,
            originalString: color,
            red: nil,
            green: nil,
            blue: nil,
            alpha: nil,
            hue: nil,
            saturation: nil,
            lightness: nil,
            variableName: variableName,
            fallback: fallback,
            namedColor: nil
        )
    }

    private static func isNamedColor(_ color: String) -> Bool {
        return namedColors[color.lowercased()] != nil
    }

    private static func parseNamedColor(_ color: String) -> ParsedColor? {
        let lowerColor = color.lowercased()

        guard let rgb = namedColors[lowerColor] else {
            return nil
        }

        return ParsedColor(
            format: .named,
            originalString: color,
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
            alpha: lowerColor == "transparent" ? 0.0 : 1.0,
            hue: nil,
            saturation: nil,
            lightness: nil,
            variableName: nil,
            fallback: nil,
            namedColor: lowerColor
        )
    }

    /// Validates that RGB components are within acceptable ranges
    /// - Parameter red: Red component (0-255)
    /// - Parameter green: Green component (0-255)
    /// - Parameter blue: Blue component (0-255)
    /// - Parameter alpha: Alpha component (0-1)
    /// - Returns: True if all components are valid
    static func validateRGBComponents(red: Int, green: Int, blue: Int, alpha: Double) -> Bool {
        let rgbValid = red >= 0 && red <= 255 && green >= 0 && green <= 255 && blue >= 0 && blue <= 255
        let alphaValid = alpha >= 0.0 && alpha <= 1.0
        return rgbValid && alphaValid
    }

    /// Validates that HSL components are within acceptable ranges
    /// - Parameter hue: Hue component (0-360)
    /// - Parameter saturation: Saturation component (0-100)
    /// - Parameter lightness: Lightness component (0-100)
    /// - Parameter alpha: Alpha component (0-1)
    /// - Returns: True if all components are valid
    static func validateHSLComponents(hue: Double, saturation: Double, lightness: Double, alpha: Double) -> Bool {
        let hueValid = hue >= 0 && hue < 360
        let saturationValid = saturation >= 0 && saturation <= 100
        let lightnessValid = lightness >= 0 && lightness <= 100
        let alphaValid = alpha >= 0.0 && alpha <= 1.0
        return hueValid && saturationValid && lightnessValid && alphaValid
    }

    /// Extracts the alpha channel from a parsed color
    /// - Parameter parsed: The ParsedColor to extract alpha from
    /// - Returns: Alpha value (0-1), defaulting to 1.0 if not present
    static func extractAlpha(from parsed: ParsedColor) -> Double {
        return parsed.alpha ?? 1.0
    }

    /// Formats RGB values as a hex string
    /// - Parameter red: Red component (0-255)
    /// - Parameter green: Green component (0-255)
    /// - Parameter blue: Blue component (0-255)
    /// - Parameter alpha: Optional alpha component (0-1)
    /// - Returns: Hex color string starting with #
    static func formatAsHex(red: Int, green: Int, blue: Int, alpha: Double? = nil) -> String {
        let hexRed = String(format: "%02X", red)
        let hexGreen = String(format: "%02X", green)
        let hexBlue = String(format: "%02X", blue)

        if let alpha = alpha, alpha < 1.0 {
            let hexAlpha = String(format: "%02X", Int(alpha * 255))
            return "#\(hexRed)\(hexGreen)\(hexBlue)\(hexAlpha)"
        }

        return "#\(hexRed)\(hexGreen)\(hexBlue)"
    }

    /// Formats RGB values as an RGB/RGBA string
    /// - Parameter red: Red component (0-255)
    /// - Parameter green: Green component (0-255)
    /// - Parameter blue: Blue component (0-255)
    /// - Parameter alpha: Optional alpha component (0-1)
    /// - Returns: RGB or RGBA color string
    static func formatAsRGB(red: Int, green: Int, blue: Int, alpha: Double? = nil) -> String {
        if let alpha = alpha, alpha < 1.0 {
            return String(format: "rgba(%d, %d, %d, %.2f)", red, green, blue, alpha)
        }

        return String(format: "rgb(%d, %d, %d)", red, green, blue)
    }

    /// Parses multiple color formats from a list of strings
    /// - Parameter colorStrings: Array of color strings to parse
    /// - Returns: Array of successfully parsed colors
    static func parseMultiple(_ colorStrings: [String]) -> [ParsedColor] {
        return colorStrings.compactMap { parseColor($0) }
    }

    /// Batch-detects color format types for multiple strings
    /// - Parameter colorStrings: Array of color strings
    /// - Returns: Dictionary mapping strings to detected formats
    static func detectFormatsInBatch(_ colorStrings: [String]) -> [String: ColorFormatType] {
        var formats: [String: ColorFormatType] = [:]
        for colorString in colorStrings {
            formats[colorString] = detectFormat(colorString)
        }
        return formats
    }

    /// Attempts to parse a color with fallback chain
    /// - Parameters:
    ///   - primaryColor: The primary color string to parse
    ///   - fallbacks: Array of fallback color strings if primary fails
    /// - Returns: ParsedColor from first successful parse, or nil
    static func parseWithFallback(_ primaryColor: String, fallbacks: [String] = []) -> ParsedColor? {
        if let parsed = parseColor(primaryColor) {
            return parsed
        }

        for fallback in fallbacks {
            if let parsed = parseColor(fallback) {
                return parsed
            }
        }

        return nil
    }

    /// Extracts all color values from a string that might contain multiple formats
    /// - Parameter text: Text containing color specifications
    /// - Returns: Array of detected color strings and their formats
    static func extractColorReferences(_ text: String) -> [(string: String, format: ColorFormatType)] {
        var references: [(string: String, format: ColorFormatType)] = []

        // Hex pattern matching
        if let hexRegex = try? NSRegularExpression(pattern: hexPattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = hexRegex.matches(in: text, range: range)
            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let hexString = String(text[matchRange])
                    references.append((hexString, .hex))
                }
            }
        }

        // RGB/RGBA pattern matching
        if let rgbRegex = try? NSRegularExpression(pattern: rgbPattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = rgbRegex.matches(in: text, range: range)
            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let rgbString = String(text[matchRange])
                    let isRGBA = rgbString.lowercased().hasPrefix("rgba")
                    references.append((rgbString, isRGBA ? .rgba : .rgb))
                }
            }
        }

        return references
    }

    /// Validates color string format without full parsing
    /// - Parameter colorString: The color string to validate
    /// - Returns: True if the string appears to be a valid color format
    static func isValidColorFormat(_ colorString: String) -> Bool {
        let format = detectFormat(colorString)
        return format != .unknown && parseColor(colorString) != nil
    }

    /// Gets all supported color format descriptions
    /// - Returns: Dictionary of format types with their descriptions
    static func getFormatDescriptions() -> [ColorFormatType: String] {
        return [
            .hex: "Hexadecimal format (#RGB, #RRGGBB, #RGBA, #RRGGBBAA)",
            .rgb: "RGB functional notation: rgb(r, g, b)",
            .rgba: "RGBA functional notation: rgba(r, g, b, a)",
            .hsl: "HSL functional notation: hsl(h, s%, l%)",
            .hsla: "HSLA functional notation: hsla(h, s%, l%, a)",
            .cssVariable: "CSS custom property: var(--name) or var(--name, fallback)",
            .named: "Named color (red, blue, transparent, etc.)",
            .unknown: "Unknown or invalid color format"
        ]
    }

    /// Normalizes color component values to valid ranges
    /// - Parameters:
    ///   - red: Red component value
    ///   - green: Green component value
    ///   - blue: Blue component value
    ///   - alpha: Alpha component value
    /// - Returns: Tuple of normalized RGBA values
    static func normalizeRGBAComponents(red: Int, green: Int, blue: Int, alpha: Double) -> (r: Int, g: Int, b: Int, a: Double) {
        return (
            min(max(red, 0), 255),
            min(max(green, 0), 255),
            min(max(blue, 0), 255),
            min(max(alpha, 0.0), 1.0)
        )
    }

    /// Converts a color to an alternative format
    /// - Parameters:
    ///   - color: The parsed color to convert
    ///   - targetFormat: The target format to convert to
    /// - Returns: Formatted string in target format, or nil if conversion not possible
    static func convertToFormat(_ color: ParsedColor, targetFormat: ColorFormatType) -> String? {
        guard let rgb = getRGB(from: color) else { return nil }

        let alpha = color.alphaValue

        switch targetFormat {
        case .hex:
            return formatAsHex(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha == 1.0 ? nil : alpha)
        case .rgb, .rgba:
            return formatAsRGB(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha == 1.0 ? nil : alpha)
        case .cssVariable:
            return "var(--color)"
        case .hsl, .hsla:
            // Would require HSL conversion which is done in normalizer
            return nil
        case .named:
            return nil
        case .unknown:
            return nil
        }
    }

    private static func getRGB(from parsed: ParsedColor) -> (r: Int, g: Int, b: Int)? {
        if let r = parsed.red, let g = parsed.green, let b = parsed.blue {
            return (r, g, b)
        }
        return nil
    }
}
