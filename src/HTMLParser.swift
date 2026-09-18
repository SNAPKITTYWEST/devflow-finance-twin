import Foundation

public struct SourceLocation: Codable, Hashable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct HTMLAttribute {
    public let name: String
    public let value: String?
    public let location: SourceLocation

    public init(name: String, value: String?, location: SourceLocation) {
        self.name = name
        self.value = value
        self.location = location
    }
}

public struct HTMLElement {
    public let tagName: String
    public let attributes: [HTMLAttribute]
    public let content: String?
    public let inlineStyle: String?
    public let location: SourceLocation
    public let nestingDepth: Int
    public let isSelfClosing: Bool

    public init(
        tagName: String,
        attributes: [HTMLAttribute],
        content: String?,
        inlineStyle: String?,
        location: SourceLocation,
        nestingDepth: Int,
        isSelfClosing: Bool
    ) {
        self.tagName = tagName
        self.attributes = attributes
        self.content = content
        self.inlineStyle = inlineStyle
        self.location = location
        self.nestingDepth = nestingDepth
        self.isSelfClosing = isSelfClosing
    }
}

public struct StyleBlock {
    public let content: String
    public let media: String?
    public let location: SourceLocation
    public let scopedSelector: String?

    public init(content: String, media: String?, location: SourceLocation, scopedSelector: String?) {
        self.content = content
        self.media = media
        self.location = location
        self.scopedSelector = scopedSelector
    }
}

public struct HTMLParseResult {
    public let elements: [HTMLElement]
    public let styleBlocks: [StyleBlock]
    public let inlineStyles: [HTMLElement]
    public let mediaQueries: [String]
    public let pseudoClasses: [String]
    public let errors: [ParseError]

    public init(
        elements: [HTMLElement],
        styleBlocks: [StyleBlock],
        inlineStyles: [HTMLElement],
        mediaQueries: [String],
        pseudoClasses: [String],
        errors: [ParseError]
    ) {
        self.elements = elements
        self.styleBlocks = styleBlocks
        self.inlineStyles = inlineStyles
        self.mediaQueries = mediaQueries
        self.pseudoClasses = pseudoClasses
        self.errors = errors
    }
}

public struct ParseError {
    public let message: String
    public let location: SourceLocation
    public let context: String?

    public init(message: String, location: SourceLocation, context: String?) {
        self.message = message
        self.location = location
        self.context = context
    }
}

public class HTMLParser {
    private let html: String
    private let filename: String
    private var position: Int = 0
    private var line: Int = 1
    private var column: Int = 1
    private var nestingDepth: Int = 0
    private var elements: [HTMLElement] = []
    private var styleBlocks: [StyleBlock] = []
    private var inlineStyles: [HTMLElement] = []
    private var mediaQueries: Set<String> = []
    private var pseudoClasses: Set<String> = []
    private var errors: [ParseError] = []
    private let voidElements = Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"])

    public init(html: String, filename: String = "unknown.html") {
        self.html = html
        self.filename = filename
    }

    public func parse() -> HTMLParseResult {
        while position < html.count {
            skipWhitespace()
            if position >= html.count { break }

            if peekChar() == "<" {
                parseTag()
            } else {
                skipTextContent()
            }
        }

        return HTMLParseResult(
            elements: elements,
            styleBlocks: styleBlocks,
            inlineStyles: inlineStyles,
            mediaQueries: Array(mediaQueries).sorted(),
            pseudoClasses: Array(pseudoClasses).sorted(),
            errors: errors
        )
    }

    private func parseTag() {
        let startLocation = currentLocation()
        consume("<")

        if peekChar() == "!" {
            parseComment()
            return
        }

        if peekChar() == "?" {
            parseProcessingInstruction()
            return
        }

        let isClosingTag = peekChar() == "/"
        if isClosingTag {
            consume("/")
            skipWhitespace()
            let tagName = parseIdentifier()
            skipWhitespace()
            if peekChar() == ">" {
                consume(">")
                nestingDepth = max(0, nestingDepth - 1)
            }
            return
        }

        let tagName = parseIdentifier()
        skipWhitespace()

        var attributes: [HTMLAttribute] = []
        while position < html.count && peekChar() != ">" && peekChar() != "/" {
            skipWhitespace()
            if peekChar() == ">" || peekChar() == "/" { break }

            if let attr = parseAttribute() {
                attributes.append(attr)
            }
        }

        let isSelfClosing = peekChar() == "/"
        if isSelfClosing {
            consume("/")
        }
        consume(">")

        var inlineStyle: String? = nil
        var contentStart = position
        if attributes.contains(where: { $0.name.lowercased() == "style" }) {
            inlineStyle = attributes.first(where: { $0.name.lowercased() == "style" })?.value
        }

        if inlineStyle != nil {
            inlineStyles.append(HTMLElement(
                tagName: tagName,
                attributes: attributes,
                content: nil,
                inlineStyle: inlineStyle,
                location: startLocation,
                nestingDepth: nestingDepth,
                isSelfClosing: isSelfClosing
            ))
        }

        let element = HTMLElement(
            tagName: tagName,
            attributes: attributes,
            content: nil,
            inlineStyle: inlineStyle,
            location: startLocation,
            nestingDepth: nestingDepth,
            isSelfClosing: isSelfClosing
        )
        elements.append(element)

        if tagName.lowercased() == "style" {
            parseStyleBlock(startLocation: startLocation)
        } else if !isSelfClosing && !voidElements.contains(tagName.lowercased()) {
            nestingDepth += 1
        }
    }

