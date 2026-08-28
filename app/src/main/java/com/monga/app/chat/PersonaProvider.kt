package com.monga.app.chat

fun interface PersonaProvider {
    suspend fun buildPersona(): String
}
