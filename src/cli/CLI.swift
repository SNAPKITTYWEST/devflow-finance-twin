import Foundation

/// Command-line interface for Apple Color Engine
/// Provides scan, extract, normalize, map, resolve, validate, palette, and report commands

public class ColorEngineCLI {
    private let engine = ColorEngine()
    private var diagnosticLevel: Int = 0
    private var outputFormat: OutputFormat = .json
    private var inputPath: String = ""
    private var outputPath: String?
    private var lightMode: Bool = false
    private var darkMode: Bool = false

    public enum OutputFormat: String {
        case json = "json"
        case text = "text"
        case csv = "csv"
    }

    public init() {}

    /// Main entry point for CLI
    /// - Parameter arguments: Command-line arguments
    /// - Returns: Exit code (0 = success, non-zero = failure)
    public func run(arguments: [String]) -> Int32 {
        guard arguments.count > 1 else {
            printUsage()
            return 1
        }

        let command = arguments[1]

        do {
            switch command {
            case "scan":
                return try handleScan(Array(arguments.dropFirst(2))) ? 0 : 1
            case "extract":
                return try handleExtract(Array(arguments.dropFirst(2))) ? 0 : 1
            case "normalize":
                return try handleNormalize(Array(arguments.dropFirst(2))) ? 0 : 1
            case "map":
                return try handleMap(Array(arguments.dropFirst(2))) ? 0 : 1
            case "resolve":
                return try handleResolve(Array(arguments.dropFirst(2))) ? 0 : 1
            case "validate":
                return try handleValidate(Array(arguments.dropFirst(2))) ? 0 : 1
            case "palette":
                return try handlePalette(Array(arguments.dropFirst(2))) ? 0 : 1
            case "report":
                return try handleReport(Array(arguments.dropFirst(2))) ? 0 : 1
            case "--help", "-h":
                printHelp()
                return 0
            case "--version", "-v":
                printVersion()
                return 0
            default:
                print("Error: Unknown command '\(command)'")
                printUsage()
                return 1
            }
        } catch {
            print("Error: \(error)")
            return 1
        }
    }

    // MARK: - Command Handlers

