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
}
