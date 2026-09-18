package com.monga.app.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class GroundedResponsePrefixSanitizerTest {

    @Test
    fun finalResponseStripsStandaloneAffirmativePrefix() {
        assertEquals(
            "9월 17일에 홍차를 마신 기록이 있어.",
            GroundedResponsePrefixSanitizer.sanitizeFinal(
                "응. 9월 17일에 홍차를 마신 기록이 있어."
            ),
        )
    }

    @Test
    fun finalResponseStripsStandaloneNegativePrefix() {
        assertEquals(
            "9월 8일에 계단을 15분 걸은 기록이 있어.",
            GroundedResponsePrefixSanitizer.sanitizeFinal(
                "아니. 9월 8일에 계단을 15분 걸은 기록이 있어."
            ),
        )
    }

    @Test
    fun finalResponseKeepsNonStandaloneWord() {
        assertEquals(
            "아니지만 괜찮아.",
            GroundedResponsePrefixSanitizer.sanitizeFinal(
                "아니지만 괜찮아."
            ),
        )
    }

    @Test
    fun streamingHoldsPotentialPrefixUntilMeaningfulBodyArrives() {
        assertEquals(
            "",
            GroundedResponsePrefixSanitizer.sanitizeStreaming("아"),
        )
        assertEquals(
            "",
            GroundedResponsePrefixSanitizer.sanitizeStreaming("아니."),
        )
        assertEquals(
            "9월 10일에 운동한 기록이 있어.",
            GroundedResponsePrefixSanitizer.sanitizeStreaming(
                "아니. 9월 10일에 운동한 기록이 있어."
            ),
        )
    }

    @Test
    fun ordinaryGroundedTextIsPreserved() {
        assertEquals(
            "구매 여부를 확인할 기록이 없어.",
            GroundedResponsePrefixSanitizer.sanitizeFinal(
                "구매 여부를 확인할 기록이 없어."
            ),
        )
    }
}
