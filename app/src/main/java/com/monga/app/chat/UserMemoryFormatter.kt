package com.monga.app.chat

internal object UserMemoryFormatter {

    fun format(content: String): String {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) return trimmed

        val replacements = listOf(
            "나는 " to "사용자는 ",
            "저는 " to "사용자는 ",
            "내가 " to "사용자가 ",
            "제가 " to "사용자가 ",
            "나의 " to "사용자의 ",
            "저의 " to "사용자의 ",
        )

        val replacement = replacements.firstOrNull { (prefix, _) ->
            trimmed.startsWith(prefix)
        } ?: return trimmed

        return replacement.second + trimmed.removePrefix(replacement.first)
    }
}
