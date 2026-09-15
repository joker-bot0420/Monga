package com.monga.app.chat

fun interface EpisodicMemoryProvider {
    suspend fun buildMemory(userMessage: String): String
}
