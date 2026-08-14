package com.monga.app.inference

sealed interface InferenceEvent {
    data class Token(val text: String) : InferenceEvent
    data object Completed : InferenceEvent
    data object Cancelled : InferenceEvent
    data class Failed(val cause: Throwable) : InferenceEvent
}
