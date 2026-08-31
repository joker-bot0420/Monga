package com.monga.app.inference

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.util.concurrent.atomic.AtomicBoolean

enum class GenerationEndReason {
    NONE,
    EOG,
    MAX_TOKENS,
    CANCELLED,
    UNKNOWN,
}

class LlamaInferenceEngine(
    private val maxTokens: Int = 64,
    private val contextBudgetTokens: Int = 4096,
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

    override fun generate(prompt: String): Flow<InferenceEvent> =
        generate(
            listOf(
                InferenceMessage(
                    role = InferenceRole.USER,
                    content = prompt,
                )
            )
        )

    override fun generate(
        messages: List<InferenceMessage>,
    ): Flow<InferenceEvent> = flow {

        if (messages.isEmpty()) {
            emit(
                InferenceEvent.Failed(
                    IllegalArgumentException(
                        "대화 메시지가 비어 있습니다."
                    )
                )
            )
            return@flow
        }

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

        val workingMessages = messages.toMutableList()

        var roles = workingMessages
            .map { it.role.wireValue }
            .toTypedArray()

        var contents = workingMessages
            .map { it.content }
            .toTypedArray()

        var promptTokens = LlamaNativeBridge.nativeCountChatTokens(
            roles = roles,
            contents = contents,
        )

        val modelContextSize =
            LlamaNativeBridge.nativeModelContextSize()

        if (
            promptTokens <= 0 ||
            modelContextSize <= 0 ||
            contextBudgetTokens <= 0
        ) {
            emit(
                InferenceEvent.Failed(
                    IllegalStateException(
                        "대화 컨텍스트 크기를 확인하지 못했습니다."
                    )
                )
            )
            return@flow
        }

        val effectiveContextBudget =
            minOf(modelContextSize, contextBudgetTokens)

        while (
            promptTokens.toLong() + maxTokens.toLong() >
            effectiveContextBudget.toLong() &&
            workingMessages.size > 1
        ) {
            val trimmedMessages =
                ContextBudgetPolicy.dropOldestTurn(workingMessages)

            if (trimmedMessages == workingMessages) {
                break
            }

            workingMessages.clear()
            workingMessages.addAll(trimmedMessages)

            roles = workingMessages
                .map { it.role.wireValue }
                .toTypedArray()

            contents = workingMessages
                .map { it.content }
                .toTypedArray()

            promptTokens = LlamaNativeBridge.nativeCountChatTokens(
                roles = roles,
                contents = contents,
            )

            if (promptTokens <= 0) {
                emit(
                    InferenceEvent.Failed(
                        IllegalStateException(
                            "대화 컨텍스트 크기를 확인하지 못했습니다."
                        )
                    )
                )
                return@flow
            }
        }

        if (
            promptTokens.toLong() + maxTokens.toLong() >
            effectiveContextBudget.toLong()
        ) {
            emit(
                InferenceEvent.Failed(
                    IllegalArgumentException(
                        "대화가 사용 가능한 컨텍스트 예산을 초과했습니다."
                    )
                )
            )
            return@flow
        }

        cancelled.set(false)
        _state.value = InferenceState.Generating

        val decoder = Utf8StreamDecoder()

        try {

            val started = LlamaNativeBridge.nativeStartChatGeneration(
                roles = roles,
                contents = contents,
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

    fun lastGenerationEndReason(): GenerationEndReason =
        when (LlamaNativeBridge.nativeLastGenerationEndReason()) {
            0 -> GenerationEndReason.NONE
            1 -> GenerationEndReason.EOG
            2 -> GenerationEndReason.MAX_TOKENS
            3 -> GenerationEndReason.CANCELLED
            else -> GenerationEndReason.UNKNOWN
        }

    fun lastGeneratedTokenCount(): Int =
        LlamaNativeBridge.nativeLastGeneratedTokenCount()

    fun lastPromptPrefillUs(): Long =
        LlamaNativeBridge.nativeLastPromptPrefillUs()

    fun lastDecodeUs(): Long =
        LlamaNativeBridge.nativeLastDecodeUs()

    fun lastDecodedTokenCount(): Int =
        LlamaNativeBridge.nativeLastDecodedTokenCount()

    fun currentRssKb(): Long =
        LlamaNativeBridge.nativeCurrentRssKb()

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
