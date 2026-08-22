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

    fun generate(prompt: String): Flow<InferenceEvent>

    fun generate(
        messages: List<InferenceMessage>,
    ): Flow<InferenceEvent> {
        require(messages.size == 1) {
            "현재는 단일 메시지 추론만 지원합니다."
        }

        val message = messages.single()

        require(message.role == InferenceRole.USER) {
            "현재 단일 메시지는 USER 역할이어야 합니다."
        }

        return generate(message.content)
    }

    fun cancel()

    suspend fun unload()
}
