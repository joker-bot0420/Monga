package com.monga.app.inference

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface InferenceEngine {
    val state: StateFlow<InferenceState>

    suspend fun loadModel(path: String)

    fun generate(prompt: String): Flow<InferenceEvent>

    fun cancel()

    suspend fun unload()
}
