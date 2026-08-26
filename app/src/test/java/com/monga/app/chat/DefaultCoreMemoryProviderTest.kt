package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
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
            tokenCounter = { text -> text.length },
            tokenBudget = 5,
        )

        val result = provider.buildMemory()

        assertEquals(
            "- new",
            result,
        )
    }
}
