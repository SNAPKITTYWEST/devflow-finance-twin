import Foundation

/// Represents a canonicalized color with multiple representations
struct CanonicalColor: Codable, Equatable {
    let hexValue: String
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double
    let hue: Double
    let saturation: Double
    let lightness: Double
    let originalFormat: ColorFormatType
    let originalString: String
    let isDark: Bool
    let isNeutral: Bool
    let isTransparent: Bool

    /// Unique identifier for this color based on its RGB and alpha values
    var colorIdentity: String {
        return "\(red)_\(green)_\(blue)_\(Int(alpha * 1000))"
    }

    /// Creates a deterministic hash for the color
    var colorHash: String {
        let combined = "\(red)|\(green)|\(blue)|\(alpha)"
        let data = combined.data(using: .utf8) ?? Data()
        let digest = self.simpleHash(data)
        return digest
    }

    private func simpleHash(_ data: Data) -> String {
        var hash: UInt32 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return String(format: "%08x", hash)
    }

    static func == (lhs: CanonicalColor, rhs: CanonicalColor) -> Bool {
        return lhs.red == rhs.red &&
               lhs.green == rhs.green &&
               lhs.blue == rhs.blue &&
               abs(lhs.alpha - rhs.alpha) < 0.001
    }
}

/// ColorNormalizer converts any color format to canonical representation
class ColorNormalizer {
    /// Normalizes a color string to its canonical form
    /// - Parameter colorString: The color string to normalize
    /// - Returns: CanonicalColor with all representations, or nil if parsing fails
    static func normalize(_ colorString: String) -> CanonicalColor? {
        guard let parsed = ColorFormat.parseColor(colorString) else {
            return nil
        }

        return canonicalizeFromParsed(parsed)
    }

    /// Converts a ParsedColor to its canonical representation
    /// - Parameter parsed: The ParsedColor to canonicalize
    /// - Returns: CanonicalColor with all representations
    private static func canonicalizeFromParsed(_ parsed: ParsedColor) -> CanonicalColor? {
        var red: Int
        var green: Int
        var blue: Int
        var alpha: Double

        // Convert to RGB if needed
        if let r = parsed.red, let g = parsed.green, let b = parsed.blue {
            red = r
            green = g
            blue = b
        } else if let h = parsed.hue, let s = parsed.saturation, let l = parsed.lightness {
            let rgb = hslToRGB(hue: h, saturation: s, lightness: l)
            red = rgb.r
            green = rgb.g
            blue = rgb.b
        } else {
            return nil
        }

        alpha = parsed.alphaValue

        // Validate components
        guard ColorFormat.validateRGBComponents(red: red, green: green, blue: blue, alpha: alpha) else {
            return nil
        }

        // Convert RGB to HSL
        let hsl = rgbToHSL(red: red, green: green, blue: blue)

        // Generate hex representation
        let hexValue = ColorFormat.formatAsHex(red: red, green: green, blue: blue, alpha: alpha == 1.0 ? nil : alpha)

        // Determine properties
        let isTransparent = alpha < 0.5
        let isDark = hsl.lightness < 50
        let isNeutral = hsl.saturation < 5 || (hsl.saturation < 15 && abs(hsl.lightness - 50) < 5)

        return CanonicalColor(
            hexValue: hexValue,
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            hue: hsl.hue,
            saturation: hsl.saturation,
            lightness: hsl.lightness,
            originalFormat: parsed.format,
            originalString: parsed.originalString,
            isDark: isDark,
            isNeutral: isNeutral,
            isTransparent: isTransparent
        )
    }

