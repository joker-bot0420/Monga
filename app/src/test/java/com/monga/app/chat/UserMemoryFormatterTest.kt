package com.monga.app.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class UserMemoryFormatterTest {

    @Test
    fun rewritesFirstPersonSubjectToUser() {
        assertEquals(
            "사용자는 녹차를 좋아한다.",
            UserMemoryFormatter.format("나는 녹차를 좋아한다."),
        )
    }

    @Test
    fun rewritesFirstPersonPossessiveToUser() {
        assertEquals(
            "사용자의 취미는 수영이다.",
            UserMemoryFormatter.format("나의 취미는 수영이다."),
        )
    }

    @Test
    fun rewritesFirstPersonTokenInMiddleOfSentence() {
        assertEquals(
            "요즘 사용자가 관심 있는 건 해양생태다.",
            UserMemoryFormatter.format("요즘 내가 관심 있는 건 해양생태다."),
        )
    }

    @Test
    fun doesNotRewriteMatchingCharactersInsideAnotherToken() {
        assertEquals(
            "내가방은 검은색이다.",
            UserMemoryFormatter.format("내가방은 검은색이다."),
        )
    }

    @Test
    fun leavesAlreadyNeutralMemoryUnchanged() {
        assertEquals(
            "좋아하는 음료: 녹차",
            UserMemoryFormatter.format("좋아하는 음료: 녹차"),
        )
    }
}
