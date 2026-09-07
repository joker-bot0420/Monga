package com.monga.app.inference

class LeadingThinkBlockFilter {

    private enum class State {
        CHECKING,
        SUPPRESSING,
        TRIMMING,
        PASSTHROUGH,
    }

    private var state = State.CHECKING
    private val buffer = StringBuilder()

    fun accept(text: String): String {
        if (text.isEmpty()) {
            return ""
        }

        if (state == State.PASSTHROUGH) {
            return text
        }

        if (state == State.TRIMMING) {
            return trimLeadingNewlines(text)
        }

        buffer.append(text)

        if (state == State.CHECKING) {
            val openTag = "<think>"
            val current = buffer.toString()

            if (
                current.length < openTag.length &&
                openTag.startsWith(current)
            ) {
                return ""
            }

            if (current.startsWith(openTag)) {
                state = State.SUPPRESSING
            } else {
                state = State.PASSTHROUGH

                val result = buffer.toString()
                buffer.clear()

                return result
            }
        }

        if (state == State.SUPPRESSING) {
            val closeTag = "</think>"
            val closeIndex = buffer.indexOf(closeTag)

            if (closeIndex < 0) {
                return ""
            }

            val afterThink =
                buffer.substring(
                    closeIndex + closeTag.length
                )

            buffer.clear()
            state = State.TRIMMING

            return trimLeadingNewlines(afterThink)
        }

        return ""
    }

    private fun trimLeadingNewlines(text: String): String {
        val trimmed =
            text.trimStart('\r', '\n')

        if (trimmed.isEmpty()) {
            return ""
        }

        state = State.PASSTHROUGH
        return trimmed
    }

    fun reset() {
        state = State.CHECKING
        buffer.clear()
    }
}
