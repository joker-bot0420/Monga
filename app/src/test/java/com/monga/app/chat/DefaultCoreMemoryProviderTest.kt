package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlinx.coroutines.flow.MutableStateFlow

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
            tokenCounter = { text -> text.length },
            tokenBudget = 5,
        )

        val result = provider.buildMemory()

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
            tokenBudget = 100,
        )

        assertEquals("- original", provider.buildMemory())

        // 같은 Provider 인스턴스에서 기억이 수정된 상황을 재현한다.
        memories.value = listOf(
            CoreMemory(
                id = 1,
                content = "revised",
                createdAt = 100L,
                updatedAt = 200L,
            )
        )

        assertEquals("- revised", provider.buildMemory())

        // 삭제된 기억도 다음 호출에 반영되어야 한다.
        memories.value = emptyList()

        assertEquals("", provider.buildMemory())
    }

}
