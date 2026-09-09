package com.monga.app.data.local

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

@RunWith(AndroidJUnit4::class)
class MongaDaoTest {

    private lateinit var database: MongaDatabase
    private lateinit var dao: MongaDao

    @Before
    fun setUp() {
        val context =
            InstrumentationRegistry
                .getInstrumentation()
                .targetContext

        database = Room.inMemoryDatabaseBuilder(
            context,
            MongaDatabase::class.java,
        )
            .allowMainThreadQueries()
            .build()

        dao = database.dao()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun episodicMemoriesAreStoredAndObservedNewestFirst() = runBlocking {
        dao.insertEpisodicMemory(
            EpisodicMemory(
                title = "older",
                content = "first event",
                occurredAt = 100L,
                createdAt = 100L,
            )
        )

        dao.insertEpisodicMemory(
            EpisodicMemory(
                title = "newer",
                content = "second event",
                occurredAt = 200L,
                createdAt = 200L,
            )
        )

        val memories =
            dao.observeEpisodicMemories().first()

        assertEquals(2, memories.size)
        assertEquals("newer", memories[0].title)
        assertEquals("older", memories[1].title)
    }

    @Test
    fun episodicMemoriesByDateUseStartInclusiveEndExclusiveAndNewestFirst() =
        runBlocking {
            dao.insertEpisodicMemory(
                EpisodicMemory(
                    title = "before",
                    content = "before range",
                    occurredAt = 999L,
                    createdAt = 1L,
                )
            )

            dao.insertEpisodicMemory(
                EpisodicMemory(
                    title = "start",
                    content = "start boundary",
                    occurredAt = 1000L,
                    createdAt = 2L,
                )
            )

            dao.insertEpisodicMemory(
                EpisodicMemory(
                    title = "inside",
                    content = "inside range",
                    occurredAt = 1999L,
                    createdAt = 3L,
                )
            )

            dao.insertEpisodicMemory(
                EpisodicMemory(
                    title = "end",
                    content = "end boundary",
                    occurredAt = 2000L,
                    createdAt = 4L,
                )
            )

            val memories =
                dao.observeEpisodicMemoriesByDate(
                    start = 1000L,
                    end = 2000L,
                ).first()

            assertEquals(2, memories.size)
            assertEquals("inside", memories[0].title)
            assertEquals("start", memories[1].title)
        }

    @Test
    fun coreMemoriesAreInsertedUpdatedDeletedAndObserved() = runBlocking {
        val updates = Channel<List<CoreMemory>>(Channel.RENDEZVOUS)

        val observer = launch {
            dao.observeCoreMemories().collect { memories ->
                updates.send(memories)
            }
        }

        suspend fun nextUpdate(): List<CoreMemory> =
            withTimeout(5_000L) {
                updates.receive()
            }

        try {
            // 처음에는 기억이 없다.
            assertEquals(
                emptyList<CoreMemory>(),
                nextUpdate(),
            )

            // 추가: 생성된 ID와 저장된 내용이 Flow에 반영된다.
            val original = CoreMemory(
                content = "first memory",
                createdAt = 100L,
                updatedAt = 100L,
            )

            val id = dao.insertCoreMemory(original)
            val saved = original.copy(id = id)

            assertEquals(
                listOf(saved),
                nextUpdate(),
            )

            // 수정: ID와 생성 시각을 유지하고 내용과 수정 시각을 갱신한다.
            val revised = saved.copy(
                content = "revised memory",
                updatedAt = 200L,
            )

            dao.updateCoreMemory(revised)

            assertEquals(
                listOf(revised),
                nextUpdate(),
            )

            // 삭제: 해당 기억이 목록에서 사라진다.
            dao.deleteCoreMemory(revised)

            assertEquals(
                emptyList<CoreMemory>(),
                nextUpdate(),
            )
        } finally {
            observer.cancelAndJoin()
            updates.close()
        }
    }
}
