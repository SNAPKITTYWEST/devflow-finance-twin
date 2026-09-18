import Foundation

/// Color semantic family classification
enum SemanticColorFamily: String, Codable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case magenta
    case neutral
    case unknown
}

/// Represents color properties and classifications
struct ColorProperties: Codable {
    let hueFamily: SemanticColorFamily
    let hueRange: (min: Double, max: Double)
    let saturationLevel: String // "muted", "desaturated", "saturated", "vivid"
    let lightnessLevel: String // "dark", "gray", "light", "bright"
    let vibrance: Double // 0-1
    let contrast: Double // contrast ratio against white (1.0 = white)
    let temperature: String // "warm", "cool", "neutral"
    let brightness: Double // 0-1
    let isNeutral: Bool
    let isPastel: Bool
    let isAccent: Bool
    let similarity: [ColorSimilarity]
}

/// Represents similarity to another color
struct ColorSimilarity: Codable {
    let targetColor: String
    let distance: Double
    let similarity: Double // 0-1
}

/// Represents color taxonomy classification
struct ColorTaxonomy: Codable {
    let family: SemanticColorFamily
    let saturationBucket: String
    let lightnessBucket: String
    let temperatureBucket: String
    let perceptualBucket: String
    let contrastBucket: String
}

/// ColorClassifier analyzes and classifies normalized colors
class ColorClassifier {
    /// Classifies a normalized color by its properties
    /// - Parameter color: The canonical color to classify
    /// - Returns: ColorProperties with comprehensive classification
    static func classifyColor(_ color: CanonicalColor) -> ColorProperties {
        let hueFamily = classifyHueFamily(hue: color.hue)
        let hueRange = getHueRange(for: hueFamily)
        let saturationLevel = classifySaturation(color.saturation)
        let lightnessLevel = classifyLightness(color.lightness)
        let vibrance = computeVibrance(saturation: color.saturation, lightness: color.lightness)
        let contrast = computeContrast(red: color.red, green: color.green, blue: color.blue)
        let temperature = classifyTemperature(hue: color.hue)
        let brightness = computeBrightness(red: color.red, green: color.green, blue: color.blue)
        let isPastel = color.saturation < 50 && color.lightness > 70
        let isAccent = color.saturation > 60 && color.lightness > 30 && color.lightness < 80

        return ColorProperties(
            hueFamily: hueFamily,
            hueRange: hueRange,
            saturationLevel: saturationLevel,
            lightnessLevel: lightnessLevel,
            vibrance: vibrance,
            contrast: contrast,
            temperature: temperature,
            brightness: brightness,
            isNeutral: color.isNeutral,
            isPastel: isPastel,
            isAccent: isAccent,
            similarity: []
        )
    }

    /// Identifies if a color is a neutral gray
    /// - Parameter color: The canonical color to check
    /// - Returns: True if color is a neutral gray
    static func isNeutralGray(_ color: CanonicalColor) -> Bool {
        // Neutral grays have very low saturation and roughly equal RGB values
        return color.saturation < 10 && isRGBBalanced(r: color.red, g: color.green, b: color.blue)
    }

    /// Identifies if a color is an accent color
    /// - Parameter color: The canonical color to check
    /// - Returns: True if color is suitable as an accent
    static func isAccentColor(_ color: CanonicalColor) -> Bool {
        // Accent colors are highly saturated and have good contrast
        return color.saturation > 60 && color.lightness > 30 && color.lightness < 80 && !color.isTransparent
    }

    /// Detects similar colors within a distance threshold
    /// - Parameters:
    ///   - sourceColor: The color to match against
    ///   - candidates: Array of candidate colors to search
    ///   - distanceThreshold: Maximum perceptual distance (0-100), defaults to 15
    /// - Returns: Array of similar colors sorted by similarity
    static func detectSimilarColors(_ sourceColor: CanonicalColor, in candidates: [CanonicalColor], distanceThreshold: Double = 15.0) -> [ColorSimilarity] {
        var similarities: [ColorSimilarity] = []

        for candidate in candidates {
            let distance = ColorNormalizer.computeColorDistance(sourceColor, candidate)

            if distance <= distanceThreshold {
                let similarity = max(0.0, 1.0 - (distance / distanceThreshold))
                similarities.append(ColorSimilarity(
                    targetColor: candidate.hexValue,
                    distance: distance,
                    similarity: similarity
                ))
            }
        }

        return similarities.sorted { $0.distance < $1.distance }
    }

