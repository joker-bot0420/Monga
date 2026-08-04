package com.monga.app.data

import android.content.Context
import android.net.Uri
import androidx.room.withTransaction
import com.monga.app.data.backup.BackupJsonCodec
import com.monga.app.data.backup.SafBackupStore
import com.monga.app.data.local.*
import com.monga.app.util.epochRange
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

class MongaRepository(private val database: MongaDatabase, private val backupStore: SafBackupStore) {
    private val dao = database.dao()
    val conversations = dao.observeConversations()
    val coreMemories = dao.observeCoreMemories()
    val episodicMemories = dao.observeEpisodicMemories()
    val dailySummaries = dao.observeDailySummaries()
    fun messages(conversationId: Long): Flow<List<Message>> = dao.observeMessages(conversationId)
    fun messages(date: LocalDate): Flow<List<Message>> = date.epochRange().let { dao.observeMessagesByDate(it.start, it.endExclusive) }

    suspend fun createConversation(): Long {
        val now = System.currentTimeMillis()
        return dao.insertConversation(Conversation(title = "새 대화", createdAt = now, updatedAt = now))
    }

    suspend fun send(conversationId: Long, content: String) {
        val text = content.trim(); if (text.isEmpty()) return
        val now = System.currentTimeMillis()
        dao.insertMessage(Message(conversationId = conversationId, role = MessageRole.USER, content = text, createdAt = now))
        dao.insertMessage(Message(conversationId = conversationId, role = MessageRole.ASSISTANT, content = "로컬 AI 모델은 다음 단계에서 연결됩니다.", createdAt = now + 1))
        dao.touchConversation(conversationId, now + 1)
    }

    suspend fun addCoreMemory(content: String) {
        val now = System.currentTimeMillis()
        dao.insertCoreMemory(CoreMemory(content = content.trim(), createdAt = now, updatedAt = now))
    }
    suspend fun updateCoreMemory(value: CoreMemory, content: String) = dao.updateCoreMemory(value.copy(content = content.trim(), updatedAt = System.currentTimeMillis()))
    suspend fun deleteCoreMemory(value: CoreMemory) = dao.deleteCoreMemory(value)

    suspend fun export(context: Context, treeUri: Uri): Uri {
        backupStore.persistTreePermission(treeUri)
        return backupStore.writeToTree(context, treeUri, BackupJsonCodec.encode(snapshot()))
    }
    suspend fun restore(uri: Uri) = database.withTransaction { dao.replaceAll(BackupJsonCodec.decode(backupStore.read(uri))) }
    private suspend fun snapshot() = DatabaseSnapshot(dao.allConversations(), dao.allMessages(), dao.allCoreMemories(), dao.allEpisodicMemories(), dao.allDailySummaries())
}
