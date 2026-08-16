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

class MongaViewModel(
    private val repository: MongaRepository,
    private val chatCoordinator: ChatCoordinator,
    private val modelStore: ModelStore,
    private val modelPreferences: ModelPreferences,
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
    val notice = MutableStateFlow<String?>(null)

    val selectedModelName = modelPreferences.selectedModelName
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            null,
        )

    init {
        viewModelScope.launch {
            conversations.collect { list ->
                if (selectedConversation.value == null && list.isNotEmpty()) selectedConversation.value = list.first().id
            }
        }
    }

    fun newConversation() = viewModelScope.launch { selectedConversation.value = repository.createConversation() }
    fun selectConversation(id: Long) { selectedConversation.value = id }
    fun send(text: String) = viewModelScope.launch {
        val id = selectedConversation.value
            ?: repository.createConversation().also { selectedConversation.value = it }

        when (chatCoordinator.send(id, text)) {
            ChatResult.Completed,
            ChatResult.Cancelled,
            ChatResult.Ignored -> Unit

            is ChatResult.Failed -> {
                notice.value = "응답을 생성하지 못했습니다."
            }
        }
    }
    fun addMemory(text: String) = viewModelScope.launch { if (text.isNotBlank()) repository.addCoreMemory(text) }
    fun updateMemory(memory: CoreMemory, text: String) = viewModelScope.launch { if (text.isNotBlank()) repository.updateCoreMemory(memory, text) }
    fun deleteMemory(memory: CoreMemory) = viewModelScope.launch { repository.deleteCoreMemory(memory) }
    fun changeDate(days: Long) { selectedDate.value = selectedDate.value.plusDays(days) }
    fun export(context: Context, uri: Uri) = runCatchingTask("백업을 저장했습니다.") { repository.export(context, uri) }
    fun restore(uri: Uri) = runCatchingTask("백업을 복원했습니다.") { repository.restore(uri) }
    fun importModel(uri: Uri) = viewModelScope.launch {
        notice.value = runCatching {
            val imported = modelStore.importModel(uri)

            modelPreferences.setSelectedModelName(
                imported.displayName
            )

            "모델을 가져왔습니다: ${imported.displayName}"
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
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        MongaViewModel(
            repository,
            chatCoordinator,
            modelStore,
            modelPreferences,
        ) as T
}
