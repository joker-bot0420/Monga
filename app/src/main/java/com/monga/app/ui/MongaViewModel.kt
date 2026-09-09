package com.monga.app.ui

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.monga.app.data.MongaRepository
import com.monga.app.data.local.CoreMemory
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.time.LocalDate
import com.monga.app.chat.ChatCoordinator
import com.monga.app.chat.ChatResult
import com.monga.app.data.model.ModelPreferences
import com.monga.app.data.model.ModelStore
import com.monga.app.inference.LlamaModelLoader
import com.monga.app.util.epochRange
import java.util.concurrent.atomic.AtomicBoolean

class MongaViewModel(
    private val repository: MongaRepository,
    private val chatCoordinator: ChatCoordinator,
    private val modelStore: ModelStore,
    private val modelPreferences: ModelPreferences,
    private val llamaModelLoader: LlamaModelLoader,
) : ViewModel() {
    val conversations = repository.conversations.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val coreMemories = repository.coreMemories.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val episodicMemories = repository.episodicMemories.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val dailySummaries = repository.dailySummaries.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    private val selectedConversation = MutableStateFlow<Long?>(null)
    val selectedDate = MutableStateFlow(LocalDate.now())
    val messages = selectedConversation.flatMapLatest { id -> id?.let(repository::messages) ?: flowOf(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val datedMessages = selectedDate.flatMapLatest(repository::messages)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val datedEpisodicMemories =
        selectedDate.flatMapLatest(repository::episodicMemories)
            .stateIn(
                viewModelScope,
                SharingStarted.WhileSubscribed(5_000),
                emptyList(),
            )

    val notice = MutableStateFlow<String?>(null)

    private val _streamingDraft = MutableStateFlow("")
    val streamingDraft: StateFlow<String> = _streamingDraft
    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating

    private val sendInProgress = AtomicBoolean(false)

    private val chatDraftState = ChatDraftState()
    val chatDraft: StateFlow<ChatDraft> = chatDraftState.draft

    fun editChatDraft(text: String) {
        chatDraftState.edit(text)
    }

    fun sendChatDraft() {
        val submitted = chatDraftState.snapshot()

        send(
            text = submitted.text,
            onUserMessageSaved = {
                chatDraftState.clearIfUnchanged(submitted)
            },
        )
    }

    val selectedModelName = modelPreferences.selectedModelName
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            null,
        )

    init {
        viewModelScope.launch {
            conversations.collect { list ->
                if (selectedConversation.value == null && list.isNotEmpty()) {
                    selectedConversation.value = list.first().id
                }
            }
        }

        viewModelScope.launch {
            val savedModelName = modelPreferences.selectedModelName.first()

            if (savedModelName != null) {
                runCatching {
                    val modelFile = modelStore.getModelFile(savedModelName)

                    check(
                        llamaModelLoader.load(modelFile.absolutePath)
                    ) {
                        "llama.cpp가 저장된 모델을 불러오지 못했습니다."
                    }
                }.onFailure {
                    notice.value =
                        "저장된 모델을 다시 불러오지 못했습니다: " +
                                (it.message ?: "알 수 없는 오류")
                }
            }
        }
    }

    fun newConversation() = viewModelScope.launch { selectedConversation.value = repository.createConversation() }
    fun selectConversation(id: Long) { selectedConversation.value = id }

    fun send(
        text: String,
        onUserMessageSaved: (String) -> Unit = {},
    ) {
        if (text.isBlank()) return

        // Only one send operation may run at a time.
        if (!sendInProgress.compareAndSet(false, true)) return

        _streamingDraft.value = ""
        _isGenerating.value = true

        val sendJob = viewModelScope.launch(
            start = kotlinx.coroutines.CoroutineStart.LAZY,
        ) {
            try {
                val id = selectedConversation.value
                    ?: repository.createConversation().also {
                        selectedConversation.value = it
                    }

                when (
                    val result = chatCoordinator.send(
                        conversationId = id,
                        content = text,
                        onToken = { draft ->
                            _streamingDraft.value = draft
                        },
                        onUserMessageSaved = onUserMessageSaved,
                    )
                ) {
                    ChatResult.Completed,
                    ChatResult.Cancelled,
                    ChatResult.Ignored -> Unit

                    is ChatResult.Failed -> {
                        notice.value =
                            "응답 생성 실패: " +
                                    (result.cause.message
                                        ?: result.cause::class.simpleName
                                        ?: "알 수 없는 오류")
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (t: Throwable) {
                notice.value =
                    "응답 생성 실패: " +
                            (t.message
                                ?: t::class.simpleName
                                ?: "알 수 없는 오류")
            }
        }

        // Register cleanup before the coroutine is allowed to start.
        // This also runs when the job is cancelled before its body executes.
        sendJob.invokeOnCompletion {
            _streamingDraft.value = ""
            _isGenerating.value = false
            sendInProgress.set(false)
        }

        sendJob.start()
    }

    fun cancelGeneration() {
        chatCoordinator.cancel()
    }

    fun addMemory(text: String) = viewModelScope.launch { if (text.isNotBlank()) repository.addCoreMemory(text) }
    fun updateMemory(memory: CoreMemory, text: String) = viewModelScope.launch { if (text.isNotBlank()) repository.updateCoreMemory(memory, text) }
    fun deleteMemory(memory: CoreMemory) = viewModelScope.launch { repository.deleteCoreMemory(memory) }

    fun addEpisodicMemory(
        title: String,
        content: String,
    ) = viewModelScope.launch {
        val trimmedTitle = title.trim()
        val trimmedContent = content.trim()

        if (trimmedTitle.isEmpty() || trimmedContent.isEmpty()) {
            return@launch
        }

        val date = selectedDate.value
        val occurredAt =
            if (date == LocalDate.now()) {
                System.currentTimeMillis()
            } else {
                date.epochRange().start
            }

        repository.addEpisodicMemory(
            title = trimmedTitle,
            content = trimmedContent,
            occurredAt = occurredAt,
        )
    }

    fun changeDate(days: Long) { selectedDate.value = selectedDate.value.plusDays(days) }
    fun export(context: Context, uri: Uri) = runCatchingTask("백업을 저장했습니다.") { repository.export(context, uri) }
    fun restore(uri: Uri) = runCatchingTask("백업을 복원했습니다.") { repository.restore(uri) }
    fun importModel(uri: Uri) = viewModelScope.launch {
        notice.value = runCatching {
            val imported = modelStore.importModel(uri)

            check(
                llamaModelLoader.load(imported.file.absolutePath)
            ) {
                "llama.cpp가 모델을 불러오지 못했습니다."
            }

            modelPreferences.setSelectedModelName(
                imported.displayName
            )

            "모델을 가져오고 불러왔습니다: ${imported.displayName}"
        }.getOrElse {
            "오류: ${it.message ?: "알 수 없는 오류"}"
        }
    }
    fun clearNotice() { notice.value = null }
    private fun runCatchingTask(success: String, block: suspend () -> Unit) = viewModelScope.launch {
        notice.value = runCatching { block() }.fold({ success }, { "오류: ${it.message ?: "알 수 없는 오류"}" })
    }
}

class MongaViewModelFactory(
    private val repository: MongaRepository,
    private val chatCoordinator: ChatCoordinator,
    private val modelStore: ModelStore,
    private val modelPreferences: ModelPreferences,
    private val llamaModelLoader: LlamaModelLoader,
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        MongaViewModel(
            repository,
            chatCoordinator,
            modelStore,
            modelPreferences,
            llamaModelLoader,
        ) as T
}
