package com.monga.app.inference

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

class Utf8StreamDecoder {

    private val decoder = StandardCharsets.UTF_8
        .newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)

    private var pending = ByteArray(0)

    fun decode(bytes: ByteArray): String {
        if (bytes.isEmpty()) {
            return ""
        }

        val combined = ByteArray(pending.size + bytes.size)

        pending.copyInto(
            destination = combined,
            destinationOffset = 0,
        )

        bytes.copyInto(
            destination = combined,
            destinationOffset = pending.size,
        )

        val input = ByteBuffer.wrap(combined)
        val output = CharBuffer.allocate(combined.size.coerceAtLeast(1))

        val result = decoder.decode(
            input,
            output,
            false,
        )

        if (result.isError) {
            result.throwException()
        }

        if (result.isOverflow) {
            throw IllegalStateException("UTF-8 decode buffer overflow.")
        }

        pending = ByteArray(input.remaining())
        input.get(pending)

        output.flip()

        return output.toString()
    }

    fun finish(): String {
        pending = ByteArray(0)
        decoder.reset()

        return ""
    }

    fun reset() {
        pending = ByteArray(0)
        decoder.reset()
    }
}
