import Foundation

// MARK: - Command-Line Interface

struct AppleDesignParserCLI {

    enum Command: String {
        case parse = "parse"
        case extract = "extract"
        case resolve = "resolve"
        case validate = "validate"
    }

    static func main() {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            printUsage()
            return
        }

        let command = arguments[1]

        switch command {
        case Command.parse.rawValue:
            handleParse(Array(arguments.dropFirst(2)))
        case Command.extract.rawValue:
            handleExtract(Array(arguments.dropFirst(2)))
        case Command.resolve.rawValue:
            handleResolve(Array(arguments.dropFirst(2)))
        case Command.validate.rawValue:
            handleValidate(Array(arguments.dropFirst(2)))
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    // MARK: - Commands

    static func handleParse(_ args: [String]) {
        guard let filePath = args.first else {
            print("Usage: apple-parser parse <file>")
            return
        }

        do {
            let payload = try String(contentsOfFile: filePath, encoding: .utf8)
            let result = AppleDesignHTMLParser.parsePayload(payload)

            print("Parsed \(result.declarations.count) declarations:")
            for (variable, value) in result.colorTokens() {
                print("  \(variable): \(value)")
            }
        } catch {
            print("Error reading file: \(error)")
        }
    }

    static func handleExtract(_ args: [String]) {
        guard let filePath = args.first else {
            print("Usage: apple-parser extract <file>")
            return
        }

        do {
            let payload = try String(contentsOfFile: filePath, encoding: .utf8)
            let hexColors = PatternMatcher.extractHexColors(from: payload)

            print("Extracted \(hexColors.count) hex colors:")
            for color in hexColors {
                print("  \(color)")
            }
        } catch {
            print("Error: \(error)")
        }
    }

    static func handleResolve(_ args: [String]) {
        guard args.count >= 2 else {
            print("Usage: apple-parser resolve <token-name> [--dark]")
            return
        }

        let tokenName = args[0]
        let isDarkMode = args.contains("--dark")

        guard let token = AppleDesignPalette.token(byName: tokenName) else {
            print("Token not found: \(tokenName)")
            return
        }

        let resolver = ColorResolver(isDarkMode: isDarkMode)
        let resolvedColor = resolver.resolve(token)

        print("\(tokenName): \(resolvedColor)")
    }

    static func handleValidate(_ args: [String]) {
        guard let filePath = args.first else {
            print("Usage: apple-parser validate <file>")
            return
        }

        do {
            let payload = try String(contentsOfFile: filePath, encoding: .utf8)
            let result = AppleDesignHTMLParser.parsePayload(payload)

            var validCount = 0
            var invalidCount = 0

            for (_, value) in result.declarations {
                if PatternMatcher.identifyColorFormat(value) != .unknown {
                    validCount += 1
                } else {
                    invalidCount += 1
                }
            }

            print("Validation Report:")
            print("  Valid declarations: \(validCount)")
            print("  Invalid declarations: \(invalidCount)")
            print("  Total: \(result.declarations.count)")
        } catch {
            print("Error: \(error)")
        }
    }

    static func printUsage() {
        print("""
        Apple Design System Parser v1.0

        Usage:
          apple-parser parse <file>           Parse HTML/CSS file and extract color tokens
          apple-parser extract <file>         Extract all hex colors from file
          apple-parser resolve <token> [--dark] Resolve token to color value
          apple-parser validate <file>        Validate color declarations in file

        Examples:
          apple-parser parse page.html
          apple-parser extract styles.css
          apple-parser resolve "Primary Background"
          apple-parser resolve "Apple Blue (Link)" --dark
        """)
    }
}

// MARK: - Entry Point

AppleDesignParserCLI.main()
