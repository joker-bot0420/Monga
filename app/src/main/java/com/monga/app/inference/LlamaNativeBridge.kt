package com.monga.app.inference

object LlamaNativeBridge {
    init {
        System.loadLibrary("monga_native")
    }

    external fun nativePing(): String
    external fun nativeLlamaTimeUs(): Long

    external fun nativeLoadModel(path: String): Boolean
    external fun nativeUnloadModel()

    external fun nativeModelContextSize(): Int

    external fun nativeStartGeneration(
        prompt: String,
        maxTokens: Int,
    ): Boolean

    external fun nativeCountChatTokens(
        roles: Array<String>,
        contents: Array<String>,
    ): Int

    external fun nativeStartChatGeneration(
        roles: Array<String>,
        contents: Array<String>,
        maxTokens: Int,
    ): Boolean

    external fun nativeNextToken(): ByteArray?
    external fun nativeLastGenerationEndReason(): Int
    external fun nativeLastGeneratedTokenCount(): Int
    external fun nativeLastPromptPrefillUs(): Long
    external fun nativeLastDecodeUs(): Long
    external fun nativeLastDecodedTokenCount(): Int
    external fun nativeCancelGeneration()
    external fun nativeFinishGeneration()
    external fun nativeCurrentRssKb(): Long

}
