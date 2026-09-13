package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class DefaultCoreMemoryProvider(
    private val coreMemories: Flow<List<CoreMemory>>,
    private val tokenCounter: (String) -> Int,
    private val tokenBudget: Int =
        CoreMemoryBudgetPolicy.DEFAULT_TOKEN_BUDGET,
) : CoreMemoryProvider {

    override suspend fun buildMemory(): String {
        val formattedMemories = coreMemories.first().map { memory ->
            memory.copy(
                content = UserMemoryFormatter.format(memory.content),
            )
        }

        return CoreMemoryBudgetPolicy.build(
            memories = formattedMemories,
            tokenBudget = tokenBudget,
            tokenCounter = tokenCounter,
        )
    }
}
