package com.monga.app.chat

internal object GroundedResponsePrefixSanitizer {

    private val standalonePrefix = Regex(
        pattern = """^\s*(응|아니)(?=\s|[.!?,~…]|$)[.!?,~…\s]*"""
    )

    private val standalonePrefixOnly = Regex(
        pattern = """^\s*(응|아니)(?=\s|[.!?,~…]|$)[.!?,~…\s]*$"""
    )

    private val possiblePrefixes = listOf("응", "아니")

    fun sanitizeStreaming(text: String): String {
        if (text.isEmpty()) {
            return text
        }

        val trimmed = text.trimStart()
        if (trimmed.isEmpty()) {
            return ""
        }

        if (possiblePrefixes.any { prefix -> prefix.startsWith(trimmed) }) {
            return ""
        }

        if (standalonePrefixOnly.matches(text)) {
            return ""
        }

        return standalonePrefix.replaceFirst(text, "")
    }

    fun sanitizeFinal(text: String): String =
        standalonePrefix.replaceFirst(text, "")
}
