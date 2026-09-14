package com.monga.app.chat

import com.monga.app.data.local.CoreMemory

fun interface CoreMemorySelector {
    fun select(
        userMessage: String,
        memories: List<CoreMemory>,
    ): List<CoreMemory>
}

internal object DefaultCoreMemorySelector : CoreMemorySelector {

    private const val MAX_SELECTED_MEMORIES = 3
    private const val MIN_SCORE = 4

    private data class ScoredMemory(
        val memory: CoreMemory,
        val score: Int,
    )

    override fun select(
        userMessage: String,
        memories: List<CoreMemory>,
    ): List<CoreMemory> {
        if (userMessage.isBlank() || memories.isEmpty()) {
            return emptyList()
        }

        return memories
            .map { memory ->
                ScoredMemory(
                    memory = memory,
                    score = MemoryRelevanceScorer.score(
                        query = userMessage,
                        memory = memory.content,
                    ),
                )
            }
            .filter { scored -> scored.score >= MIN_SCORE }
            .sortedWith(
                compareByDescending<ScoredMemory> { it.score }
                    .thenByDescending { it.memory.updatedAt }
                    .thenByDescending { it.memory.createdAt }
                    .thenByDescending { it.memory.id }
            )
            .take(MAX_SELECTED_MEMORIES)
            .map { scored -> scored.memory }
    }
}
