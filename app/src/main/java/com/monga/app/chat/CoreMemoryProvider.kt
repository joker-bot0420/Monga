package com.monga.app.chat

fun interface CoreMemoryProvider {
    suspend fun buildMemory(): String
}
