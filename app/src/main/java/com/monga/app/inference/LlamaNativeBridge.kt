package com.monga.app.inference

object LlamaNativeBridge {
    init {
        System.loadLibrary("monga_native")
    }

    external fun nativePing(): String
    external fun nativeLlamaTimeUs(): Long

    external fun nativeLoadModel(path: String): Boolean
    external fun nativeUnloadModel()

    external fun nativeStartGeneration(
        prompt: String,
        maxTokens: Int,
    ): Boolean

    external fun nativeNextToken(): ByteArray?
    external fun nativeCancelGeneration()
    external fun nativeFinishGeneration()
}
