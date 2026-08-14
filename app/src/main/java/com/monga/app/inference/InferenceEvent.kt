package com.monga.app.inference

sealed interface InferenceEvent {
    data class Token(val text: String) : InferenceEvent
    data object Completed : InferenceEvent
    data object Cancelled : InferenceEvent

    /**
     * A single generation request failed.
     *
     * This does not necessarily mean that the inference engine itself
     * is unusable and subsequent requests may still succeed.
     */
    data class Failed(val cause: Throwable) : InferenceEvent
}
