package com.monga.app.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMemoryRelevanceGateTest {

    @Test
    fun ignoresUnrelatedConversation() {
        assertFalse(
            DefaultCoreMemoryRelevanceGate.shouldInclude(
                "오늘 기분 어때?"
            )
        )
    }

    @Test
    fun includesExplicitRecallRequest() {
        assertTrue(
            DefaultCoreMemoryRelevanceGate.shouldInclude(
                "내가 좋아하는 음료가 뭐였지?"
            )
        )
    }

    @Test
    fun includesPersonalizedPreferenceRequest() {
        assertTrue(
            DefaultCoreMemoryRelevanceGate.shouldInclude(
                "내 취향에 맞는 음료 추천해줘"
            )
        )
    }

    @Test
    fun doesNotTreatGenericTopicAsPersonalMemoryRequest() {
        assertFalse(
            DefaultCoreMemoryRelevanceGate.shouldInclude(
                "녹차는 어떤 맛이야?"
            )
        )
    }
}
