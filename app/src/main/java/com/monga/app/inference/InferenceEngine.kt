package com.monga.app.inference

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

enum class InferenceRole(
    val wireValue: String,
) {
    SYSTEM("system"),
    USER("user"),
    ASSISTANT("assistant"),
}

data class InferenceMessage(
    val role: InferenceRole,
    val content: String,
)
interface InferenceEngine {
    val state: StateFlow<InferenceState>

    suspend fun loadModel(path: String)

    fun generate(
        messages: List<InferenceMessage>,
    ): Flow<InferenceEvent>

    fun generate(prompt: String): Flow<InferenceEvent> =
        generate(
            listOf(
                InferenceMessage(
                    role = InferenceRole.USER,
                    content = prompt,
                )
            )
        )

    fun cancel()

    suspend fun unload()
}
