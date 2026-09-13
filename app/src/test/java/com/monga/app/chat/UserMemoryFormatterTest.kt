package com.monga.app.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class UserMemoryFormatterTest {

    @Test
    fun rewritesLeadingFirstPersonSubjectAsUser() {
        assertEquals(
            "사용자에 대한 사실: 사용자는 녹차를 좋아한다.",
            UserMemoryFormatter.format("나는 녹차를 좋아한다."),
        )
        assertEquals(
            "사용자에 대한 사실: 사용자는 커피를 좋아한다.",
            UserMemoryFormatter.format("저는 커피를 좋아한다."),
        )
        assertEquals(
            "사용자에 대한 사실: 사용자가 좋아하는 색은 파랑이다.",
            UserMemoryFormatter.format("내가 좋아하는 색은 파랑이다."),
        )
        assertEquals(
            "사용자에 대한 사실: 사용자가 좋아하는 음식은 국밥이다.",
            UserMemoryFormatter.format("제가 좋아하는 음식은 국밥이다."),
        )
    }

    @Test
    fun preservesContentWithoutLeadingFirstPersonSubject() {
        assertEquals(
            "사용자에 대한 사실: 좋아하는 음료: 녹차",
            UserMemoryFormatter.format("좋아하는 음료: 녹차"),
        )
    }
}
