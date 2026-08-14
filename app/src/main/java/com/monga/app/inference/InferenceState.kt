package com.monga.app.inference

sealed interface InferenceState {
    data object NoModel : InferenceState
    data object Loading : InferenceState
    data object Ready : InferenceState
    data object Generating : InferenceState

    /**
     * The inference engine is in an unusable state.
     *
     * This represents a persistent engine-level failure, such as
     * model loading or native initialization failure.
     */
    data class Error(val message: String) : InferenceState
}
