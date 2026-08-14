package com.monga.app.inference

sealed interface InferenceState {
    data object NoModel : InferenceState
    data object Loading : InferenceState
    data object Ready : InferenceState
    data object Generating : InferenceState
    data class Error(val message: String) : InferenceState
}
