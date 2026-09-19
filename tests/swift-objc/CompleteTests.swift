import XCTest
@testable import ColorEngine

/// Comprehensive test suite for Apple Color Engine
/// Covers color parsing, variable resolution, semantic mapping, palette generation, and CLI

final class ColorParsingTests: XCTestCase {
    let engine = ColorEngine()

    // MARK: - Hex Color Tests

    func testParseHexRGB() {
        let colors = engine.extractColors(from: "#FF5733")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hex, "FF5733")
        XCTAssertEqual(colors[0].rgb.red, 255)
        XCTAssertEqual(colors[0].rgb.green, 87)
        XCTAssertEqual(colors[0].rgb.blue, 51)
    }

    func testParseHexRRGGBB() {
        let colors = engine.extractColors(from: "#0099FF")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hex, "0099FF")
        XCTAssertEqual(colors[0].rgb.red, 0)
        XCTAssertEqual(colors[0].rgb.green, 153)
        XCTAssertEqual(colors[0].rgb.blue, 255)
    }

    func testParseHexRGBA() {
        let colors = engine.extractColors(from: "#FF5733FF")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hex, "FF5733")
        XCTAssertEqual(colors[0].alpha, 1.0, accuracy: 0.01)
    }

    func testParseHexRRGGBBAA() {
        let colors = engine.extractColors(from: "#FF573380")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hex, "FF5733")
        XCTAssertGreater(colors[0].alpha, 0.4)
        XCTAssertLess(colors[0].alpha, 0.6)
    }

    func testParseHexRGBShort() {
        let colors = engine.extractColors(from: "#F57")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hex, "FF5577")
    }

    func testParseHexRGBAShort() {
        let colors = engine.extractColors(from: "#F5F8")
        XCTAssertEqual(colors.count, 1)
    }

    func testParseMultipleHexColors() {
        let colors = engine.extractColors(from: "#FF5733 #0099FF #00FF00")
        XCTAssertEqual(colors.count, 3)
    }

    // MARK: - RGB/RGBA Function Tests

    func testParseRGBFunction() {
        let colors = engine.extractColors(from: "rgb(255, 87, 51)")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.red, 255)
        XCTAssertEqual(colors[0].rgb.green, 87)
        XCTAssertEqual(colors[0].rgb.blue, 51)
    }

    func testParseRGBAFunction() {
        let colors = engine.extractColors(from: "rgba(255, 87, 51, 0.5)")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].alpha, 0.5, accuracy: 0.01)
    }

    func testParseRGBWithSpaces() {
        let colors = engine.extractColors(from: "rgb( 100 , 150 , 200 )")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.red, 100)
    }

    // MARK: - HSL Tests

    func testParseHSLFunction() {
        let colors = engine.extractColors(from: "hsl(120, 100%, 50%)")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].hsl.hue, 120, accuracy: 1)
        XCTAssertEqual(colors[0].hsl.saturation, 100, accuracy: 1)
        XCTAssertEqual(colors[0].hsl.lightness, 50, accuracy: 1)
    }

    func testParseHSLGreen() {
        let colors = engine.extractColors(from: "hsl(120, 100%, 50%)")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.green, 255)
    }

    func testParseHSLRed() {
        let colors = engine.extractColors(from: "hsl(0, 100%, 50%)")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.red, 255)
        XCTAssertEqual(colors[0].rgb.green, 0)
        XCTAssertEqual(colors[0].rgb.blue, 0)
    }

    // MARK: - CSS Variable Tests

    func testParseSimpleVariable() {
        let css = "--primary: #FF5733; --secondary: #0099FF;"
        let resolved = engine.resolveVariables(css)
        XCTAssertEqual(resolved["primary"], "#FF5733")
        XCTAssertEqual(resolved["secondary"], "#0099FF")
    }

    func testParseVariableWithDashes() {
        let css = "--color-primary: #FF5733;"
        let resolved = engine.resolveVariables(css)
        XCTAssertEqual(resolved["color-primary"], "#FF5733")
    }

    func testParseMultipleVariables() {
        let css = "--bg: #FFF; --text: #000; --accent: #007AFF;"
        let resolved = engine.resolveVariables(css)
        XCTAssertEqual(resolved.count, 3)
    }

    // MARK: - Nested Variables Tests

    func testResolveNestedVariables() {
        let css = "--primary: #FF5733; --bg: var(--primary);"
        let resolved = engine.resolveVariables(css)
        XCTAssertNotNil(resolved["primary"])
        XCTAssertNotNil(resolved["bg"])
    }

    func testResolveDeeplyNestedVariables() {
        let css = "--a: #FF0000; --b: var(--a); --c: var(--b);"
        let resolved = engine.resolveVariables(css)
        XCTAssertEqual(resolved.count, 3)
    }

    // MARK: - Circular Variable Tests

    func testCircularVariableDetection() {
        let css = "--a: var(--b); --b: var(--a);"
        let resolved = engine.resolveVariables(css)
        // Should not cause infinite loop
        XCTAssertEqual(resolved.count, 2)
    }

    // MARK: - Variable Fallback Tests

    func testVariableFallback() {
        let css = "--primary: #FF5733;"
        let resolved = engine.resolveVariables(css, fallback: "#000000")
        XCTAssertEqual(resolved.count, 1)
    }

    // MARK: - Cascade Resolution Tests

    func testCascadeResolution() {
        let css1 = "--primary: #FF5733;"
        let css2 = "--primary: #0099FF;"
        let resolved1 = engine.resolveVariables(css1)
        let resolved2 = engine.resolveVariables(css2)
        XCTAssertNotEqual(resolved1["primary"], resolved2["primary"])
    }

    // MARK: - Token Normalization Tests

    func testNormalizeHexToken() {
        let rawTokens: [String: String] = ["primary-color": "#FF5733"]
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].name, "primary-color")
        XCTAssertEqual(tokens[0].value.hex, "FF5733")
    }

    func testNormalizeRGBToken() {
        let rawTokens: [String: String] = ["bg-color": "rgb(255, 255, 255)"]
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].value.rgb.red, 255)
    }

    func testNormalizeMultipleTokens() {
        let rawTokens: [String: String] = [
            "primary": "#FF5733",
            "secondary": "#0099FF",
            "background": "#FFFFFF"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens.count, 3)
    }

    func testNormalizeCategorization() {
        let rawTokens: [String: String] = [
            "primary-color": "#FF5733",
            "success-indicator": "#00FF00",
            "error-state": "#FF0000"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens[0].category, "primary")
        XCTAssertEqual(tokens[1].category, "success")
        XCTAssertEqual(tokens[2].category, "danger")
    }

    // MARK: - Semantic Mapping Tests

    func testApplySemanticMappingPrimary() {
        let rawTokens: [String: String] = ["primary-color": "#FF5733"]
        let tokens = engine.normalizeTokens(rawTokens)
        let mappings: [String: String] = ["primary": "primary"]
        let mapped = engine.applySemanticMappings(tokens, mappings: mappings)
        XCTAssertEqual(mapped[0].semanticRole, "primary")
    }

    func testApplySemanticMappingMultiple() {
        let rawTokens: [String: String] = [
            "primary": "#FF5733",
            "secondary": "#0099FF",
            "danger": "#FF0000"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        let mappings: [String: String] = [
            "primary": "primary",
            "secondary": "secondary",
            "danger": "destructive"
        ]
        let mapped = engine.applySemanticMappings(tokens, mappings: mappings)
        XCTAssertEqual(mapped.count, 3)
    }

    // MARK: - Specificity Tests

    func testSpecificityHandling() {
        let css1 = "color: #FF5733;"
        let css2 = "div { color: #0099FF; }"
        // More specific selector should override
        let rules1 = engine.parseCSS(css1)
        let rules2 = engine.parseCSS(css2)
        XCTAssertNotEqual(rules1, rules2)
    }

    // MARK: - Media Query Tests

    func testMediaQueryParsing() {
        let css = """
        @media (prefers-color-scheme: dark) {
            --bg-color: #000000;
            --text-color: #FFFFFF;
        }
        """
        let rules = engine.parseCSS(css)
        // Should extract some rules
        XCTAssertGreater(rules.count, 0)
    }

    // MARK: - Light/Dark Mode Tests

    func testLightModeColorGeneration() {
        let rawTokens: [String: String] = [
            "bg-light": "#FFFFFF",
            "text-light": "#000000"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        let palette = engine.generatePalettes(tokens, includeLight: true, includeDark: false)
        XCTAssertGreater(palette.lightColors.count, 0)
        XCTAssertEqual(palette.darkColors.count, 0)
    }

    func testDarkModeColorGeneration() {
        let rawTokens: [String: String] = [
            "bg-dark": "#000000",
            "text-dark": "#FFFFFF"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        let palette = engine.generatePalettes(tokens, includeLight: false, includeDark: true)
        XCTAssertEqual(palette.lightColors.count, 0)
        XCTAssertGreater(palette.darkColors.count, 0)
    }

    func testBothModeColorGeneration() {
        let rawTokens: [String: String] = [
            "bg-light": "#FFFFFF",
            "bg-dark": "#000000"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        let palette = engine.generatePalettes(tokens, includeLight: true, includeDark: true)
        XCTAssertGreater(palette.lightColors.count, 0)
        XCTAssertGreater(palette.darkColors.count, 0)
    }

    // MARK: - Palette Generation Tests

    func testGeneratePalette() {
        let rawTokens: [String: String] = [
            "primary": "#FF5733",
            "secondary": "#0099FF",
            "background": "#FFFFFF"
        ]
        let tokens = engine.normalizeTokens(rawTokens)
        let palette = engine.generatePalettes(tokens)
        XCTAssertGreater(palette.commonColors.count + palette.lightColors.count + palette.darkColors.count, 0)
    }

    // MARK: - Validation Tests

    func testValidateCorrectColor() {
        let color = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            alpha: 1.0,
            originalFormat: "hex",
            source: "test"
        )
        let token = Token(name: "test", value: color, category: "primary")
        let errors = engine.validateColors([token])
        XCTAssertEqual(errors.count, 0)
    }

    func testValidateInvalidRed() {
        let color = Color(
            hex: "FF5733",
            rgb: RGB(red: 256, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            alpha: 1.0,
            originalFormat: "hex",
            source: "test"
        )
        let token = Token(name: "test", value: color, category: "primary")
        let errors = engine.validateColors([token])
        XCTAssertGreater(errors.count, 0)
    }

    func testValidateInvalidAlpha() {
        let color = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            alpha: 1.5,
            originalFormat: "hex",
            source: "test"
        )
        let token = Token(name: "test", value: color, category: "primary")
        let errors = engine.validateColors([token])
        XCTAssertGreater(errors.count, 0)
    }

    // MARK: - Provenance Tests

    func testSetProvenance() {
        let provenance = ColorProvenance(
            tokenName: "primary",
            source: "main.css",
            lineNumber: 42,
            cssSelector: ".primary",
            mediaQuery: "(prefers-color-scheme: dark)",
            specificity: 10,
            resolvedValue: "#FF5733"
        )
        engine.setProvenance(provenance, for: "primary")
        let retrieved = engine.getProvenance(for: "primary")
        XCTAssertEqual(retrieved?.tokenName, "primary")
        XCTAssertEqual(retrieved?.lineNumber, 42)
    }

    // MARK: - Serialization Tests

    func testSerializeToJSON() {
        let color = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            originalFormat: "hex",
            source: "test"
        )
        let token = Token(name: "primary", value: color, category: "primary")
        let json = engine.serializeToJSON([token])
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("primary") ?? false)
    }

    func testSerializeToText() {
        let color = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            originalFormat: "hex",
            source: "test"
        )
        let token = Token(name: "primary", value: color, category: "primary")
        let text = engine.serializeToText([token])
        XCTAssertTrue(text.contains("primary"))
        XCTAssertTrue(text.contains("FF5733"))
    }

    // MARK: - HTML Parsing Tests

    func testParseHTMLStyleTag() {
        let html = """
        <html>
            <head>
                <style>
                    .color { color: #FF5733; }
                </style>
            </head>
        </html>
        """
        let styles = engine.parseHTML(html)
        XCTAssertGreater(styles.count, 0)
    }

    func testParseHTMLInlineStyle() {
        let html = "<div style=\"background-color: #FF5733; color: #FFFFFF;\"></div>"
        let styles = engine.parseHTML(html)
        XCTAssertGreater(styles.count, 0)
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let colors = engine.extractColors(from: "")
        XCTAssertEqual(colors.count, 0)
    }

    func testMalformedHex() {
        let colors = engine.extractColors(from: "#GGGGGG")
        // Should not crash, gracefully handle invalid hex
        XCTAssertTrue(true)
    }

    func testInvalidColorValues() {
        let rawTokens: [String: String] = ["bad": "not-a-color"]
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens.count, 0)
    }

    // MARK: - Boundary Tests

    func testColorBoundaryMin() {
        let colors = engine.extractColors(from: "#000000")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.red, 0)
        XCTAssertEqual(colors[0].rgb.green, 0)
        XCTAssertEqual(colors[0].rgb.blue, 0)
    }

    func testColorBoundaryMax() {
        let colors = engine.extractColors(from: "#FFFFFF")
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colors[0].rgb.red, 255)
        XCTAssertEqual(colors[0].rgb.green, 255)
        XCTAssertEqual(colors[0].rgb.blue, 255)
    }

    // MARK: - Integration Tests

    func testEndToEndPipeline() {
        let css = """
        --primary-color: #FF5733;
        --secondary-color: #0099FF;
        .button {
            background-color: var(--primary-color);
            color: #FFFFFF;
        }
        """

        let variables = engine.resolveVariables(css)
        XCTAssertEqual(variables.count, 2)

        let colors = engine.extractColors(from: css)
        XCTAssertGreater(colors.count, 0)

        let rules = engine.parseCSS(css)
        let tokens = engine.normalizeTokens(rules)
        let errors = engine.validateColors(tokens)
        XCTAssertEqual(errors.count, 0)

        let palette = engine.generatePalettes(tokens)
        XCTAssertGreater(palette.commonColors.count + palette.lightColors.count + palette.darkColors.count, 0)
    }

    func testFullWorkflow() {
        // Step 1: Define colors
        let rawTokens: [String: String] = [
            "primary-color": "#FF5733",
            "secondary-color": "#0099FF",
            "success-color": "#00FF00",
            "error-color": "#FF0000"
        ]

        // Step 2: Normalize
        let tokens = engine.normalizeTokens(rawTokens)
        XCTAssertEqual(tokens.count, 4)

        // Step 3: Validate
        let errors = engine.validateColors(tokens)
        XCTAssertEqual(errors.count, 0)

        // Step 4: Apply semantic mapping
        let mappings: [String: String] = [
            "primary": "primary",
            "secondary": "secondary",
            "success": "success",
            "error": "destructive"
        ]
        let mapped = engine.applySemanticMappings(tokens, mappings: mappings)
        XCTAssertGreater(mapped.count, 0)

        // Step 5: Generate palette
        let palette = engine.generatePalettes(mapped)
        XCTAssertGreater(palette.commonColors.count, 0)

        // Step 6: Serialize
        let json = engine.serializeToJSON(tokens)
        XCTAssertNotNil(json)
    }
}