    /// Converts HSL to RGB color space
    /// - Parameters:
    ///   - hue: Hue (0-360)
    ///   - saturation: Saturation (0-100)
    ///   - lightness: Lightness (0-100)
    /// - Returns: Tuple with red, green, blue values (0-255)
    static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (r: Int, g: Int, b: Int) {
        let h = hue / 60.0
        let s = saturation / 100.0
        let l = lightness / 100.0

        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        var r: Double = 0
        var g: Double = 0
        var b: Double = 0

        switch h {
        case 0..<1:
            r = c
            g = x
            b = 0
        case 1..<2:
            r = x
            g = c
            b = 0
        case 2..<3:
            r = 0
            g = c
            b = x
        case 3..<4:
            r = 0
            g = x
            b = c
        case 4..<5:
            r = x
            g = 0
            b = c
        case 5..<6:
            r = c
            g = 0
            b = x
        default:
            r = 0
            g = 0
            b = 0
        }

        r += m
        g += m
        b += m

        return (
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }

    /// Converts RGB to HSL color space
    /// - Parameters:
    ///   - red: Red component (0-255)
    ///   - green: Green component (0-255)
    ///   - blue: Blue component (0-255)
    /// - Returns: Tuple with hue, saturation, lightness values
    static func rgbToHSL(red: Int, green: Int, blue: Int) -> (hue: Double, saturation: Double, lightness: Double) {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let b = Double(blue) / 255.0

        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let l = (max + min) / 2

        if max == min {
            return (0, 0, l * 100)
        }

        let d = max - min
        let s = l > 0.5 ? d / (2 - max - min) : d / (max + min)

        var h: Double
        switch max {
        case r:
            h = ((g - b) / d + (g < b ? 6 : 0)) / 6
        case g:
            h = ((b - r) / d + 2) / 6
        case b:
            h = ((r - g) / d + 4) / 6
        default:
            h = 0
        }

        return (h * 360, s * 100, l * 100)
    }

    /// Computes color equivalence by comparing RGB values with tolerance
    /// - Parameters:
    ///   - color1: First canonical color
    ///   - color2: Second canonical color
    ///   - tolerance: RGB difference tolerance (0-255), defaults to 5
    /// - Returns: True if colors are equivalent within tolerance
    static func areColorsEquivalent(_ color1: CanonicalColor, _ color2: CanonicalColor, tolerance: Int = 5) -> Bool {
        let redDiff = abs(color1.red - color2.red)
        let greenDiff = abs(color1.green - color2.green)
        let blueDiff = abs(color1.blue - color2.blue)
        let alphaDiff = abs(color1.alpha - color2.alpha)

        return redDiff <= tolerance && greenDiff <= tolerance && blueDiff <= tolerance && alphaDiff < 0.05
    }

    /// Computes perceptual color distance using Delta E CIE76
    /// - Parameters:
    ///   - color1: First canonical color
    ///   - color2: Second canonical color
    /// - Returns: Perceptual distance (0 = identical, ~100 = very different)
    static func computeColorDistance(_ color1: CanonicalColor, _ color2: CanonicalColor) -> Double {
        let lab1 = rgbToLab(r: color1.red, g: color1.green, b: color1.blue)
        let lab2 = rgbToLab(r: color2.red, g: color2.green, b: color2.blue)

        let dL = lab1.l - lab2.l
        let da = lab1.a - lab2.a
        let db = lab1.b - lab2.b

        return sqrt(dL * dL + da * da + db * db)
    }

    /// Converts RGB to LAB color space for perceptual distance calculation
    private static func rgbToLab(r: Int, g: Int, b: Int) -> (l: Double, a: Double, b: Double) {
        let red = Double(r) / 255.0
        let green = Double(g) / 255.0
        let blue = Double(b) / 255.0

        // Convert RGB to XYZ
        let rLinear = red > 0.04045 ? pow((red + 0.055) / 1.055, 2.4) : red / 12.92
        let gLinear = green > 0.04045 ? pow((green + 0.055) / 1.055, 2.4) : green / 12.92
        let bLinear = blue > 0.04045 ? pow((blue + 0.055) / 1.055, 2.4) : blue / 12.92

        let x = (rLinear * 0.4124 + gLinear * 0.3576 + bLinear * 0.1805) / 0.95047
        let y = (rLinear * 0.2126 + gLinear * 0.7152 + bLinear * 0.0722) / 1.00000
        let z = (rLinear * 0.0193 + gLinear * 0.1192 + bLinear * 0.9505) / 1.08883

        // Convert XYZ to LAB
        let fx = x > 0.008856 ? pow(x, 1.0 / 3.0) : (7.787 * x) + (16.0 / 116.0)
        let fy = y > 0.008856 ? pow(y, 1.0 / 3.0) : (7.787 * y) + (16.0 / 116.0)
        let fz = z > 0.008856 ? pow(z, 1.0 / 3.0) : (7.787 * z) + (16.0 / 116.0)

        let l = (116 * fy) - 16
        let a = 500 * (fx - fy)
        let bValue = 200 * (fy - fz)

        return (l, a, bValue)
    }

    /// Validates that a canonical color representation is valid
    /// - Parameter color: The color to validate
    /// - Returns: True if canonical color is valid
    static func isValidCanonical(_ color: CanonicalColor) -> Bool {
        guard ColorFormat.validateRGBComponents(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        ) else {
            return false
        }

        guard ColorFormat.validateHSLComponents(
            hue: color.hue,
            saturation: color.saturation,
            lightness: color.lightness,
            alpha: color.alpha
        ) else {
            return false
        }

        return true
    }

    /// Generates alternate representations of a color
    /// - Parameter color: The canonical color
    /// - Returns: Dictionary with format types as keys and formatted strings as values
    static func generateAlternateRepresentations(_ color: CanonicalColor) -> [ColorFormatType: String] {
        var representations: [ColorFormatType: String] = [:]

        // Hex representation
        representations[.hex] = color.hexValue

        // RGB/RGBA representation
        representations[color.alpha < 1.0 ? .rgba : .rgb] = ColorFormat.formatAsRGB(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha < 1.0 ? color.alpha : nil
        )

        // HSL/HSLA representation
        let hslString: String
        if color.alpha < 1.0 {
            hslString = String(format: "hsla(%.0f, %.1f%%, %.1f%%, %.2f)",
                              color.hue, color.saturation, color.lightness, color.alpha)
        } else {
            hslString = String(format: "hsl(%.0f, %.1f%%, %.1f%%)",
                              color.hue, color.saturation, color.lightness)
        }
        representations[color.alpha < 1.0 ? .hsla : .hsl] = hslString

        return representations
    }

    /// Deterministically normalizes a color ensuring consistent results
    /// - Parameter colorString: The color to normalize
    /// - Returns: Normalized canonical color with deterministic properties
    static func normalizeDeterministic(_ colorString: String) -> CanonicalColor? {
        guard var canonical = normalize(colorString) else {
            return nil
        }

        // Round HSL values for determinism
        var rounded = canonical
        rounded.hue = (rounded.hue * 10).rounded() / 10
        rounded.saturation = (rounded.saturation * 10).rounded() / 10
        rounded.lightness = (rounded.lightness * 10).rounded() / 10

        return rounded
    }

    /// Builds a canonical color identity for deduplication
    /// - Parameter color: The canonical color
    /// - Returns: Unique string identifier for the color
    static func buildColorIdentity(_ color: CanonicalColor) -> String {
        return color.colorIdentity
    }

    /// Creates a color from HSL values with alpha
    /// - Parameters:
    ///   - hue: Hue (0-360)
    ///   - saturation: Saturation (0-100)
    ///   - lightness: Lightness (0-100)
    ///   - alpha: Alpha (0-1)
    /// - Returns: CanonicalColor or nil if invalid
    static func createFromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1.0) -> CanonicalColor? {
        guard ColorFormat.validateHSLComponents(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha) else {
            return nil
        }

        let rgb = hslToRGB(hue: hue, saturation: saturation, lightness: lightness)

        let isTransparent = alpha < 0.5
        let isDark = lightness < 50
        let isNeutral = saturation < 5 || (saturation < 15 && abs(lightness - 50) < 5)

        let hexValue = ColorFormat.formatAsHex(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha == 1.0 ? nil : alpha)

        return CanonicalColor(
            hexValue: hexValue,
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
            alpha: alpha,
            hue: hue,
            saturation: saturation,
            lightness: lightness,
            originalFormat: .hsl,
            originalString: String(format: "hsl(%.0f, %.1f%%, %.1f%%)", hue, saturation, lightness),
            isDark: isDark,
            isNeutral: isNeutral,
            isTransparent: isTransparent
        )
    }

