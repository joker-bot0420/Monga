package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class DefaultCoreMemoryProvider(
    private val coreMemories: Flow<List<CoreMemory>>,
    private val tokenCounter: (String) -> Int,
    private val selector: CoreMemorySelector = DefaultCoreMemorySelector,
    private val tokenBudget: Int =
        CoreMemoryBudgetPolicy.DEFAULT_TOKEN_BUDGET,
) : CoreMemoryProvider {

    override suspend fun buildMemory(userMessage: String): String {
        val selected = selector.select(
            userMessage = userMessage,
            memories = coreMemories.first(),
        )

        if (selected.isEmpty()) {
            return ""
        }

        return CoreMemoryBudgetPolicy.build(
            memories = selected.map { memory ->
                memory.copy(
                    content = UserMemoryFormatter.format(memory.content),
                )
            },
            tokenBudget = tokenBudget,
            tokenCounter = tokenCounter,
        )
    }
}