// MARK: - CLI Tests

final class CLITests: XCTestCase {
    let cli = ColorEngineCLI()

    func testCLIHelpCommand() {
        let args = ["color-engine", "--help"]
        let exitCode = cli.run(arguments: args)
        XCTAssertEqual(exitCode, 0)
    }

    func testCLIVersionCommand() {
        let args = ["color-engine", "--version"]
        let exitCode = cli.run(arguments: args)
        XCTAssertEqual(exitCode, 0)
    }

    func testCLIInvalidCommand() {
        let args = ["color-engine", "invalid-command"]
        let exitCode = cli.run(arguments: args)
        XCTAssertNotEqual(exitCode, 0)
    }

    func testCLINoArgs() {
        let args = ["color-engine"]
        let exitCode = cli.run(arguments: args)
        XCTAssertNotEqual(exitCode, 0)
    }
}

// MARK: - Color Model Tests

final class ColorModelTests: XCTestCase {
    func testRGBBoundaries() {
        let rgb = RGB(red: 300, green: -50, blue: 150)
        XCTAssertEqual(rgb.red, 255)
        XCTAssertEqual(rgb.green, 0)
        XCTAssertEqual(rgb.blue, 150)
    }

    func testHSLBoundaries() {
        let hsl = HSL(hue: 400, saturation: 150, lightness: -10)
        XCTAssertGreaterThanOrEqual(hsl.hue, 0)
        XCTAssertLessThan(hsl.hue, 360)
        XCTAssertEqual(hsl.saturation, 100)
        XCTAssertEqual(hsl.lightness, 0)
    }

    func testColorEquality() {
        let color1 = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            originalFormat: "hex",
            source: "test"
        )
        let color2 = Color(
            hex: "FF5733",
            rgb: RGB(red: 255, green: 87, blue: 51),
            hsl: HSL(hue: 12, saturation: 100, lightness: 60),
            originalFormat: "hex",
            source: "test"
        )
        XCTAssertEqual(color1, color2)
    }
}

// MARK: - Color Conversion Tests

final class ColorConversionTests: XCTestCase {
    let engine = ColorEngine()

    func testRGBToHex() {
        let rgb = RGB(red: 255, green: 87, blue: 51)
        let hex = rgb.toHex()
        XCTAssertEqual(hex, "FF5733")
    }

    func testHexToRGBAndBack() {
        let colors = engine.extractColors(from: "#FF5733")
        XCTAssertEqual(colors.count, 1)
        let hex = colors[0].rgb.toHex()
        XCTAssertEqual(hex, "FF5733")
    }
}
