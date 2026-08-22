package com.monga.app

import android.app.Application
import com.monga.app.chat.ChatCoordinator
import com.monga.app.data.MongaRepository
import com.monga.app.data.backup.SafBackupStore
import com.monga.app.data.local.MongaDatabase
import com.monga.app.data.model.ModelPreferences
import com.monga.app.data.model.ModelStore
import com.monga.app.inference.LlamaInferenceEngine
import com.monga.app.inference.LlamaModelLoader
import java.io.File
import com.monga.app.chat.DefaultSystemPromptProvider
import com.monga.app.chat.DefaultCoreMemoryProvider

class MongaApplication : Application() {
    val repository by lazy {
        MongaRepository(
            MongaDatabase.create(this),
            SafBackupStore(contentResolver),
        )
    }

    val modelStore by lazy {
        ModelStore(
            contentResolver = contentResolver,
            modelsDirectory = File(filesDir, "models"),
        )
    }

    val modelPreferences by lazy {
        ModelPreferences(this)
    }

    val inferenceEngine by lazy {
        LlamaInferenceEngine()
    }

    val llamaModelLoader by lazy {
        LlamaModelLoader(inferenceEngine)
    }

    val chatCoordinator by lazy {
        ChatCoordinator(
            chatStore = repository,
            inferenceEngine = inferenceEngine,
            systemPromptProvider = DefaultSystemPromptProvider(
                coreMemoryProvider = DefaultCoreMemoryProvider(
                    coreMemories = repository.coreMemories,
                ),
            ),
        )
    }
}
