package com.monga.app.chat

import com.monga.app.data.local.CoreMemory

internal object CoreMemoryBudgetPolicy {

    const val DEFAULT_TOKEN_BUDGET = 1024

    fun build(
        memories: List<CoreMemory>,
        tokenBudget: Int = DEFAULT_TOKEN_BUDGET,
        tokenCounter: (String) -> Int,
    ): String {
        if (memories.isEmpty() || tokenBudget <= 0) {
            return ""
        }

        val prioritized = memories.sortedWith(
            compareByDescending<CoreMemory> { it.updatedAt }
                .thenByDescending { it.createdAt }
                .thenByDescending { it.id }
        )

        val selected = mutableListOf<CoreMemory>()

        for (memory in prioritized) {
            val candidate = selected + memory
            val rendered = render(candidate)

            val tokenCount = tokenCounter(rendered)

            if (tokenCount <= 0) {
                throw IllegalStateException(
                    "핵심 기억의 토큰 수를 확인하지 못했습니다."
                )
            }

            if (tokenCount <= tokenBudget) {
                selected += memory
            }
        }

        return render(selected)
    }

    private fun render(
        memories: List<CoreMemory>,
    ): String =
        memories.joinToString(separator = "\n") { memory ->
            "- ${memory.content}"
        }
}
