package com.monga.app.chat

fun interface SystemPromptProvider {
    suspend fun buildPrompt(): String
}
