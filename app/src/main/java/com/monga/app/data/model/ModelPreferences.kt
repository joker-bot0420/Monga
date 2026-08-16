package com.monga.app.data.model

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.modelPreferencesDataStore by preferencesDataStore(
    name = "model_preferences"
)

class ModelPreferences(
    context: Context,
) {
    private val dataStore = context.applicationContext.modelPreferencesDataStore

    val selectedModelName: Flow<String?> =
        dataStore.data.map { preferences ->
            preferences[SELECTED_MODEL_NAME]
        }

    suspend fun setSelectedModelName(fileName: String) {
        dataStore.edit { preferences ->
            preferences[SELECTED_MODEL_NAME] = fileName
        }
    }

    suspend fun clearSelectedModel() {
        dataStore.edit { preferences ->
            preferences.remove(SELECTED_MODEL_NAME)
        }
    }

    private companion object {
        val SELECTED_MODEL_NAME =
            stringPreferencesKey("selected_model_name")
    }
}
