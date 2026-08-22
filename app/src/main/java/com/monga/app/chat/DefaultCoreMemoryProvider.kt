package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class DefaultCoreMemoryProvider(
    private val coreMemories: Flow<List<CoreMemory>>,
) : CoreMemoryProvider {

    override suspend fun buildMemory(): String =
        coreMemories.first()
            .joinToString(separator = "\n") { memory ->
                "- ${memory.content}"
            }
}