    /// Creates a color from RGB values with alpha
    /// - Parameters:
    ///   - red: Red (0-255)
    ///   - green: Green (0-255)
    ///   - blue: Blue (0-255)
    ///   - alpha: Alpha (0-1)
    /// - Returns: CanonicalColor or nil if invalid
    static func createFromRGB(red: Int, green: Int, blue: Int, alpha: Double = 1.0) -> CanonicalColor? {
        guard ColorFormat.validateRGBComponents(red: red, green: green, blue: blue, alpha: alpha) else {
            return nil
        }

        let hsl = rgbToHSL(red: red, green: green, blue: blue)

        let isTransparent = alpha < 0.5
        let isDark = hsl.lightness < 50
        let isNeutral = hsl.saturation < 5 || (hsl.saturation < 15 && abs(hsl.lightness - 50) < 5)

        let hexValue = ColorFormat.formatAsHex(red: red, green: green, blue: blue, alpha: alpha == 1.0 ? nil : alpha)

        return CanonicalColor(
            hexValue: hexValue,
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            hue: hsl.hue,
            saturation: hsl.saturation,
            lightness: hsl.lightness,
            originalFormat: .rgb,
            originalString: String(format: "rgb(%d, %d, %d)", red, green, blue),
            isDark: isDark,
            isNeutral: isNeutral,
            isTransparent: isTransparent
        )
    }

