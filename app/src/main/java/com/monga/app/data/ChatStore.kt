package com.monga.app.data

import com.monga.app.data.local.Message
import com.monga.app.data.local.MessageRole

interface ChatStore {
    suspend fun saveMessage(
        conversationId: Long,
        role: MessageRole,
        content: String,
    )

    suspend fun recentMessages(
        conversationId: Long,
    ): List<Message>

    companion object {
        const val MAX_RECENT_MESSAGES = 20
    }
}