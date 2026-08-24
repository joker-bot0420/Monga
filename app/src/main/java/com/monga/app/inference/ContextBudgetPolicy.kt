package com.monga.app.inference

internal object ContextBudgetPolicy {

    fun dropOldestTurn(
        messages: List<InferenceMessage>,
    ): List<InferenceMessage> {
        if (messages.size <= 1) {
            return messages
        }

        val result = messages.toMutableList()

        val removableIndex =
            (0 until result.lastIndex)
                .firstOrNull {
                    result[it].role != InferenceRole.SYSTEM
                }
                ?: return messages

        val removed = result.removeAt(removableIndex)

        if (
            removed.role == InferenceRole.USER &&
            removableIndex < result.lastIndex &&
            result[removableIndex].role == InferenceRole.ASSISTANT
        ) {
            result.removeAt(removableIndex)
        }

        return result
    }
}
