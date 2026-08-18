package com.monga.app.inference

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LlamaNativeBridgeTest {

    @Test
    fun nativePing_returnsExpectedMessage() {
        assertEquals(
            "monga-native-ok",
            LlamaNativeBridge.nativePing(),
        )
    }

    @Test
    fun nativeLlamaTimeUs_returnsPositiveValue() {
        assertTrue(
            LlamaNativeBridge.nativeLlamaTimeUs() > 0L,
        )
    }
}
