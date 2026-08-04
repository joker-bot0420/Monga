package com.monga.app.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "conversations")
data class Conversation(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val createdAt: Long,
    val updatedAt: Long,
)

enum class MessageRole { USER, ASSISTANT, SYSTEM }

@Entity(
    tableName = "messages",
    foreignKeys = [ForeignKey(
        entity = Conversation::class,
        parentColumns = ["id"], childColumns = ["conversationId"],
        onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("conversationId"), Index("createdAt")],
)
data class Message(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val conversationId: Long,
    val role: MessageRole,
    val content: String,
    val createdAt: Long,
)

@Entity(tableName = "core_memories")
data class CoreMemory(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val content: String,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "episodic_memories", indices = [Index("occurredAt")])
data class EpisodicMemory(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val content: String,
    val occurredAt: Long,
    val createdAt: Long,
)

@Entity(tableName = "daily_summaries", indices = [Index(value = ["date"], unique = true)])
data class DailySummary(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val date: String,
    val content: String,
    val createdAt: Long,
    val updatedAt: Long,
)

