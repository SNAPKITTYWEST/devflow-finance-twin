import Foundation

/// Represents a single palette token
struct PaletteToken: Codable {
    let id: String
    let name: String
    let semanticRole: String
    let appearance: AppearanceMode
    let value: String
    let originalValue: String
    let source: TokenSource
    let metadata: [String: String]

    enum TokenSource: String, Codable {
        case cssProperty
        case mediaQuery
        case computed
        case inherited
    }
}

/// Grouped palette structure
struct PaletteGroup: Codable {
    let name: String
    let role: String
    let appearance: String
    let tokens: [PaletteToken]
    let count: Int

    var isEmpty: Bool {
        return tokens.isEmpty
    }
}

/// Palette metadata
struct PaletteMetadata: Codable {
    let version: String
    let generated: Date
    let totalTokens: Int
    let uniqueValues: Int
    let appearances: [String]
    let roles: [String]
    let source: String
    let contentHash: String
}

/// Complete palette structure
struct DesignPalette: Codable {
    let metadata: PaletteMetadata
    let tokens: [PaletteToken]
    let groupedByRole: [String: [PaletteToken]]
    let groupedByAppearance: [String: [PaletteToken]]
    let groupedByRoleAndAppearance: [String: [String: [PaletteToken]]]
    let statistics: PaletteStatistics

    enum CodingKeys: String, CodingKey {
        case metadata
        case tokens
        case groupedByRole = "grouped_by_role"
        case groupedByAppearance = "grouped_by_appearance"
        case groupedByRoleAndAppearance = "grouped_by_role_and_appearance"
        case statistics
    }
}

/// Palette statistics
struct PaletteStatistics: Codable {
    let totalTokenCount: Int
    let uniqueValueCount: Int
    let roleDistribution: [String: Int]
    let appearanceDistribution: [String: Int]
    let tokenSourceDistribution: [String: Int]
    let highestUsedRole: String?
    let averageVariantsPerToken: Double
    let colorValueTypes: [String: Int]

    enum CodingKeys: String, CodingKey {
        case totalTokenCount = "total_token_count"
        case uniqueValueCount = "unique_value_count"
        case roleDistribution = "role_distribution"
        case appearanceDistribution = "appearance_distribution"
        case tokenSourceDistribution = "token_source_distribution"
        case highestUsedRole = "highest_used_role"
        case averageVariantsPerToken = "average_variants_per_token"
        case colorValueTypes = "color_value_types"
    }
}

/// Palette query options
struct PaletteQueryOptions: Codable {
    let filterByRole: String?
    let filterByAppearance: String?
    let filterBySource: String?
    let sortBy: SortField
    let limit: Int?

    enum SortField: String, Codable {
        case name
        case role
        case appearance
        case value
        case created
    }

    static let `default` = PaletteQueryOptions(
        filterByRole: nil,
        filterByAppearance: nil,
        filterBySource: nil,
        sortBy: .name,
        limit: nil
    )
}

/// Palette generation configuration
struct PaletteGeneratorConfig: Codable {
    let includeSources: Bool
    let includeMetadata: Bool
    let validateConsistency: Bool
    let normalizeColorValues: Bool
    let generateStatistics: Bool
    let groupByRole: Bool
    let groupByAppearance: Bool
    let version: String
    let source: String

    static let `default` = PaletteGeneratorConfig(
        includeSources: true,
        includeMetadata: true,
        validateConsistency: true,
        normalizeColorValues: true,
        generateStatistics: true,
        groupByRole: true,
        groupByAppearance: true,
        version: "1.0.0",
        source: "apple-design-parser"
    )
}

/// Main palette generation engine
final class PaletteGenerator {
    private let config: PaletteGeneratorConfig
    private var tokens: [PaletteToken] = []
    private var palette: DesignPalette?
    private var validationIssues: [String] = []
    private var generationLog: [String] = []

    init(config: PaletteGeneratorConfig = .default) {
        self.config = config
    }

