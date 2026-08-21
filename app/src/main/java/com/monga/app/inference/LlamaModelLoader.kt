package com.monga.app.inference

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LlamaModelLoader(
    private val inferenceEngine: InferenceEngine,
) {

    suspend fun load(path: String): Boolean =
        withContext(Dispatchers.IO) {
            inferenceEngine.loadModel(path)

            inferenceEngine.state.value == InferenceState.Ready
        }

    suspend fun unload() =
        withContext(Dispatchers.IO) {
            inferenceEngine.unload()
        }
}
