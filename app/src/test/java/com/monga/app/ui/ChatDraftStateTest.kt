package com.monga.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatDraftStateTest {

    @Test
    fun editUpdatesTextAndRevision() {
        val state = ChatDraftState()

        assertEquals(ChatDraft(), state.snapshot())

        state.edit("안녕")
        assertEquals(ChatDraft("안녕", 1L), state.snapshot())

        // 같은 값을 다시 전달하면 수정 번호가 증가하지 않는다.
        state.edit("안녕")
        assertEquals(ChatDraft("안녕", 1L), state.snapshot())
    }

    @Test
    fun savedMessageClearsUnchangedDraft() {
        val state = ChatDraftState()
        state.edit("전송할 메시지")

        val submitted = state.snapshot()

        assertTrue(state.clearIfUnchanged(submitted))
        assertEquals("", state.snapshot().text)
        assertEquals(submitted.revision + 1, state.snapshot().revision)
    }

    @Test
    fun lateCallbackDoesNotClearEditedDraft() {
        val state = ChatDraftState()
        state.edit("첫 번째 메시지")

        val submitted = state.snapshot()

        // 저장이 완료되기 전에 사용자가 새 문장을 작성한다.
        state.edit("새로 작성한 메시지")

        assertFalse(state.clearIfUnchanged(submitted))
        assertEquals("새로 작성한 메시지", state.snapshot().text)
    }

    @Test
    fun retypingSameTextDoesNotAllowOldCallbackToClear() {
        val state = ChatDraftState()
        state.edit("같은 문장")

        val submitted = state.snapshot()

        state.edit("")
        state.edit("같은 문장")

        assertFalse(state.clearIfUnchanged(submitted))
        assertEquals("같은 문장", state.snapshot().text)
        assertEquals(3L, state.snapshot().revision)
    }

    @Test
    fun rejectedSendLeavesDraftAndCanBeRetried() {
        val state = ChatDraftState()
        state.edit("다시 전송할 메시지")

        val submitted = state.snapshot()

        // 전송이 거절되거나 저장이 실패하면 clearIfUnchanged를 호출하지 않는다.
        assertEquals(submitted, state.snapshot())

        // 이후 실제 저장 성공 콜백이 도착하면 같은 초안을 비울 수 있다.
        assertTrue(state.clearIfUnchanged(submitted))
        assertEquals("", state.snapshot().text)
    }
}
