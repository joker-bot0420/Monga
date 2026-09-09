package com.monga.app.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class ChatDraft(
    val text: String = "",
    val revision: Long = 0L,
)

class ChatDraftState {

    private val _draft = MutableStateFlow(ChatDraft())
    val draft: StateFlow<ChatDraft> = _draft.asStateFlow()

    fun edit(text: String) {
        _draft.update { current ->
            if (current.text == text) {
                current
            } else {
                current.copy(
                    text = text,
                    revision = current.revision + 1,
                )
            }
        }
    }

    fun snapshot(): ChatDraft = _draft.value

    fun clearIfUnchanged(expected: ChatDraft): Boolean {
        while (true) {
            val current = _draft.value

            if (current != expected || current.text.isEmpty()) {
                return false
            }

            val cleared = current.copy(
                text = "",
                revision = current.revision + 1,
            )

            if (_draft.compareAndSet(current, cleared)) {
                return true
            }
        }
    }
}
