package com.monga.app.chat

internal object UserMemoryFormatter {

    fun format(content: String): String {
        val normalized = normalizeSubject(content.trim())
        return "사용자에 대한 사실: $normalized"
    }

    private fun normalizeSubject(content: String): String {
        val replacements = listOf(
            "나는 " to "사용자는 ",
            "저는 " to "사용자는 ",
            "내가 " to "사용자가 ",
            "제가 " to "사용자가 ",
            "나의 " to "사용자의 ",
            "저의 " to "사용자의 ",
        )

        val replacement = replacements.firstOrNull { (prefix, _) ->
            content.startsWith(prefix)
        } ?: return content

        return replacement.second + content.removePrefix(replacement.first)
    }
}
