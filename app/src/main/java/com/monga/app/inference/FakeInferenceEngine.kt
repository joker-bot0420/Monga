package com.monga.app.inference

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.atomic.AtomicBoolean

class FakeInferenceEngine : InferenceEngine {
    private val _state = MutableStateFlow<InferenceState>(InferenceState.NoModel)
    override val state: StateFlow<InferenceState> = _state

    private val cancelled = AtomicBoolean(false)

    override suspend fun loadModel(path: String) {
        _state.value = InferenceState.Loading
        _state.value = InferenceState.Ready
    }

    override fun generate(prompt: String): Flow<InferenceEvent> = flow {
        if (_state.value != InferenceState.Ready) {
            emit(
                InferenceEvent.Failed(
                    IllegalStateException("모델이 준비되지 않았습니다.")
                )
            )
            return@flow
        }

        cancelled.set(false)
        _state.value = InferenceState.Generating

        try {
            val response = "안녕! 지금은 테스트 엔진으로 대화하고 있어."

            for (chunk in response.chunked(3)) {
                if (cancelled.get()) {
                    emit(InferenceEvent.Cancelled)
                    return@flow
                }

                emit(InferenceEvent.Token(chunk))
                delay(20)
            }

            emit(InferenceEvent.Completed)
        } finally {
            if (_state.value != InferenceState.NoModel) {
                _state.value = InferenceState.Ready
            }
        }
    }

    override fun cancel() {
        cancelled.set(true)
    }

    override suspend fun unload() {
        cancel()
        _state.value = InferenceState.NoModel
    }
}
