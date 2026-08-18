package com.monga.app.inference

object LlamaNativeBridge {
    init {
        System.loadLibrary("monga_native")
    }

    external fun nativePing(): String
    external fun nativeLlamaTimeUs(): Long
}