    /// Scan directory for color definitions
    /// Usage: scan <directory> [--recursive] [--format json|text|csv] [--output <file>]
    private func handleScan(_ args: [String]) throws -> Bool {
        var directory = ""
        var recursive = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--recursive", "-r":
                recursive = true
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && directory.isEmpty {
                    directory = arg
                }
            }
            i += 1
        }

        guard !directory.isEmpty else {
            print("Error: Directory path required")
            return false
        }

        var results: [String: String] = [:]

        if recursive {
            results = scanDirectoryRecursive(directory)
        } else {
            results = scanDirectory(directory)
        }

        if diagnosticLevel >= 1 {
            print("Found \(results.count) color definitions")
        }

        let output = formatOutput(results, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Extract colors from file(s)
    /// Usage: extract <file|directory> [--format json|text|csv] [--output <file>] [--light|--dark]
    private func handleExtract(_ args: [String]) throws -> Bool {
        var path = ""

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--light":
                lightMode = true
            case "--dark":
                darkMode = true
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && path.isEmpty {
                    path = arg
                }
            }
            i += 1
        }

        guard !path.isEmpty else {
            print("Error: File or directory path required")
            return false
        }

        var cssContent = ""
        let isDirectory = FileManager.default.fileExists(atPath: path) &&
            (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? String == FileAttributeType.typeDirectory.rawValue ?? false

        if isDirectory {
            let files = try FileManager.default.contentsOfDirectory(atPath: path)
            let cssFiles = files.filter { $0.hasSuffix(".css") || $0.hasSuffix(".html") }
            for file in cssFiles {
                let fullPath = (path as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    cssContent += content + "\n"
                }
            }
        } else {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                cssContent = content
            }
        }

        let colors = engine.extractColors(from: cssContent)

        if diagnosticLevel >= 1 {
            print("Extracted \(colors.count) colors")
        }

        let output = formatColors(colors, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Normalize color tokens
    /// Usage: normalize <file> [--format json|text|csv] [--output <file>]
    private func handleNormalize(_ args: [String]) throws -> Bool {
        var filePath = ""

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        let cssRules = engine.parseCSS(content)
        let tokens = engine.normalizeTokens(cssRules)

        if diagnosticLevel >= 1 {
            print("Normalized \(tokens.count) tokens")
        }

        let output = formatTokens(tokens, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Apply semantic mappings
    /// Usage: map <file> [--mappings <json>] [--format json|text|csv] [--output <file>]
    private func handleMap(_ args: [String]) throws -> Bool {
        var filePath = ""
        var mappingsJSON = ""

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--mappings":
                i += 1
                if i < args.count {
                    mappingsJSON = args[i]
                }
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        let cssRules = engine.parseCSS(content)
        var tokens = engine.normalizeTokens(cssRules)

        var mappings: [String: String] = [:]
        if !mappingsJSON.isEmpty, let data = mappingsJSON.data(using: .utf8) {
            mappings = (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
        }

        tokens = engine.applySemanticMappings(tokens, mappings: mappings)

        if diagnosticLevel >= 1 {
            print("Applied semantic mappings to \(tokens.count) tokens")
        }

        let output = formatTokens(tokens, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Resolve CSS variables
    /// Usage: resolve <file> [--fallback <color>] [--format json|text|csv] [--output <file>]
    private func handleResolve(_ args: [String]) throws -> Bool {
        var filePath = ""
        var fallback = "#000000"

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--fallback":
                i += 1
                if i < args.count {
                    fallback = args[i]
                }
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        let resolved = engine.resolveVariables(content, fallback: fallback)

        if diagnosticLevel >= 1 {
            print("Resolved \(resolved.count) variables")
        }

        let output = formatVariables(resolved, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Validate color definitions
    /// Usage: validate <file> [--format json|text|csv] [--output <file>]
    private func handleValidate(_ args: [String]) throws -> Bool {
        var filePath = ""

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        let cssRules = engine.parseCSS(content)
        let tokens = engine.normalizeTokens(cssRules)
        let errors = engine.validateColors(tokens)

        if diagnosticLevel >= 1 {
            if errors.isEmpty {
                print("Validation passed: all \(tokens.count) tokens are valid")
            } else {
                print("Found \(errors.count) validation errors")
            }
        }

        let output = formatValidationResults(errors, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Generate color palettes
    /// Usage: palette <file> [--light|--dark|--both] [--format json|text|csv] [--output <file>]
    private func handlePalette(_ args: [String]) throws -> Bool {
        var filePath = ""
        var includeLight = false
        var includeDark = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--light":
                includeLight = true
            case "--dark":
                includeDark = true
            case "--both":
                includeLight = true
                includeDark = true
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        if !includeLight && !includeDark {
            includeLight = true
            includeDark = true
        }

        let cssRules = engine.parseCSS(content)
        let tokens = engine.normalizeTokens(cssRules)
        let palette = engine.generatePalettes(tokens, includeLight: includeLight, includeDark: includeDark)

        if diagnosticLevel >= 1 {
            let total = palette.lightColors.count + palette.darkColors.count + palette.commonColors.count
            print("Generated palette with \(total) colors")
        }

        let output = formatPalette(palette, format: outputFormat)
        writeOutput(output)

        return true
    }

    /// Generate comprehensive report
    /// Usage: report <file> [--format json|text|csv] [--output <file>] [--include-provenance]
    private func handleReport(_ args: [String]) throws -> Bool {
        var filePath = ""
        var includeProvenance = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--include-provenance":
                includeProvenance = true
            case "--format":
                i += 1
                if i < args.count, let format = OutputFormat(rawValue: args[i]) {
                    outputFormat = format
                }
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputPath = args[i]
                }
            case "--diagnostic":
                i += 1
                if i < args.count, let level = Int(args[i]) {
                    diagnosticLevel = level
                }
            default:
                if !arg.hasPrefix("-") && filePath.isEmpty {
                    filePath = arg
                }
            }
            i += 1
        }

        guard !filePath.isEmpty else {
            print("Error: File path required")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("Error: Could not read file")
            return false
        }

        let cssRules = engine.parseCSS(content)
        let tokens = engine.normalizeTokens(cssRules)
        let errors = engine.validateColors(tokens)
        let palette = engine.generatePalettes(tokens, includeLight: true, includeDark: true)

        let output = formatReport(
            tokens: tokens,
            errors: errors,
            palette: palette,
            includeProvenance: includeProvenance,
            format: outputFormat
        )

        writeOutput(output)

        return true
    }

    // MARK: - Formatting Functions

    private func formatOutput(_ results: [String: String], format: OutputFormat) -> String {
        switch format {
        case .json:
            if let data = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case .text:
            var output = ""
            for (key, value) in results.sorted(by: { $0.key < $1.key }) {
                output += "\(key): \(value)\n"
            }
            return output

        case .csv:
            var output = "Key,Value\n"
            for (key, value) in results.sorted(by: { $0.key < $1.key }) {
                output += "\"\(key)\",\"\(value)\"\n"
            }
            return output
        }
    }

    private func formatColors(_ colors: [Color], format: OutputFormat) -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(colors), let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "[]"

        case .text:
            var output = ""
            for color in colors {
                output += "Color: #\(color.hex)\n"
                output += "  RGB: rgb(\(color.rgb.red), \(color.rgb.green), \(color.rgb.blue))\n"
                output += "  HSL: hsl(\(Int(color.hsl.hue)), \(Int(color.hsl.saturation))%, \(Int(color.hsl.lightness))%)\n"
                output += "  Alpha: \(color.alpha)\n\n"
            }
            return output

        case .csv:
            var output = "Hex,Red,Green,Blue,Hue,Saturation,Lightness,Alpha\n"
            for color in colors {
                output += "#\(color.hex),\(color.rgb.red),\(color.rgb.green),\(color.rgb.blue),"
                output += "\(Int(color.hsl.hue)),\(Int(color.hsl.saturation)),\(Int(color.hsl.lightness)),\(color.alpha)\n"
            }
            return output
        }
    }

    private func formatTokens(_ tokens: [Token], format: OutputFormat) -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(tokens), let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "[]"

        case .text:
            return engine.serializeToText(tokens)

        case .csv:
            var output = "Name,Hex,RGB,HSL,Category,Semantic\n"
            for token in tokens {
                let rgb = "rgb(\(token.value.rgb.red),\(token.value.rgb.green),\(token.value.rgb.blue))"
                let hsl = "hsl(\(Int(token.value.hsl.hue)),\(Int(token.value.hsl.saturation))%,\(Int(token.value.hsl.lightness))%)"
                let semantic = token.semanticRole ?? "none"
                output += "\"\(token.name)\",#\(token.value.hex),\"\(rgb)\",\"\(hsl)\",\(token.category),\(semantic)\n"
            }
            return output
        }
    }

    private func formatVariables(_ variables: [String: String], format: OutputFormat) -> String {
        switch format {
        case .json:
            if let data = try? JSONSerialization.data(withJSONObject: variables, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case .text:
            var output = ""
            for (name, value) in variables.sorted(by: { $0.key < $1.key }) {
                output += "\(name): \(value)\n"
            }
            return output

        case .csv:
            var output = "Variable,Value\n"
            for (name, value) in variables.sorted(by: { $0.key < $1.key }) {
                output += "\"\(name)\",\"\(value)\"\n"
            }
            return output
        }
    }

    private func formatValidationResults(_ errors: [String], format: OutputFormat) -> String {
        switch format {
        case .json:
            let dict: [String: Any] = [
                "valid": errors.isEmpty,
                "errorCount": errors.count,
                "errors": errors
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case .text:
            if errors.isEmpty {
                return "Validation passed: no errors found\n"
            }
            var output = "Validation errors: \(errors.count)\n"
            for error in errors {
                output += "  - \(error)\n"
            }
            return output

        case .csv:
            var output = "Error\n"
            for error in errors {
                output += "\"\(error)\"\n"
            }
            return output
        }
    }

    private func formatPalette(_ palette: PaletteConfig, format: OutputFormat) -> String {
        switch format {
        case .json:
            let dict: [String: Any] = [
                "light": palette.lightColors,
                "dark": palette.darkColors,
                "common": palette.commonColors
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case .text:
            var output = "Light Mode:\n"
            for (name, color) in palette.lightColors.sorted(by: { $0.key < $1.key }) {
                output += "  \(name): \(color)\n"
            }
            output += "\nDark Mode:\n"
            for (name, color) in palette.darkColors.sorted(by: { $0.key < $1.key }) {
                output += "  \(name): \(color)\n"
            }
            output += "\nCommon:\n"
            for (name, color) in palette.commonColors.sorted(by: { $0.key < $1.key }) {
                output += "  \(name): \(color)\n"
            }
            return output

        case .csv:
            var output = "Mode,Name,Color\n"
            for (name, color) in palette.lightColors {
                output += "light,\"\(name)\",\(color)\n"
            }
            for (name, color) in palette.darkColors {
                output += "dark,\"\(name)\",\(color)\n"
            }
            for (name, color) in palette.commonColors {
                output += "common,\"\(name)\",\(color)\n"
            }
            return output
        }
    }

    private func formatReport(tokens: [Token], errors: [String], palette: PaletteConfig, includeProvenance: Bool, format: OutputFormat) -> String {
        switch format {
        case .json:
            var report: [String: Any] = [
                "summary": [
                    "tokenCount": tokens.count,
                    "errorCount": errors.count,
                    "isValid": errors.isEmpty
                ],
                "tokens": tokens.map { $0 },
                "errors": errors,
                "palette": [
                    "light": palette.lightColors,
                    "dark": palette.darkColors,
                    "common": palette.commonColors
                ]
            ]

            if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case .text:
            var output = "=== COLOR ENGINE REPORT ===\n\n"
            output += "Summary:\n"
            output += "  Total Tokens: \(tokens.count)\n"
            output += "  Errors: \(errors.count)\n"
            output += "  Status: \(errors.isEmpty ? "VALID" : "INVALID")\n\n"

            output += "Tokens:\n"
            output += engine.serializeToText(tokens)

            if !errors.isEmpty {
                output += "Validation Errors:\n"
                for error in errors {
                    output += "  - \(error)\n"
                }
                output += "\n"
            }

            output += "Palette:\n"
            output += "  Light colors: \(palette.lightColors.count)\n"
            output += "  Dark colors: \(palette.darkColors.count)\n"
            output += "  Common colors: \(palette.commonColors.count)\n"

            return output

        case .csv:
            var output = "Type,Name,Value\n"
            for token in tokens {
                output += "token,\"\(token.name)\",#\(token.value.hex)\n"
            }
            for error in errors {
                output += "error,\"\(error)\",\"\"\n"
            }
            return output
        }
    }

    // MARK: - Directory Scanning

    private func scanDirectory(_ path: String) -> [String: String] {
        var results: [String: String] = [:]

        if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for file in files {
                let fullPath = (path as NSString).appendingPathComponent(file)
                if file.hasSuffix(".css") || file.hasSuffix(".html") {
                    if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                        let rules = engine.parseCSS(content)
                        results.merge(rules) { _, new in new }
                    }
                }
            }
        }

        return results
    }

    private func scanDirectoryRecursive(_ path: String) -> [String: String] {
        var results: [String: String] = [:]

        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let file as String in enumerator {
                if file.hasSuffix(".css") || file.hasSuffix(".html") {
                    let fullPath = (path as NSString).appendingPathComponent(file)
                    if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                        let rules = engine.parseCSS(content)
                        results.merge(rules) { _, new in new }
                    }
                }
            }
        }

        return results
    }

    // MARK: - Output Handling

    private func writeOutput(_ content: String) {
        if let outputPath = outputPath {
            try? content.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if diagnosticLevel >= 1 {
                print("Output written to: \(outputPath)")
            }
        } else {
            print(content)
        }
    }

    // MARK: - Help Functions

    private func printUsage() {
        print("Usage: color-engine <command> [options]")
        print("Commands: scan, extract, normalize, map, resolve, validate, palette, report")
        print("Use 'color-engine <command> --help' for more information")
    }

    private func printHelp() {
        print("""
        Apple Color Engine - Command Line Interface

        COMMANDS:
          scan <dir>          Scan directory for color definitions
          extract <file>      Extract colors from file
          normalize <file>    Normalize color tokens
          map <file>          Apply semantic mappings
          resolve <file>      Resolve CSS variables
          validate <file>     Validate color definitions
          palette <file>      Generate color palettes
          report <file>       Generate comprehensive report

        OPTIONS:
          --format json|text|csv    Output format (default: json)
          --output <file>, -o       Write output to file
          --light               Include light mode colors
          --dark                Include dark mode colors
          --recursive, -r       Scan directories recursively
          --diagnostic <level>  Set diagnostic output level (0-3)
          --help, -h            Show this help message
          --version, -v         Show version information
        """)
    }

    private func printVersion() {
        print("Apple Color Engine v1.0.0")
    }
}

// MARK: - Main Entry Point

// Can be used as:
// let cli = ColorEngineCLI()
// exit(cli.run(arguments: CommandLine.arguments))
