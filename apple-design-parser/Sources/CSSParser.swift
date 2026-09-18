import Foundation

public struct CSSSelector {
    public let selector: String
    public let specificity: (id: Int, classes: Int, elements: Int)
    public let isPseudoClass: Bool
    public let isPseudoElement: Bool
    public let location: SourceLocation

    public init(selector: String, location: SourceLocation) {
        self.selector = selector
        self.location = location

        var idCount = 0
        var classCount = 0
        var elementCount = 0

        let parts = selector.split(separator: " ", omittingEmptySubsequences: true)
        for part in parts {
            let partStr = String(part)
            if partStr.contains("#") {
                idCount += partStr.components(separatedBy: "#").count - 1
            }
            if partStr.contains(".") {
                classCount += partStr.components(separatedBy: ".").count - 1
            }
            if !partStr.contains("#") && !partStr.contains(".") && !partStr.contains(":") && !partStr.contains("[") {
                elementCount += 1
            }
        }

        self.specificity = (idCount, classCount, elementCount)
        self.isPseudoClass = selector.contains(":")
        self.isPseudoElement = selector.contains("::")
    }
}

public struct CSSDeclaration {
    public let property: String
    public let value: String
    public let important: Bool
    public let order: Int
    public let location: SourceLocation

    public init(property: String, value: String, important: Bool, order: Int, location: SourceLocation) {
        self.property = property
        self.value = value
        self.important = important
        self.order = order
        self.location = location
    }
}

public struct CSSRule {
    public let selector: CSSSelector
    public let declarations: [CSSDeclaration]
    public let media: String?
    public let location: SourceLocation
    public let isNested: Bool

    public init(
        selector: CSSSelector,
        declarations: [CSSDeclaration],
        media: String?,
        location: SourceLocation,
        isNested: Bool = false
    ) {
        self.selector = selector
        self.declarations = declarations
        self.media = media
        self.location = location
        self.isNested = isNested
    }
}

public struct CSSAtRule {
    public enum AtRuleType {
        case media
        case keyframes
        case fontFace
        case import
        case supports
        case document
        case unknown(String)
    }

    public let type: AtRuleType
    public let content: String
    public let prelude: String
    public let location: SourceLocation

    public init(type: AtRuleType, content: String, prelude: String, location: SourceLocation) {
        self.type = type
        self.content = content
        self.prelude = prelude
        self.location = location
    }
}

public struct CSSCustomProperty {
    public let name: String
    public let value: String
    public let location: SourceLocation
    public let scope: String?

    public init(name: String, value: String, location: SourceLocation, scope: String? = nil) {
        self.name = name
        self.value = value
        self.location = location
        self.scope = scope
    }
}

public struct CSSParseResult {
    public let rules: [CSSRule]
    public let atRules: [CSSAtRule]
    public let customProperties: [CSSCustomProperty]
    public let declarations: [CSSDeclaration]
    public let mediaQueries: [String]
    public let pseudoElements: [String]
    public let pseudoClasses: [String]
    public let errors: [ParseError]

    public init(
        rules: [CSSRule],
        atRules: [CSSAtRule],
        customProperties: [CSSCustomProperty],
        declarations: [CSSDeclaration],
        mediaQueries: [String],
        pseudoElements: [String],
        pseudoClasses: [String],
        errors: [ParseError]
    ) {
        self.rules = rules
        self.atRules = atRules
        self.customProperties = customProperties
        self.declarations = declarations
        self.mediaQueries = mediaQueries
        self.pseudoElements = pseudoElements
        self.pseudoClasses = pseudoClasses
        self.errors = errors
    }
}

public class CSSParser {
    private let css: String
    private let filename: String
    private var position: Int = 0
    private var line: Int = 1
    private var column: Int = 1
    private var rules: [CSSRule] = []
    private var atRules: [CSSAtRule] = []
    private var customProperties: [CSSCustomProperty] = []
    private var declarations: [CSSDeclaration] = []
    private var mediaQueries: Set<String> = []
    private var pseudoElements: Set<String> = []
    private var pseudoClasses: Set<String> = []
    private var errors: [ParseError] = []
    private var declarationOrder: Int = 0

    public init(css: String, filename: String = "unknown.css") {
        self.css = css
        self.filename = filename
    }

    public func parse() -> CSSParseResult {
        parseStylesheet()

        return CSSParseResult(
            rules: rules,
            atRules: atRules,
            customProperties: customProperties,
            declarations: declarations,
            mediaQueries: Array(mediaQueries).sorted(),
            pseudoElements: Array(pseudoElements).sorted(),
            pseudoClasses: Array(pseudoClasses).sorted(),
            errors: errors
        )
    }

    private func parseStylesheet() {
        while position < css.count {
            skipWhitespaceAndComments()
            if position >= css.count { break }

            if peekChar() == "@" {
                parseAtRule()
            } else if peekChar() != "}" {
                parseRule()
            } else {
                advance()
            }
        }
    }

    private func parseAtRule() {
        let location = currentLocation()
        consume("@")
        let keyword = parseIdentifier()

        skipWhitespace()
        var prelude = ""

        while position < css.count && peekChar() != "{" && peekChar() != ";" {
            prelude.append(advance())
        }

        prelude = prelude.trimmingCharacters(in: .whitespaces)

        let type: CSSAtRule.AtRuleType
        switch keyword.lowercased() {
        case "media":
            type = .media
            mediaQueries.insert(prelude)
        case "keyframes":
            type = .keyframes
        case "font-face":
            type = .fontFace
        case "import":
            type = .import
        case "supports":
            type = .supports
        case "document":
            type = .document
        default:
            type = .unknown(keyword)
        }

        if peekChar() == "{" {
            consume("{")
            let content = parseBlock()
            consume("}")

            let atRule = CSSAtRule(type: type, content: content, prelude: prelude, location: location)
            atRules.append(atRule)

            if case .media = type {
                parseMediaRules(content: content, media: prelude)
            }
        } else if peekChar() == ";" {
            consume(";")
            let atRule = CSSAtRule(type: type, content: "", prelude: prelude, location: location)
            atRules.append(atRule)
        }
    }