    /// Creates a color from hexadecimal value
    /// - Parameters:
    ///   - hex: Hex string (with or without #)
    ///   - alpha: Optional alpha (0-1)
    /// - Returns: CanonicalColor or nil if invalid
    static func createFromHex(_ hex: String, alpha: Double? = nil) -> CanonicalColor? {
        let colorString = alpha != nil && alpha! < 1.0 ? "\(hex)\(String(format: "%02X", Int((alpha ?? 1.0) * 255)))" : hex
        return normalize(colorString)
    }

    /// Normalizes multiple colors in batch
    /// - Parameter colorStrings: Array of color strings to normalize
    /// - Returns: Array of successfully normalized canonical colors
    static func normalizeBatch(_ colorStrings: [String]) -> [CanonicalColor] {
        return colorStrings.compactMap { normalize($0) }
    }

    /// Deduplicates colors in a collection based on equivalence
    /// - Parameters:
    ///   - colors: Array of canonical colors
    ///   - tolerance: RGB difference tolerance (0-255)
    /// - Returns: Deduplicated array with unique colors
    static func deduplicateColors(_ colors: [CanonicalColor], tolerance: Int = 5) -> [CanonicalColor] {
        var deduplicated: [CanonicalColor] = []

        for color in colors {
            if !deduplicated.contains(where: { areColorsEquivalent($0, color, tolerance: tolerance) }) {
                deduplicated.append(color)
            }
        }

        return deduplicated
    }

    /// Groups colors by identity for provenance tracking
    /// - Parameter colors: Array of canonical colors
    /// - Returns: Dictionary mapping color identities to arrays of colors with that identity
    static func groupByIdentity(_ colors: [CanonicalColor]) -> [String: [CanonicalColor]] {
        var groups: [String: [CanonicalColor]] = [:]

        for color in colors {
            let identity = color.colorIdentity
            if groups[identity] == nil {
                groups[identity] = []
            }
            groups[identity]?.append(color)
        }

        return groups
    }

