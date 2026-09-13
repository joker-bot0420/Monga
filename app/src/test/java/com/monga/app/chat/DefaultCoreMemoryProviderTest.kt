package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultCoreMemoryProviderTest {

    @Test
    fun buildsMemoryWithinConfiguredBudget() = runBlocking {
        val provider = DefaultCoreMemoryProvider(
            coreMemories = flowOf(
                listOf(
                    CoreMemory(
                        id = 1,
                        content = "old",
                        createdAt = 100,
                        updatedAt = 100,
                    ),
                    CoreMemory(
                        id = 2,
                        content = "new",
                        createdAt = 200,
                        updatedAt = 200,
                    ),
                )
            ),
            tokenCounter = { text -> text.lineSequence().count() },
            tokenBudget = 1,
        )

        val result = provider.buildMemory()

        assertEquals(
            "- 사용자에 대한 사실: new",
            result,
        )
    }

    @Test
    fun rebuildsMemoryFromLatestFlowValue() = runBlocking {
        val memories = MutableStateFlow(
            listOf(
                CoreMemory(
                    id = 1,
                    content = "original",
                    createdAt = 100L,
                    updatedAt = 100L,
                )
            )
        )

        val provider = DefaultCoreMemoryProvider(
            coreMemories = memories,
            tokenCounter = { text -> text.length },
            tokenBudget = 100,
        )

        assertEquals(
            "- 사용자에 대한 사실: original",
            provider.buildMemory(),
        )

        memories.value = listOf(
            CoreMemory(
                id = 1,
                content = "revised",
                createdAt = 100L,
                updatedAt = 200L,
            )
        )

        assertEquals(
            "- 사용자에 대한 사실: revised",
            provider.buildMemory(),
        )

        memories.value = emptyList()

        assertEquals("", provider.buildMemory())
    }
}
