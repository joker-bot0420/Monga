package com.monga.app.inference

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.util.concurrent.atomic.AtomicBoolean

class LlamaInferenceEngine(
    private val maxTokens: Int = 64,
) : InferenceEngine {

    private val _state = MutableStateFlow<InferenceState>(
        InferenceState.NoModel
    )

    override val state: StateFlow<InferenceState> = _state

    private val cancelled = AtomicBoolean(false)

    override suspend fun loadModel(path: String) {
        _state.value = InferenceState.Loading

        try {
            val loaded = LlamaNativeBridge.nativeLoadModel(path)

            if (loaded) {
                _state.value = InferenceState.Ready
            } else {
                _state.value = InferenceState.Error(
                    "모델을 불러오지 못했습니다."
                )
            }
        } catch (cause: Throwable) {
            _state.value = InferenceState.Error(
                cause.message ?: "모델 로드 중 오류가 발생했습니다."
            )

            throw cause
        }
    }

    override fun generate(prompt: String): Flow<InferenceEvent> = flow {
        if (_state.value != InferenceState.Ready) {
            val currentState = _state.value

            emit(
                InferenceEvent.Failed(
                    IllegalStateException(
                        "모델이 준비되지 않았습니다. 현재 상태: $currentState"
                    )
                )
            )
            return@flow
        }

        cancelled.set(false)
        _state.value = InferenceState.Generating

        val decoder = Utf8StreamDecoder()

        try {

            val started = LlamaNativeBridge.nativeStartGeneration(
                prompt = prompt,
                maxTokens = maxTokens,
            )

            if (!started) {
                emit(
                    InferenceEvent.Failed(
                        IllegalStateException(
                            "텍스트 생성을 시작하지 못했습니다."
                        )
                    )
                )
                return@flow
            }

            while (true) {
                if (cancelled.get()) {
                    emit(InferenceEvent.Cancelled)
                    return@flow
                }

                val bytes = LlamaNativeBridge.nativeNextToken()

                if (bytes == null) {
                    break
                }

                if (cancelled.get()) {
                    emit(InferenceEvent.Cancelled)
                    return@flow
                }

                val text = decoder.decode(bytes)

                if (text.isNotEmpty()) {
                    emit(InferenceEvent.Token(text))
                }
            }

            if (cancelled.get()) {
                emit(InferenceEvent.Cancelled)
            } else {
                val remainingText = decoder.finish()

                if (remainingText.isNotEmpty()) {
                    emit(InferenceEvent.Token(remainingText))
                }

                emit(InferenceEvent.Completed)
            }
        } catch (cause: CancellationException) {
            cancelled.set(true)
            LlamaNativeBridge.nativeCancelGeneration()

            throw cause
        } catch (cause: Throwable) {
            emit(InferenceEvent.Failed(cause))
        } finally {
            decoder.reset()
            LlamaNativeBridge.nativeFinishGeneration()

            if (_state.value != InferenceState.NoModel) {
                _state.value = InferenceState.Ready
            }
        }
    }.flowOn(Dispatchers.Default)

    override fun cancel() {
        cancelled.set(true)
        LlamaNativeBridge.nativeCancelGeneration()
    }

    override suspend fun unload() {
        cancel()
        LlamaNativeBridge.nativeFinishGeneration()
        LlamaNativeBridge.nativeUnloadModel()

        _state.value = InferenceState.NoModel
    }
}