    /// Finds nearest color match from candidates
    /// - Parameters:
    ///   - targetColor: The color to match
    ///   - candidates: Array of candidate colors to search
    /// - Returns: The nearest matching color and its distance
    static func findNearestMatch(_ targetColor: CanonicalColor, in candidates: [CanonicalColor]) -> (color: CanonicalColor, distance: Double)? {
        guard !candidates.isEmpty else { return nil }

        var nearest = candidates[0]
        var minDistance = computeColorDistance(targetColor, nearest)

        for candidate in candidates.dropFirst() {
            let distance = computeColorDistance(targetColor, candidate)
            if distance < minDistance {
                minDistance = distance
                nearest = candidate
            }
        }

        return (nearest, minDistance)
    }

    /// Finds all colors within a maximum distance threshold
    /// - Parameters:
    ///   - targetColor: The reference color
    ///   - colors: Array of colors to search
    ///   - maxDistance: Maximum perceptual distance threshold
    /// - Returns: Array of colors within threshold, sorted by distance
    static func findColorsWithinDistance(_ targetColor: CanonicalColor, in colors: [CanonicalColor], maxDistance: Double = 30.0) -> [(color: CanonicalColor, distance: Double)] {
        var results: [(color: CanonicalColor, distance: Double)] = []

        for color in colors {
            let distance = computeColorDistance(targetColor, color)
            if distance <= maxDistance {
                results.append((color, distance))
            }
        }

        return results.sorted { $0.distance < $1.distance }
    }

    /// Creates a palette of derivative colors (lighter, darker, saturated variants)
    /// - Parameter baseColor: The base color to derive from
    /// - Returns: Dictionary with color variants
    static func createColorPalette(from baseColor: CanonicalColor) -> [String: CanonicalColor] {
        var palette: [String: CanonicalColor] = [:]

        palette["base"] = baseColor

        // Lighter variant
        if let lighter = createFromHSL(
            hue: baseColor.hue,
            saturation: baseColor.saturation,
            lightness: min(baseColor.lightness + 20, 95)
        ) {
            palette["lighter"] = lighter
        }

        // Darker variant
        if let darker = createFromHSL(
            hue: baseColor.hue,
            saturation: baseColor.saturation,
            lightness: max(baseColor.lightness - 20, 5)
        ) {
            palette["darker"] = darker
        }

        // More saturated variant
        if let saturated = createFromHSL(
            hue: baseColor.hue,
            saturation: min(baseColor.saturation + 30, 100),
            lightness: baseColor.lightness
        ) {
            palette["saturated"] = saturated
        }

        // Less saturated variant
        if let desaturated = createFromHSL(
            hue: baseColor.hue,
            saturation: max(baseColor.saturation - 30, 0),
            lightness: baseColor.lightness
        ) {
            palette["desaturated"] = desaturated
        }

        // Complementary color (hue + 180)
        let complementaryHue = (baseColor.hue + 180).truncatingRemainder(dividingBy: 360)
        if let complementary = createFromHSL(
            hue: complementaryHue,
            saturation: baseColor.saturation,
            lightness: baseColor.lightness
        ) {
            palette["complementary"] = complementary
        }

        return palette
    }

    /// Adjusts brightness of a color
    /// - Parameters:
    ///   - color: The base color
    ///   - factor: Brightness adjustment factor (-1.0 to 1.0, where 0 is unchanged)
    /// - Returns: Adjusted color or nil if invalid
    static func adjustBrightness(_ color: CanonicalColor, by factor: Double) -> CanonicalColor? {
        let newLightness = color.lightness + (factor * 50)
        return createFromHSL(
            hue: color.hue,
            saturation: color.saturation,
            lightness: newLightness,
            alpha: color.alpha
        )
    }

    /// Adjusts saturation of a color
    /// - Parameters:
    ///   - color: The base color
    ///   - factor: Saturation adjustment factor (-1.0 to 1.0, where 0 is unchanged)
    /// - Returns: Adjusted color or nil if invalid
    static func adjustSaturation(_ color: CanonicalColor, by factor: Double) -> CanonicalColor? {
        let newSaturation = color.saturation + (factor * 50)
        return createFromHSL(
            hue: color.hue,
            saturation: newSaturation,
            lightness: color.lightness,
            alpha: color.alpha
        )
    }