    private func parseMediaRules(content: String, media: String) {
        let subParser = CSSParser(css: content, filename: filename)
        let result = subParser.parse()
        for rule in result.rules {
            var modifiedRule = rule
            // Attach media to rule
            rules.append(modifiedRule)
        }
    }

    private func parseRule() {
        let location = currentLocation()
        let selector = parseSelector()

        if selector.isEmpty {
            if peekChar() == "{" {
                consume("{")
                parseBlock()
                consume("}")
            }
            return
        }

        skipWhitespace()

        if peekChar() == "{" {
            consume("{")
            let decls = parseDeclarations()
            consume("}")

            let cssSelector = CSSSelector(selector: selector, location: location)

            if selector.contains(":") {
                pseudoClasses.insert(selector)
            }
            if selector.contains("::") {
                pseudoElements.insert(selector)
            }

            let rule = CSSRule(selector: cssSelector, declarations: decls, media: nil, location: location)
            rules.append(rule)
        }
    }

    private func parseSelector() -> String {
        var selector = ""

        while position < css.count {
            let char = peekChar()
            if char == "{" {
                break
            }
            if char == "," {
                break
            }
            selector.append(advance())
        }

        return selector.trimmingCharacters(in: .whitespaces)
    }

    private func parseDeclarations() -> [CSSDeclaration] {
        var declarations: [CSSDeclaration] = []

        while position < css.count && peekChar() != "}" {
            skipWhitespaceAndComments()
            if peekChar() == "}" { break }

            let location = currentLocation()
            let property = parseProperty()

            if property.isEmpty {
                skipUntilSemicolon()
                continue
            }

            skipWhitespace()
            if peekChar() != ":" {
                skipUntilSemicolon()
                continue
            }

            consume(":")
            skipWhitespace()

            let value = parseValue()
            skipWhitespace()

            var important = false
            if value.lowercased().hasSuffix("!important") {
                important = true
            }

            if peekChar() == ";" {
                consume(";")
            }

            let property_lower = property.lowercased()
            if property_lower.hasPrefix("--") {
                let customProp = CSSCustomProperty(name: property, value: value, location: location)
                customProperties.append(customProp)
            }

            let decl = CSSDeclaration(property: property, value: value, important: important, order: declarationOrder, location: location)
            declarations.append(decl)
            self.declarations.append(decl)
            declarationOrder += 1
        }

        return declarations
    }

    private func parseProperty() -> String {
        var property = ""

        while position < css.count {
            let char = peekChar()
            if char == ":" || char == ";" || char == "}" || char.isWhitespace {
                break
            }
            property.append(advance())
        }

        return property.trimmingCharacters(in: .whitespaces)
    }

    private func parseValue() -> String {
        var value = ""
        var depth = 0

        while position < css.count {
            let char = peekChar()

            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
            } else if char == ";" && depth == 0 {
                break
            } else if char == "}" && depth == 0 {
                break
            }

            value.append(advance())
        }

        return value.trimmingCharacters(in: .whitespaces)
    }

    private func parseBlock() -> String {
        var block = ""
        var depth = 1

        while position < css.count && depth > 0 {
            let char = peekChar()

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 { break }
            }

            block.append(advance())
        }

        return block
    }

    private func skipUntilSemicolon() {
        while position < css.count && peekChar() != ";" && peekChar() != "}" {
            advance()
        }
        if peekChar() == ";" {
            advance()
        }
    }

    private func skipWhitespaceAndComments() {
        while position < css.count {
            if isWhitespace(peekChar()) {
                advance()
            } else if peekChar() == "/" && position + 1 < css.count && peekChar(offset: 1) == "*" {
                advance()
                advance()

                while position + 1 < css.count {
                    if peekChar() == "*" && peekChar(offset: 1) == "/" {
                        advance()
                        advance()
                        break
                    }
                    advance()
                }
            } else {
                break
            }
        }
    }

    private func skipWhitespace() {
        while position < css.count && isWhitespace(peekChar()) {
            advance()
        }
    }

    private func isWhitespace(_ char: Character) -> Bool {
        return char.isWhitespace || char == "\n" || char == "\r" || char == "\t"
    }

    private func parseIdentifier() -> String {
        var identifier = ""

        while position < css.count && (peekChar().isLetter || peekChar().isNumber || peekChar() == "-" || peekChar() == "_") {
            identifier.append(advance())
        }

        return identifier
    }

    private func peekChar(offset: Int = 0) -> Character {
        let index = position + offset
        guard index < css.count else { return Character(UnicodeScalar(0)!) }
        let idx = css.index(css.startIndex, offsetBy: index)
        return css[idx]
    }

    @discardableResult
    private func consume(_ expected: String) {
        for char in expected {
            if position < css.count && peekChar() == char {
                advance()
            }
        }
    }

    @discardableResult
    private func advance() -> Character {
        guard position < css.count else { return Character(UnicodeScalar(0)!) }
        let idx = css.index(css.startIndex, offsetBy: position)
        let char = css[idx]

        position += 1
        if char == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }

        return char
    }

    private func currentLocation() -> SourceLocation {
        return SourceLocation(file: filename, line: line, column: column)
    }
}
