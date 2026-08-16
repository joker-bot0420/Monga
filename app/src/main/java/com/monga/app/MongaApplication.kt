package com.monga.app

import android.app.Application
import com.monga.app.chat.ChatCoordinator
import com.monga.app.data.MongaRepository
import com.monga.app.data.backup.SafBackupStore
import com.monga.app.data.local.MongaDatabase
import com.monga.app.inference.FakeInferenceEngine

class MongaApplication : Application() {
    val repository by lazy {
        MongaRepository(
            MongaDatabase.create(this),
            SafBackupStore(contentResolver),
        )
    }

    val inferenceEngine by lazy {
        FakeInferenceEngine(initiallyReady = true)
    }

    val chatCoordinator by lazy {
        ChatCoordinator(
            chatStore = repository,
            inferenceEngine = inferenceEngine,
        )
    }
}

