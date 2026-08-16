package com.monga.app.data.local

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface MongaDao {
    @Insert suspend fun insertConversation(value: Conversation): Long
    @Insert suspend fun insertMessage(value: Message): Long
    @Insert suspend fun insertCoreMemory(value: CoreMemory): Long
    @Update suspend fun updateCoreMemory(value: CoreMemory)
    @Delete suspend fun deleteCoreMemory(value: CoreMemory)

    @Query("SELECT * FROM conversations ORDER BY updatedAt DESC")
    fun observeConversations(): Flow<List<Conversation>>
    @Query("SELECT * FROM messages WHERE conversationId = :conversationId ORDER BY createdAt, id")
    fun observeMessages(conversationId: Long): Flow<List<Message>>

    @Query(
        """
    SELECT * FROM (
        SELECT * FROM messages
        WHERE conversationId = :conversationId
        ORDER BY createdAt DESC, id DESC
        LIMIT :limit
    )
    ORDER BY createdAt ASC, id ASC
    """
    )
    suspend fun recentMessages(
        conversationId: Long,
        limit: Int,
    ): List<Message>
    @Query("SELECT * FROM messages WHERE createdAt >= :start AND createdAt < :end ORDER BY createdAt, id")
    fun observeMessagesByDate(start: Long, end: Long): Flow<List<Message>>
    @Query("SELECT * FROM core_memories ORDER BY updatedAt DESC")
    fun observeCoreMemories(): Flow<List<CoreMemory>>
    @Query("SELECT * FROM episodic_memories ORDER BY occurredAt DESC")
    fun observeEpisodicMemories(): Flow<List<EpisodicMemory>>
    @Query("SELECT * FROM daily_summaries ORDER BY date DESC")
    fun observeDailySummaries(): Flow<List<DailySummary>>
    @Query("UPDATE conversations SET updatedAt = :updatedAt WHERE id = :id")
    suspend fun touchConversation(id: Long, updatedAt: Long)

    @Query("SELECT * FROM conversations") suspend fun allConversations(): List<Conversation>
    @Query("SELECT * FROM messages") suspend fun allMessages(): List<Message>
    @Query("SELECT * FROM core_memories") suspend fun allCoreMemories(): List<CoreMemory>
    @Query("SELECT * FROM episodic_memories") suspend fun allEpisodicMemories(): List<EpisodicMemory>
    @Query("SELECT * FROM daily_summaries") suspend fun allDailySummaries(): List<DailySummary>

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun restoreConversations(v: List<Conversation>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun restoreMessages(v: List<Message>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun restoreCoreMemories(v: List<CoreMemory>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun restoreEpisodicMemories(v: List<EpisodicMemory>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun restoreDailySummaries(v: List<DailySummary>)
    @Query("DELETE FROM messages") suspend fun clearMessages()
    @Query("DELETE FROM conversations") suspend fun clearConversations()
    @Query("DELETE FROM core_memories") suspend fun clearCoreMemories()
    @Query("DELETE FROM episodic_memories") suspend fun clearEpisodicMemories()
    @Query("DELETE FROM daily_summaries") suspend fun clearDailySummaries()

    @Transaction
    suspend fun replaceAll(snapshot: DatabaseSnapshot) {
        clearMessages(); clearConversations(); clearCoreMemories(); clearEpisodicMemories(); clearDailySummaries()
        restoreConversations(snapshot.conversations)
        restoreMessages(snapshot.messages)
        restoreCoreMemories(snapshot.coreMemories)
        restoreEpisodicMemories(snapshot.episodicMemories)
        restoreDailySummaries(snapshot.dailySummaries)
    }
}

data class DatabaseSnapshot(
    val conversations: List<Conversation>,
    val messages: List<Message>,
    val coreMemories: List<CoreMemory>,
    val episodicMemories: List<EpisodicMemory>,
    val dailySummaries: List<DailySummary>,
)