    /// Add a token to the palette
    func addToken(
        id: String,
        name: String,
        semanticRole: String,
        appearance: AppearanceMode,
        value: String,
        originalValue: String,
        source: PaletteToken.TokenSource,
        metadata: [String: String] = [:]
    ) {
        let token = PaletteToken(
            id: id,
            name: name,
            semanticRole: semanticRole,
            appearance: appearance,
            value: value,
            originalValue: originalValue,
            source: source,
            metadata: metadata
        )

        tokens.append(token)
        logGeneration("Added token: \(id)")
    }

    /// Add multiple tokens at once
    func addTokens(_ newTokens: [PaletteToken]) {
        tokens.append(contentsOf: newTokens)
        logGeneration("Added \(newTokens.count) tokens")
    }

    /// Generate the complete palette
    func generatePalette() -> DesignPalette {
        logGeneration("Starting palette generation with \(tokens.count) tokens")

        // Validate tokens
        if config.validateConsistency {
            validateTokenConsistency()
        }

        // Normalize values
        if config.normalizeColorValues {
            normalizeTokenValues()
        }

        // Build grouped structures
        let groupedByRole = buildGroupByRole()
        let groupedByAppearance = buildGroupByAppearance()
        let groupedByRoleAndAppearance = buildGroupByRoleAndAppearance()

        // Generate statistics
        let statistics = generateStatistics(
            groupedByRole: groupedByRole,
            groupedByAppearance: groupedByAppearance
        )

        // Generate metadata
        let metadata = generateMetadata(statistics: statistics)

        let generatedPalette = DesignPalette(
            metadata: metadata,
            tokens: tokens,
            groupedByRole: groupedByRole,
            groupedByAppearance: groupedByAppearance,
            groupedByRoleAndAppearance: groupedByRoleAndAppearance,
            statistics: statistics
        )

        self.palette = generatedPalette
        logGeneration("Palette generation complete")

        return generatedPalette
    }

    /// Group tokens by semantic role
    private func buildGroupByRole() -> [String: [PaletteToken]] {
        var grouped: [String: [PaletteToken]] = [:]

        for token in tokens {
            let role = token.semanticRole
            grouped[role, default: []].append(token)
        }

        // Sort each group
        for key in grouped.keys {
            grouped[key]?.sort { $0.name < $1.name }
        }

        logGeneration("Grouped \(tokens.count) tokens into \(grouped.keys.count) roles")
        return grouped
    }

    /// Group tokens by appearance
    private func buildGroupByAppearance() -> [String: [PaletteToken]] {
        var grouped: [String: [PaletteToken]] = [:]

        for token in tokens {
            let appearance = token.appearance.rawValue
            grouped[appearance, default: []].append(token)
        }

        // Sort each group
        for key in grouped.keys {
            grouped[key]?.sort { $0.name < $1.name }
        }

        logGeneration("Grouped \(tokens.count) tokens into \(grouped.keys.count) appearances")
        return grouped
    }

    /// Group tokens by role and appearance
    private func buildGroupByRoleAndAppearance() -> [String: [String: [PaletteToken]]] {
        var grouped: [String: [String: [PaletteToken]]] = [:]

        for token in tokens {
            let role = token.semanticRole
            let appearance = token.appearance.rawValue

            if grouped[role] == nil {
                grouped[role] = [:]
            }

            grouped[role]?[appearance, default: []].append(token)
        }

        // Sort each subgroup
        for roleKey in grouped.keys {
            for appearanceKey in grouped[roleKey]?.keys ?? [] {
                grouped[roleKey]?[appearanceKey]?.sort { $0.name < $1.name }
            }
        }

        logGeneration("Grouped \(tokens.count) tokens into role-appearance pairs")
        return grouped
    }

