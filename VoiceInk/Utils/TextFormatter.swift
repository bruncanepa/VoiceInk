import Foundation
import os

struct TextFormatter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TextFormatter")

    /// Applies custom formatting to text, including removal of trailing punctuation while preserving any trailing space
    /// - Parameters:
    ///   - text: The text to process
    ///   - removeTrailingPeriod: Whether to remove trailing periods (.) - defaults to true
    ///   - removeInvertedQuestionMark: Whether to remove trailing inverted question marks (¿) - defaults to true
    /// - Returns: Text with custom formatting applied, space preserved
    ///
    /// Examples:
    /// - "Hello world. " → "Hello world " (if removeTrailingPeriod enabled)
    /// - "Hello world." → "Hello world" (if removeTrailingPeriod enabled)
    /// - "Hello world " → "Hello world "
    /// - "Hola mundo¿ " → "Hola mundo " (if removeInvertedQuestionMark enabled)
    /// - "Hola mundo¿" → "Hola mundo" (if removeInvertedQuestionMark enabled)
    static func customFormat(from text: String, removeTrailingPeriod: Bool = true, removeInvertedQuestionMark: Bool = true) -> String {
        var result = text

        logger.debug("🔍 customFormat - INPUT: '\(text)'")
        logger.debug("🔍 Last 5 chars (escaped): '\(text.suffix(5).debugDescription)'")
        logger.debug("🔍 Settings - Remove period: \(removeTrailingPeriod), Remove ¿: \(removeInvertedQuestionMark)")

        var removedSomething = false

        // Handle ". " pattern - remove period but keep space
        if removeTrailingPeriod && result.hasSuffix(". ") {
            logger.debug("✅ Found '. ' pattern, removing period")
            result.removeLast(2) // Remove ". "
            result += " "        // Add back just the space
            removedSomething = true
        }
        // Handle trailing "." without space
        else if removeTrailingPeriod && result.last == "." {
            logger.debug("✅ Found '.' at end, removing")
            result.removeLast()
            removedSomething = true
        }

        // Now check for inverted question mark anywhere in the text
        if removeInvertedQuestionMark && result.contains("¿") {
            logger.debug("✅ Found '¿' in text, removing all occurrences")
            result = result.replacingOccurrences(of: "¿", with: "")
            removedSomething = true
        }

        if !removedSomething {
            logger.debug("❌ No applicable trailing punctuation found or removal disabled")
        }

        logger.debug("🔍 customFormat - OUTPUT: '\(result)'")

        return result
    }
}