    /// Rotates hue of a color
    /// - Parameters:
    ///   - color: The base color
    ///   - degrees: Hue rotation in degrees
    /// - Returns: Color with rotated hue
    static func rotateHue(_ color: CanonicalColor, by degrees: Double) -> CanonicalColor? {
        let newHue = (color.hue + degrees).truncatingRemainder(dividingBy: 360)
        return createFromHSL(
            hue: newHue,
            saturation: color.saturation,
            lightness: color.lightness,
            alpha: color.alpha
        )
    }

    /// Blends two colors together
    /// - Parameters:
    ///   - color1: First color
    ///   - color2: Second color
    ///   - ratio: Blend ratio (0 = color1, 1 = color2)
    /// - Returns: Blended color
    static func blendColors(_ color1: CanonicalColor, _ color2: CanonicalColor, ratio: Double) -> CanonicalColor? {
        let t = max(0, min(1, ratio))

        let blendedRed = Int(Double(color1.red) * (1 - t) + Double(color2.red) * t)
        let blendedGreen = Int(Double(color1.green) * (1 - t) + Double(color2.green) * t)
        let blendedBlue = Int(Double(color1.blue) * (1 - t) + Double(color2.blue) * t)
        let blendedAlpha = color1.alpha * (1 - t) + color2.alpha * t

        return createFromRGB(
            red: blendedRed,
            green: blendedGreen,
            blue: blendedBlue,
            alpha: blendedAlpha
        )
    }

    /// Calculates the average color of multiple colors
    /// - Parameter colors: Array of canonical colors
    /// - Returns: Average color or nil if empty
    static func averageColor(of colors: [CanonicalColor]) -> CanonicalColor? {
        guard !colors.isEmpty else { return nil }

        let avgRed = colors.reduce(0) { $0 + $1.red } / colors.count
        let avgGreen = colors.reduce(0) { $0 + $1.green } / colors.count
        let avgBlue = colors.reduce(0) { $0 + $1.blue } / colors.count
        let avgAlpha = colors.reduce(0.0) { $0 + $1.alpha } / Double(colors.count)

        return createFromRGB(
            red: avgRed,
            green: avgGreen,
            blue: avgBlue,
            alpha: avgAlpha
        )
    }

    /// Inverts (negates) a color
    /// - Parameter color: The color to invert
    /// - Returns: Inverted color
    static func invertColor(_ color: CanonicalColor) -> CanonicalColor? {
        return createFromRGB(
            red: 255 - color.red,
            green: 255 - color.green,
            blue: 255 - color.blue,
            alpha: color.alpha
        )
    }

    /// Desaturates a color to grayscale
    /// - Parameters:
    ///   - color: The color to desaturate
    ///   - amount: Desaturation amount (0.0 = no change, 1.0 = fully grayscale)
    /// - Returns: Desaturated color
    static func desaturate(_ color: CanonicalColor, by amount: Double) -> CanonicalColor? {
        let newSaturation = color.saturation * (1.0 - max(0, min(1, amount)))
        return createFromHSL(
            hue: color.hue,
            saturation: newSaturation,
            lightness: color.lightness,
            alpha: color.alpha
        )
    }

    /// Serializes a canonical color to JSON
    /// - Parameter color: The color to serialize
    /// - Returns: JSON string representation
    static func serializeToJSON(_ color: CanonicalColor) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let jsonData = try? encoder.encode(color),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return nil
    }

    /// Deserializes a canonical color from JSON
    /// - Parameter jsonString: JSON string to deserialize
    /// - Returns: Parsed canonical color or nil
    static func deserializeFromJSON(_ jsonString: String) -> CanonicalColor? {
        let decoder = JSONDecoder()

        if let jsonData = jsonString.data(using: .utf8),
           let color = try? decoder.decode(CanonicalColor.self, from: jsonData) {
            return color
        }

        return nil
    }
}