    /// Builds the complete color taxonomy for a color
    /// - Parameter color: The canonical color to classify
    /// - Returns: ColorTaxonomy with all classifications
    static func buildColorTaxonomy(_ color: CanonicalColor) -> ColorTaxonomy {
        let family = classifyHueFamily(hue: color.hue)
        let saturationBucket = classifySaturationBucket(color.saturation)
        let lightnessBucket = classifyLightnessBucket(color.lightness)
        let temperatureBucket = classifyTemperatureBucket(hue: color.hue)
        let perceptualBucket = classifyPerceptualBucket(hue: color.hue, saturation: color.saturation, lightness: color.lightness)
        let contrastBucket = classifyContrastBucket(red: color.red, green: color.green, blue: color.blue)

        return ColorTaxonomy(
            family: family,
            saturationBucket: saturationBucket,
            lightnessBucket: lightnessBucket,
            temperatureBucket: temperatureBucket,
            perceptualBucket: perceptualBucket,
            contrastBucket: contrastBucket
        )
    }

    /// Scores various color properties
    /// - Parameter color: The canonical color to score
    /// - Returns: Dictionary of property names to scores (0-1)
    static func scoreColorProperties(_ color: CanonicalColor) -> [String: Double] {
        var scores: [String: Double] = [:]

        // Vibrance score
        scores["vibrance"] = computeVibrance(saturation: color.saturation, lightness: color.lightness)

        // Contrast score (against white background)
        scores["contrast"] = computeContrast(red: color.red, green: color.green, blue: color.blue)

        // Saturation score
        scores["saturation"] = color.saturation / 100.0

        // Lightness score
        scores["lightness"] = color.lightness / 100.0

        // Brightness score
        scores["brightness"] = computeBrightness(red: color.red, green: color.green, blue: color.blue)

        // Accessibility score (good contrast potential)
        scores["accessibility"] = computeAccessibilityScore(color: color)

        // Purity score (how pure the hue is)
        scores["purity"] = min(color.saturation / 100.0, 1.0)

        // Warmth score
        scores["warmth"] = computeWarmthScore(hue: color.hue)

        return scores
    }

    // MARK: - Private Classification Methods

    private static func classifyHueFamily(hue: Double) -> SemanticColorFamily {
        let normalizedHue = hue.truncatingRemainder(dividingBy: 360)

        if normalizedHue >= 330 || normalizedHue < 15 {
            return .red
        } else if normalizedHue >= 15 && normalizedHue < 45 {
            return .orange
        } else if normalizedHue >= 45 && normalizedHue < 65 {
            return .yellow
        } else if normalizedHue >= 65 && normalizedHue < 165 {
            return .green
        } else if normalizedHue >= 165 && normalizedHue < 255 {
            return .cyan
        } else if normalizedHue >= 255 && normalizedHue < 270 {
            return .blue
        } else if normalizedHue >= 270 && normalizedHue < 300 {
            return .purple
        } else if normalizedHue >= 300 && normalizedHue < 330 {
            return .magenta
        }

        return .unknown
    }

    private static func getHueRange(for family: SemanticColorFamily) -> (min: Double, max: Double) {
        switch family {
        case .red:
            return (330, 15)
        case .orange:
            return (15, 45)
        case .yellow:
            return (45, 65)
        case .green:
            return (65, 165)
        case .cyan:
            return (165, 255)
        case .blue:
            return (255, 270)
        case .purple:
            return (270, 300)
        case .magenta:
            return (300, 330)
        case .neutral, .unknown:
            return (0, 360)
        }
    }

    private static func classifySaturation(_ saturation: Double) -> String {
        if saturation < 15 {
            return "muted"
        } else if saturation < 40 {
            return "desaturated"
        } else if saturation < 75 {
            return "saturated"
        } else {
            return "vivid"
        }
    }

    private static func classifyLightness(_ lightness: Double) -> String {
        if lightness < 20 {
            return "dark"
        } else if lightness < 40 {
            return "dark-gray"
        } else if lightness < 60 {
            return "gray"
        } else if lightness < 80 {
            return "light"
        } else {
            return "bright"
        }
    }

    private static func computeVibrance(saturation: Double, lightness: Double) -> Double {
        // Vibrance combines saturation and optimal lightness (around 50%)
        let saturationComponent = saturation / 100.0
        let lightnessComponent = 1.0 - abs(lightness - 50.0) / 50.0
        return (saturationComponent + lightnessComponent) / 2.0
    }

