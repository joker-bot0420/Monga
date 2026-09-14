package com.monga.app.chat

internal object UserMemoryFormatter {

    private val replacements = listOf(
        tokenRegex("나는") to "사용자는",
        tokenRegex("저는") to "사용자는",
        tokenRegex("내가") to "사용자가",
        tokenRegex("제가") to "사용자가",
        tokenRegex("나의") to "사용자의",
        tokenRegex("저의") to "사용자의",
    )

    fun format(content: String): String {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) return trimmed

        return replacements.fold(trimmed) { current, (pattern, replacement) ->
            pattern.replace(current, replacement)
        }
    }

    private fun tokenRegex(token: String): Regex =
        Regex(
            "(?<![가-힣A-Za-z0-9])${Regex.escape(token)}(?![가-힣A-Za-z0-9])"
        )
}