    /// Validate token consistency
    private func validateTokenConsistency() {
        var issues: [String] = []

        // Check for duplicate IDs
        let ids = tokens.map { $0.id }
        let uniqueIds = Set(ids)
        if ids.count != uniqueIds.count {
            issues.append("Found duplicate token IDs")
        }

        // Check for missing semantic roles
        let tokensWithoutRole = tokens.filter { $0.semanticRole.isEmpty }
        if !tokensWithoutRole.isEmpty {
            issues.append("Found \(tokensWithoutRole.count) tokens without semantic role")
        }

        // Check for invalid color values
        let invalidValues = tokens.filter { !isValidColorValue($0.value) }
        if !invalidValues.isEmpty {
            issues.append("Found \(invalidValues.count) tokens with invalid color values")
        }

        // Check for appearance coverage
        let roles = Set(tokens.map { $0.semanticRole })
        let appearances = Set(tokens.map { $0.appearance.rawValue })

        for role in roles {
            for appearance in appearances {
                let matching = tokens.filter { $0.semanticRole == role && $0.appearance.rawValue == appearance }
                if matching.isEmpty {
                    issues.append("Missing coverage: role '\(role)' has no tokens in appearance '\(appearance)'")
                }
            }
        }

        validationIssues = issues
        logGeneration("Validation found \(issues.count) issues")
    }

    /// Normalize color values
    private func normalizeTokenValues() {
        for i in 0..<tokens.count {
            let normalized = normalizeColorValue(tokens[i].value)
            tokens[i] = PaletteToken(
                id: tokens[i].id,
                name: tokens[i].name,
                semanticRole: tokens[i].semanticRole,
                appearance: tokens[i].appearance,
                value: normalized,
                originalValue: tokens[i].originalValue,
                source: tokens[i].source,
                metadata: tokens[i].metadata
            )
        }
        logGeneration("Normalized \(tokens.count) color values")
    }

    /// Normalize a single color value
    private func normalizeColorValue(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespaces)

        // Convert common formats
        if normalized.lowercased().hasPrefix("rgb") {
            // Keep RGB as-is or normalize
            normalized = normalized.lowercased()
        } else if normalized.hasPrefix("#") {
            // Uppercase hex colors
            normalized = normalized.uppercased()
        } else if normalized.lowercased().contains("hsl") {
            // Keep HSL as-is
            normalized = normalized.lowercased()
        }