    private static func computeContrast(red: Int, green: Int, blue: Int) -> Double {
        // Compute relative luminance for contrast ratio against white
        let luminance = computeRelativeLuminance(red: red, green: green, blue: blue)
        let whiteRelativeLuminance = 1.0

        // Contrast ratio formula
        let lighterLuminance = max(luminance, whiteRelativeLuminance)
        let darkerLuminance = min(luminance, whiteRelativeLuminance)

        let contrastRatio = (lighterLuminance + 0.05) / (darkerLuminance + 0.05)

        // Normalize to 0-1
        return min(contrastRatio / 21.0, 1.0)
    }

    private static func computeRelativeLuminance(red: Int, green: Int, blue: Int) -> Double {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let b = Double(blue) / 255.0

        let rLinear = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4)
        let gLinear = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4)
        let bLinear = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4)

        return 0.2126 * rLinear + 0.7152 * gLinear + 0.0722 * bLinear
    }

    private static func classifyTemperature(hue: Double) -> String {
        let normalizedHue = hue.truncatingRemainder(dividingBy: 360)

        if normalizedHue < 60 || normalizedHue >= 240 {
            return "cool"
        } else if normalizedHue >= 60 && normalizedHue < 240 {
            return "warm"
        }

        return "neutral"
    }

    private static func computeBrightness(red: Int, green: Int, blue: Int) -> Double {
        return computeRelativeLuminance(red: red, green: green, blue: blue)
    }

    private static func isRGBBalanced(r: Int, g: Int, b: Int, tolerance: Int = 10) -> Bool {
        let maxComponent = max(r, g, b)
        let minComponent = min(r, g, b)
        return maxComponent - minComponent <= tolerance
    }

    private static func classifySaturationBucket(_ saturation: Double) -> String {
        if saturation < 10 {
            return "grayscale"
        } else if saturation < 30 {
            return "low"
        } else if saturation < 60 {
            return "medium"
        } else if saturation < 80 {
            return "high"
        } else {
            return "maximum"
        }
    }

    private static func classifyLightnessBucket(_ lightness: Double) -> String {
        if lightness < 25 {
            return "very-dark"
        } else if lightness < 40 {
            return "dark"
        } else if lightness < 60 {
            return "mid"
        } else if lightness < 75 {
            return "light"
        } else {
            return "very-light"
        }
    }

    private static func classifyTemperatureBucket(hue: Double) -> String {
        let normalizedHue = hue.truncatingRemainder(dividingBy: 360)

        if normalizedHue >= 0 && normalizedHue < 60 {
            return "warm-red"
        } else if normalizedHue >= 60 && normalizedHue < 120 {
            return "warm-yellow"
        } else if normalizedHue >= 120 && normalizedHue < 180 {
            return "cool-green"
        } else if normalizedHue >= 180 && normalizedHue < 240 {
            return "cool-cyan"
        } else if normalizedHue >= 240 && normalizedHue < 300 {
            return "cool-blue"
        } else {
            return "warm-magenta"
        }
    }

    private static func classifyPerceptualBucket(hue: Double, saturation: Double, lightness: Double) -> String {
        if saturation < 10 {
            if lightness < 25 {
                return "deep-gray"
            } else if lightness < 75 {
                return "medium-gray"
            } else {
                return "light-gray"
            }
        }

        let family = classifyHueFamily(hue: hue)
        let satLevel = classifySaturation(saturation)
        let lightLevel = classifyLightness(lightness)

        return "\(family.rawValue)-\(satLevel)-\(lightLevel)"
    }

    private static func classifyContrastBucket(red: Int, green: Int, blue: Int) -> String {
        let luminance = computeRelativeLuminance(red: red, green: green, blue: blue)

        if luminance < 0.2 {
            return "very-dark"
        } else if luminance < 0.4 {
            return "dark"
        } else if luminance < 0.6 {
            return "medium"
        } else if luminance < 0.8 {
            return "light"
        } else {
            return "very-light"
        }
    }

    private static func computeAccessibilityScore(color: CanonicalColor) -> Double {
        // Score based on contrast ratio potential and distinctiveness
        let contrastAgainstWhite = computeContrast(red: color.red, green: color.green, blue: color.blue)
        let contrastAgainstBlack = computeContrastAgainstBlack(red: color.red, green: color.green, blue: color.blue)

        let maxContrast = max(contrastAgainstWhite, contrastAgainstBlack)

        // WCAG AAA requires 7:1, AA requires 4.5:1
        // Normalize to 0-1 based on AA standard
        return min(maxContrast * 0.22, 1.0) // 4.5 * 0.22 ≈ 1.0
    }

    private static func computeContrastAgainstBlack(red: Int, green: Int, blue: Int) -> Double {
        let luminance = computeRelativeLuminance(red: red, green: green, blue: blue)
        let blackRelativeLuminance = 0.0

        let lighterLuminance = max(luminance, blackRelativeLuminance)
        let darkerLuminance = min(luminance, blackRelativeLuminance)

        let contrastRatio = (lighterLuminance + 0.05) / (darkerLuminance + 0.05)
        return min(contrastRatio / 21.0, 1.0)
    }

    private static func computeWarmthScore(hue: Double) -> Double {
        let normalizedHue = hue.truncatingRemainder(dividingBy: 360)

        // Warm colors are in the 0-60 and 300-360 range
        if normalizedHue < 60 || normalizedHue >= 300 {
            return 1.0 - (min(normalizedHue, 60) / 60.0) * 0.5
        } else if normalizedHue >= 60 && normalizedHue < 180 {
            return 0.5 - ((normalizedHue - 60) / 120.0) * 0.5
        } else {
            return 0.0 + ((normalizedHue - 180) / 120.0) * 0.5
        }
    }

    /// Compares two colors and returns a comprehensive similarity assessment
    /// - Parameters:
    ///   - color1: First color to compare
    ///   - color2: Second color to compare
    /// - Returns: Dictionary with various similarity metrics
    static func compareSimilarity(_ color1: CanonicalColor, _ color2: CanonicalColor) -> [String: Any] {
        var comparison: [String: Any] = [:]

        // Perceptual distance
        comparison["perceptual_distance"] = ColorNormalizer.computeColorDistance(color1, color2)

        // RGB difference
        let rgbDistance = sqrt(
            Double((color1.red - color2.red) * (color1.red - color2.red)) +
            Double((color1.green - color2.green) * (color1.green - color2.green)) +
            Double((color1.blue - color2.blue) * (color1.blue - color2.blue))
        )
        comparison["rgb_distance"] = rgbDistance

        // Hue similarity (0-1)
        let hueDiff = min(abs(color1.hue - color2.hue), 360 - abs(color1.hue - color2.hue))
        comparison["hue_similarity"] = 1.0 - (hueDiff / 180.0)

        // Saturation similarity
        comparison["saturation_similarity"] = 1.0 - (abs(color1.saturation - color2.saturation) / 100.0)

        // Lightness similarity
        comparison["lightness_similarity"] = 1.0 - (abs(color1.lightness - color2.lightness) / 100.0)

        // Same hue family
        comparison["same_hue_family"] = classifyHueFamily(hue: color1.hue) == classifyHueFamily(hue: color2.hue)

        // Same saturation bucket
        comparison["same_saturation_bucket"] = classifySaturationBucket(color1.saturation) == classifySaturationBucket(color2.saturation)

        return comparison
    }

    /// Computes color harmony with other colors (complementary, analogous, triadic)
    /// - Parameters:
    ///   - baseColor: The base color for harmony calculation
    ///   - scheme: Harmony scheme type ("complementary", "analogous", "triadic", "tetradic")
    /// - Returns: Array of harmonious colors
    static func computeColorHarmony(_ baseColor: CanonicalColor, scheme: String = "complementary") -> [CanonicalColor] {
        var harmonies: [CanonicalColor] = [baseColor]

        switch scheme {
        case "complementary":
            let complementaryHue = (baseColor.hue + 180).truncatingRemainder(dividingBy: 360)
            if let complementary = ColorNormalizer.createFromHSL(
                hue: complementaryHue,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(complementary)
            }

        case "analogous":
            let hue1 = (baseColor.hue - 30).truncatingRemainder(dividingBy: 360)
            let hue2 = (baseColor.hue + 30).truncatingRemainder(dividingBy: 360)

            if let color1 = ColorNormalizer.createFromHSL(
                hue: hue1,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color1)
            }

            if let color2 = ColorNormalizer.createFromHSL(
                hue: hue2,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color2)
            }

        case "triadic":
            let hue1 = (baseColor.hue + 120).truncatingRemainder(dividingBy: 360)
            let hue2 = (baseColor.hue + 240).truncatingRemainder(dividingBy: 360)

            if let color1 = ColorNormalizer.createFromHSL(
                hue: hue1,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color1)
            }

            if let color2 = ColorNormalizer.createFromHSL(
                hue: hue2,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color2)
            }

        case "tetradic":
            let hue1 = (baseColor.hue + 90).truncatingRemainder(dividingBy: 360)
            let hue2 = (baseColor.hue + 180).truncatingRemainder(dividingBy: 360)
            let hue3 = (baseColor.hue + 270).truncatingRemainder(dividingBy: 360)

            if let color1 = ColorNormalizer.createFromHSL(
                hue: hue1,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color1)
            }

            if let color2 = ColorNormalizer.createFromHSL(
                hue: hue2,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color2)
            }

            if let color3 = ColorNormalizer.createFromHSL(
                hue: hue3,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                harmonies.append(color3)
            }

        default:
            break
        }

        return harmonies
    }

    /// Classifies colors in bulk
    /// - Parameter colors: Array of canonical colors to classify
    /// - Returns: Array of color properties for each input color
    static func classifyBatch(_ colors: [CanonicalColor]) -> [ColorProperties] {
        return colors.map { classifyColor($0) }
    }

    /// Scores colors against WCAG accessibility standards
    /// - Parameters:
    ///   - color: The color to score
    ///   - backgroundColor: The background color (defaults to white)
    /// - Returns: Dictionary with accessibility scores and compliance levels
    static func scoreAccessibility(_ color: CanonicalColor, against backgroundColor: CanonicalColor? = nil) -> [String: Any] {
        let bgColor = backgroundColor ?? ColorNormalizer.createFromRGB(red: 255, green: 255, blue: 255)!

        var scores: [String: Any] = [:]

        // Compute luminance contrast
        let colorLuminance = computeRelativeLuminance(red: color.red, green: color.green, blue: color.blue)
        let bgLuminance = computeRelativeLuminance(red: bgColor.red, green: bgColor.green, blue: bgColor.blue)

        let lighter = max(colorLuminance, bgLuminance)
        let darker = min(colorLuminance, bgLuminance)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)

        scores["contrast_ratio"] = contrastRatio
        scores["wcag_aa_normal"] = contrastRatio >= 4.5
        scores["wcag_aa_large"] = contrastRatio >= 3.0
        scores["wcag_aaa_normal"] = contrastRatio >= 7.0
        scores["wcag_aaa_large"] = contrastRatio >= 4.5

        return scores
    }

    /// Detects if two colors have sufficient contrast for readability
    /// - Parameters:
    ///   - foreground: Foreground color
    ///   - background: Background color
    ///   - level: Accessibility level ("AA" or "AAA")
    /// - Returns: True if contrast is sufficient
    static func hasAdequateContrast(_ foreground: CanonicalColor, on background: CanonicalColor, level: String = "AA") -> Bool {
        let fgLuminance = computeRelativeLuminance(red: foreground.red, green: foreground.green, blue: foreground.blue)
        let bgLuminance = computeRelativeLuminance(red: background.red, green: background.green, blue: background.blue)

        let lighter = max(fgLuminance, bgLuminance)
        let darker = min(fgLuminance, bgLuminance)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)

        switch level {
        case "AAA":
            return contrastRatio >= 7.0
        case "AA":
            return contrastRatio >= 4.5
        default:
            return contrastRatio >= 3.0
        }
    }

    /// Generates a color palette with good harmony and contrast
    /// - Parameters:
    ///   - baseColor: The base color
    ///   - size: Number of colors to generate
    /// - Returns: Array of harmonious colors
    static func generateHarmoniousPalette(_ baseColor: CanonicalColor, size: Int = 5) -> [CanonicalColor] {
        var palette: [CanonicalColor] = [baseColor]

        let hueStep = 360.0 / Double(size)
        for i in 1..<size {
            let newHue = (baseColor.hue + (hueStep * Double(i))).truncatingRemainder(dividingBy: 360)

            if let newColor = ColorNormalizer.createFromHSL(
                hue: newHue,
                saturation: baseColor.saturation,
                lightness: baseColor.lightness,
                alpha: baseColor.alpha
            ) {
                palette.append(newColor)
            }
        }

        return palette
    }

    /// Finds the dominant colors in a set
    /// - Parameters:
    ///   - colors: Array of colors to analyze
    ///   - count: Number of dominant colors to return
    /// - Returns: Array of dominant colors by frequency/representation
    static func findDominantColors(_ colors: [CanonicalColor], count: Int = 5) -> [CanonicalColor] {
        var colorGroups: [String: [CanonicalColor]] = [:]

        for color in colors {
            let family = classifyHueFamily(hue: color.hue)
            let key = family.rawValue

            if colorGroups[key] == nil {
                colorGroups[key] = []
            }
            colorGroups[key]?.append(color)
        }

        var dominant: [CanonicalColor] = []

        for (_, group) in colorGroups.sorted(by: { $0.value.count > $1.value.count }) {
            if let avgColor = ColorNormalizer.averageColor(of: group) {
                dominant.append(avgColor)
                if dominant.count >= count {
                    break
                }
            }
        }

        return dominant
    }

    /// Ranks colors by a specific property
    /// - Parameters:
    ///   - colors: Array of colors to rank
    ///   - property: Property name to rank by
    /// - Returns: Sorted array of colors by property
    static func rankColorsByProperty(_ colors: [CanonicalColor], property: String) -> [CanonicalColor] {
        let scores = colors.map { (color: $0, score: scoreColorProperties($0)) }

        switch property {
        case "vibrance":
            return scores.sorted { ($0.score["vibrance"] as? Double ?? 0) > ($1.score["vibrance"] as? Double ?? 0) }.map { $0.color }
        case "contrast":
            return scores.sorted { ($0.score["contrast"] as? Double ?? 0) > ($1.score["contrast"] as? Double ?? 0) }.map { $0.color }
        case "brightness":
            return scores.sorted { ($0.score["brightness"] as? Double ?? 0) > ($1.score["brightness"] as? Double ?? 0) }.map { $0.color }
        case "saturation":
            return scores.sorted { ($0.score["saturation"] as? Double ?? 0) > ($1.score["saturation"] as? Double ?? 0) }.map { $0.color }
        default:
            return colors
        }
    }

    /// Analyzes color distribution in a palette
    /// - Parameter colors: Array of colors to analyze
    /// - Returns: Dictionary with distribution statistics
    static func analyzeColorDistribution(_ colors: [CanonicalColor]) -> [String: Any] {
        guard !colors.isEmpty else { return [:] }

        var stats: [String: Any] = [:]

        let avgHue = colors.reduce(0.0) { $0 + $1.hue } / Double(colors.count)
        let avgSaturation = colors.reduce(0.0) { $0 + $1.saturation } / Double(colors.count)
        let avgLightness = colors.reduce(0.0) { $0 + $1.lightness } / Double(colors.count)

        stats["average_hue"] = avgHue
        stats["average_saturation"] = avgSaturation
        stats["average_lightness"] = avgLightness

        // Color diversity
        let hueDiversity = colors.reduce(0.0) { acc, color in
            let diff = abs(color.hue - avgHue)
            return acc + diff * diff
        }
        stats["hue_diversity"] = sqrt(hueDiversity / Double(colors.count))

        // Family distribution
        var familyCount: [SemanticColorFamily: Int] = [:]
        for color in colors {
            let family = classifyHueFamily(hue: color.hue)
            familyCount[family, default: 0] += 1
        }
        stats["family_distribution"] = familyCount.mapValues { $0 }

        return stats
    }

    /// Validates color scheme for common issues
    /// - Parameter colors: Array of colors to validate
    /// - Returns: Array of validation warnings/issues
    static func validateColorScheme(_ colors: [CanonicalColor]) -> [String] {
        var warnings: [String] = []

        // Check for too many similar colors
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                let distance = ColorNormalizer.computeColorDistance(colors[i], colors[j])
                if distance < 10 {
                    warnings.append("Colors \(i) and \(j) are too similar (distance: \(String(format: "%.1f", distance)))")
                }
            }
        }

        // Check for low contrast combinations
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                if !hasAdequateContrast(colors[i], on: colors[j], level: "AA") {
                    warnings.append("Colors \(i) and \(j) have insufficient contrast for readability")
                }
            }
        }

        // Check for hue distribution
        let hueDiversity = analyzeColorDistribution(colors)["hue_diversity"] as? Double ?? 0
        if hueDiversity < 30 {
            warnings.append("Hue distribution is too narrow - consider more diverse colors")
        }

        return warnings
    }
}
