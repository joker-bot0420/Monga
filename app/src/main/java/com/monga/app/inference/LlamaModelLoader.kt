package com.monga.app.inference

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LlamaModelLoader {

    suspend fun load(path: String): Boolean =
        withContext(Dispatchers.IO) {
            LlamaNativeBridge.nativeLoadModel(path)
        }

    suspend fun unload() =
        withContext(Dispatchers.IO) {
            LlamaNativeBridge.nativeUnloadModel()
        }
}
