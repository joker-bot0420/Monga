package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultCoreMemoryProviderTest {

    @Test
    fun buildsSelectedMemoryWithinConfiguredBudget() = runBlocking {
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
            tokenCounter = { text -> text.length },
            selector = CoreMemorySelector { _, memories -> memories },
            tokenBudget = 5,
        )

        val result = provider.buildMemory("query")

        assertEquals(
            "- new",
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
            selector = CoreMemorySelector { _, values -> values },
            tokenBudget = 100,
        )

        assertEquals("- original", provider.buildMemory("query"))

        memories.value = listOf(
            CoreMemory(
                id = 1,
                content = "revised",
                createdAt = 100L,
                updatedAt = 200L,
            )
        )

        assertEquals("- revised", provider.buildMemory("query"))

        memories.value = emptyList()

        assertEquals("", provider.buildMemory("query"))
    }

    @Test
    fun passesQueryToSelectorAndRendersOnlySelectedMemories() = runBlocking {
        val values = listOf(
            CoreMemory(1, "나는 포항에 산다.", 100L, 100L),
            CoreMemory(2, "내가 좋아하는 음료는 녹차다.", 200L, 200L),
        )
        var receivedQuery = ""

        val provider = DefaultCoreMemoryProvider(
            coreMemories = flowOf(values),
            tokenCounter = { text -> text.length },
            selector = CoreMemorySelector { query, memories ->
                receivedQuery = query
                memories.filter { it.id == 2L }
            },
            tokenBudget = 200,
        )

        val result = provider.buildMemory("내가 좋아하는 음료가 뭐였지?")

        assertEquals("내가 좋아하는 음료가 뭐였지?", receivedQuery)
        assertEquals("- 사용자가 좋아하는 음료는 녹차다.", result)
    }
}
