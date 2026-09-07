package com.monga.app.inference

import org.junit.Assert.assertEquals
import org.junit.Test

class LeadingThinkBlockFilterTest {

    @Test
    fun removesLeadingThinkBlock() {
        val filter = LeadingThinkBlockFilter()

        val result =
            buildString {
                append(filter.accept("<think>"))
                append(filter.accept("\nreasoning\n"))
                append(filter.accept("</think>"))
                append(filter.accept("\n\n1 + 1 = 2."))
            }

        assertEquals(
            "1 + 1 = 2.",
            result,
        )
    }

    @Test
    fun removesLeadingThinkBlockAcrossTokenBoundaries() {
        val filter = LeadingThinkBlockFilter()

        val result =
            buildString {
                append(filter.accept("<thi"))
                append(filter.accept("nk>\n"))
                append(filter.accept("hidden reasoning"))
                append(filter.accept("\n</thi"))
                append(filter.accept("nk>\n\n"))
                append(filter.accept("정답은 2입니다."))
            }

        assertEquals(
            "정답은 2입니다.",
            result,
        )
    }

    @Test
    fun passesThroughNormalTextUnchanged() {
        val filter = LeadingThinkBlockFilter()

        val result =
            buildString {
                append(filter.accept("안녕하세요."))
                append(filter.accept(" 반가워요."))
            }

        assertEquals(
            "안녕하세요. 반가워요.",
            result,
        )
    }
}