        return normalized
    }

    /// Check if a color value is valid
    private func isValidColorValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return false
        }

        if trimmed.hasPrefix("#") {
            return trimmed.count >= 4 && trimmed.count <= 9
        }

        if trimmed.lowercased().hasPrefix("rgb") {
            return trimmed.contains("(") && trimmed.contains(")")
        }

        if trimmed.lowercased().hasPrefix("hsl") {
            return trimmed.contains("(") && trimmed.contains(")")
        }

        if trimmed.lowercased().hasPrefix("hsl") {
            return trimmed.contains("(") && trimmed.contains(")")
        }

        // Named colors
        let namedColors = ["white", "black", "red", "green", "blue", "transparent"]
        if namedColors.contains(trimmed.lowercased()) {
            return true
        }

        return true
    }

    /// Generate palette statistics
    private func generateStatistics(
        groupedByRole: [String: [PaletteToken]],
        groupedByAppearance: [String: [PaletteToken]]
    ) -> PaletteStatistics {
        // Count unique values
        let uniqueValues = Set(tokens.map { $0.value }).count

        // Build role distribution
        var roleDistribution: [String: Int] = [:]
        for (role, roleTokens) in groupedByRole {
            roleDistribution[role] = roleTokens.count
        }

        // Build appearance distribution
        var appearanceDistribution: [String: Int] = [:]
        for (appearance, appearanceTokens) in groupedByAppearance {
            appearanceDistribution[appearance] = appearanceTokens.count
        }

        // Build source distribution
        var sourceDistribution: [String: Int] = [:]
        for token in tokens {
            sourceDistribution[token.source.rawValue, default: 0] += 1
        }

        // Find highest used role
        let highestUsedRole = roleDistribution.max(by: { $0.value < $1.value })?.key

        // Calculate average variants per token
        var tokenVariantMap: [String: Int] = [:]
        for token in tokens {
            tokenVariantMap[token.id, default: 0] += 1
        }
        let averageVariants = tokenVariantMap.isEmpty ? 0.0 : Double(tokens.count) / Double(tokenVariantMap.count)

        // Count color value types
        var colorValueTypes: [String: Int] = [:]
        for token in tokens {
            let type: String
            if token.value.hasPrefix("#") {
                type = "hex"
            } else if token.value.lowercased().hasPrefix("rgb") {
                type = "rgb"
            } else if token.value.lowercased().hasPrefix("hsl") {
                type = "hsl"
            } else {
                type = "named"
            }
            colorValueTypes[type, default: 0] += 1
        }

        return PaletteStatistics(
            totalTokenCount: tokens.count,
            uniqueValueCount: uniqueValues,
            roleDistribution: roleDistribution,
            appearanceDistribution: appearanceDistribution,
            tokenSourceDistribution: sourceDistribution,
            highestUsedRole: highestUsedRole,
            averageVariantsPerToken: averageVariants,
            colorValueTypes: colorValueTypes
        )
    }

    /// Generate palette metadata
    private func generateMetadata(statistics: PaletteStatistics) -> PaletteMetadata {
        let roles = Array(statistics.roleDistribution.keys).sorted()
        let appearances = Array(statistics.appearanceDistribution.keys).sorted()

        // Generate content hash
        let contentString = tokens.map { $0.id }.sorted().joined(separator: ",")
        let contentHash = String(format: "%02x", contentString.hashValue & 0xFFFFFFFF)

        return PaletteMetadata(
            version: config.version,
            generated: Date(),
            totalTokens: tokens.count,
            uniqueValues: statistics.uniqueValueCount,
            appearances: appearances,
            roles: roles,
            source: config.source,
            contentHash: contentHash
        )
    }

    /// Query palette with options
    func queryPalette(_ options: PaletteQueryOptions) -> [PaletteToken] {
        var results = tokens

        // Apply filters
        if let roleFilter = options.filterByRole {
            results = results.filter { $0.semanticRole == roleFilter }
        }

        if let appearanceFilter = options.filterByAppearance {
            results = results.filter { $0.appearance.rawValue == appearanceFilter }
        }

        if let sourceFilter = options.filterBySource {
            results = results.filter { $0.source.rawValue == sourceFilter }
        }

        // Sort
        switch options.sortBy {
        case .name:
            results.sort { $0.name < $1.name }
        case .role:
            results.sort { $0.semanticRole < $1.semanticRole }
        case .appearance:
            results.sort { $0.appearance.rawValue < $1.appearance.rawValue }
        case .value:
            results.sort { $0.value < $1.value }
        case .created:
            // Preserve insertion order (already sorted)
            break
        }

        // Apply limit
        if let limit = options.limit {
            results = Array(results.prefix(limit))
        }

        logGeneration("Query returned \(results.count) tokens")
        return results
    }

    /// Get tokens for a specific role
    func getTokensByRole(_ role: String) -> [PaletteToken] {
        let options = PaletteQueryOptions(
            filterByRole: role,
            filterByAppearance: nil,
            filterBySource: nil,
            sortBy: .name,
            limit: nil
        )
        return queryPalette(options)
    }

    /// Get tokens for a specific appearance
    func getTokensByAppearance(_ appearance: AppearanceMode) -> [PaletteToken] {
        let options = PaletteQueryOptions(
            filterByRole: nil,
            filterByAppearance: appearance.rawValue,
            filterBySource: nil,
            sortBy: .name,
            limit: nil
        )
        return queryPalette(options)
    }

    /// Get tokens for a specific role and appearance
    func getTokensByRoleAndAppearance(_ role: String, appearance: AppearanceMode) -> [PaletteToken] {
        let options = PaletteQueryOptions(
            filterByRole: role,
            filterByAppearance: appearance.rawValue,
            filterBySource: nil,
            sortBy: .name,
            limit: nil
        )
        return queryPalette(options)
    }

    /// Build serializable palette structure
    func buildSerializableStructure() -> [String: Any] {
        var structure: [String: Any] = [:]

        if let palette = palette {
            structure["metadata"] = [
                "version": palette.metadata.version,
                "generated": ISO8601DateFormatter().string(from: palette.metadata.generated),
                "total_tokens": palette.metadata.totalTokens,
                "unique_values": palette.metadata.uniqueValues,
                "appearances": palette.metadata.appearances,
                "roles": palette.metadata.roles,
                "source": palette.metadata.source,
                "content_hash": palette.metadata.contentHash
            ]

            var tokenArray: [[String: Any]] = []
            for token in palette.tokens {
                tokenArray.append([
                    "id": token.id,
                    "name": token.name,
                    "role": token.semanticRole,
                    "appearance": token.appearance.rawValue,
                    "value": token.value,
                    "source": token.source.rawValue
                ])
            }
            structure["tokens"] = tokenArray

            structure["statistics"] = [
                "total": palette.statistics.totalTokenCount,
                "unique_values": palette.statistics.uniqueValueCount,
                "role_distribution": palette.statistics.roleDistribution,
                "appearance_distribution": palette.statistics.appearanceDistribution
            ]
        }

        return structure
    }

    /// Export palette as JSON
    func exportAsJSON() -> Data? {
        if let palette = palette {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(palette)
        }
        return nil
    }

    /// Import palette from JSON
    func importFromJSON(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let imported = try? decoder.decode(DesignPalette.self, from: data) {
            self.palette = imported
            self.tokens = imported.tokens
            logGeneration("Imported palette with \(imported.tokens.count) tokens")
            return true
        }
        return false
    }

    /// Get all tokens
    func getAllTokens() -> [PaletteToken] {
        return tokens
    }

    /// Get token by ID
    func getTokenById(_ id: String) -> PaletteToken? {
        return tokens.first { $0.id == id }
    }

    /// Get validation issues
    func getValidationIssues() -> [String] {
        return validationIssues
    }

    /// Get generation log
    func getGenerationLog() -> [String] {
        return generationLog
    }

    /// Clear generation log
    func clearGenerationLog() {
        generationLog.removeAll()
    }

    /// Log a generation step
    private func logGeneration(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        generationLog.append("[\(timestamp)] \(message)")
    }

    /// Clear all tokens
    func clearTokens() {
        tokens.removeAll()
        palette = nil
        validationIssues.removeAll()
        logGeneration("Cleared all tokens")
    }

    /// Get current palette
    func getCurrentPalette() -> DesignPalette? {
        return palette
    }

    /// Get token count
    var tokenCount: Int {
        return tokens.count
    }

    /// Check if palette has been generated
    var isGenerated: Bool {
        return palette != nil
    }
}

// MARK: - Palette Generation Utilities

extension DesignPalette {
    /// Find a token by name
    func findTokenByName(_ name: String) -> PaletteToken? {
        return tokens.first { $0.name == name }
    }

    /// Find tokens by partial name match
    func findTokensByNamePattern(_ pattern: String) -> [PaletteToken] {
        return tokens.filter { $0.name.lowercased().contains(pattern.lowercased()) }
    }

    /// Get all unique color values
    var uniqueColorValues: [String] {
        return Array(Set(tokens.map { $0.value })).sorted()
    }

    /// Export palette as human-readable format
    func exportAsReadable() -> String {
        var output = "# Design Palette\n\n"
        output += "Generated: \(ISO8601DateFormatter().string(from: metadata.generated))\n"
        output += "Total Tokens: \(metadata.totalTokens)\n"
        output += "Unique Values: \(metadata.uniqueValues)\n\n"

        for (role, roleTokens) in groupedByRole.sorted(by: { $0.key < $1.key }) {
            output += "## \(role)\n"
            for token in roleTokens.sorted(by: { $0.name < $1.name }) {
                output += "- \(token.name): \(token.value) (\(token.appearance.rawValue))\n"
            }
            output += "\n"
        }

        return output
    }
}