    private func parseStyleBlock(startLocation: SourceLocation) {
        let contentStart = position
        var content = ""
        var depth = 1

        while position < html.count && depth > 0 {
            if position + 6 < html.count && substring(position, position + 6) == "</style>" {
                depth -= 1
                if depth == 0 {
                    content = substring(contentStart, position)
                    consume("</style>")
                    break
                }
            }
            advance()
        }

        var media: String? = nil
        if content.contains("@media") {
            if let mediaMatch = extractMediaQuery(from: content) {
                media = mediaMatch
                mediaQueries.insert(mediaMatch)
            }
        }

        let styleBlock = StyleBlock(
            content: content.trimmingCharacters(in: .whitespaces),
            media: media,
            location: startLocation,
            scopedSelector: nil
        )
        styleBlocks.append(styleBlock)
    }

    private func parseAttribute() -> HTMLAttribute? {
        let startLocation = currentLocation()
        let name = parseIdentifier()

        if name.isEmpty { return nil }

        skipWhitespace()
        var value: String? = nil

        if peekChar() == "=" {
            consume("=")
            skipWhitespace()
            value = parseAttributeValue()
        }

        return HTMLAttribute(name: name, value: value, location: startLocation)
    }

    private func parseAttributeValue() -> String? {
        let quoteChar = peekChar()

        if quoteChar == "\"" || quoteChar == "'" {
            consume(String(quoteChar))
            var value = ""

            while position < html.count && peekChar() != quoteChar {
                value.append(advance())
            }

            if peekChar() == quoteChar {
                consume(String(quoteChar))
            } else {
                errors.append(ParseError(
                    message: "Unterminated attribute value",
                    location: currentLocation(),
                    context: value
                ))
            }

            return value
        } else {
            var value = ""
            while position < html.count && !isWhitespace(peekChar()) && peekChar() != ">" && peekChar() != "/" {
                value.append(advance())
            }
            return value.isEmpty ? nil : value
        }
    }

    private func parseComment() {
        consume("!")
        if peekChar() == "-" {
            consume("-")
            if peekChar() == "-" {
                consume("-")
            }
        }

        while position < html.count {
            if position + 3 < html.count && substring(position, position + 3) == "-->" {
                consume("-->")
                break
            }
            advance()
        }
    }

    private func parseProcessingInstruction() {
        consume("?")
        while position < html.count {
            if peekChar() == "?" && position + 1 < html.count && peekChar(offset: 1) == ">" {
                consume("?>")
                break
            }
            advance()
        }
    }

    private func parseIdentifier() -> String {
        var identifier = ""
        while position < html.count && (isIdentifierChar(peekChar())) {
            identifier.append(advance())
        }
        return identifier
    }

    private func skipTextContent() {
        while position < html.count && peekChar() != "<" {
            advance()
        }
    }

    private func extractMediaQuery(from css: String) -> String? {
        let pattern = "@media\\s+([^{]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = css as NSString
        let range = NSRange(location: 0, length: nsString.length)

        if let match = regex.firstMatch(in: css, options: [], range: range) {
            if let matchRange = Range(match.range(at: 1), in: css) {
                return String(css[matchRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func skipWhitespace() {
        while position < html.count && isWhitespace(peekChar()) {
            advance()
        }
    }

    private func isWhitespace(_ char: Character) -> Bool {
        return char.isWhitespace || char == "\n" || char == "\r" || char == "\t"
    }

    private func isIdentifierChar(_ char: Character) -> Bool {
        return char.isLetter || char.isNumber || char == "-" || char == "_" || char == ":"
    }

    private func peekChar(offset: Int = 0) -> Character {
        let index = position + offset
        guard index < html.count else { return Character(UnicodeScalar(0)!) }
        let idx = html.index(html.startIndex, offsetBy: index)
        return html[idx]
    }

    @discardableResult
    private func consume(_ expected: String) {
        for char in expected {
            if position < html.count && peekChar() == char {
                advance()
            }
        }
    }

    @discardableResult
    private func advance() -> Character {
        guard position < html.count else { return Character(UnicodeScalar(0)!) }
        let idx = html.index(html.startIndex, offsetBy: position)
        let char = html[idx]

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

    private func substring(_ start: Int, _ end: Int) -> String {
        guard start >= 0, end <= html.count, start <= end else { return "" }
        let startIdx = html.index(html.startIndex, offsetBy: start)
        let endIdx = html.index(html.startIndex, offsetBy: end)
        return String(html[startIdx..<endIdx])
    }
}
