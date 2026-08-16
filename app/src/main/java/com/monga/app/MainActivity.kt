package com.monga.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.monga.app.ui.MongaApp
import com.monga.app.ui.MongaViewModel
import com.monga.app.ui.MongaViewModelFactory
import com.monga.app.ui.theme.MongaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as MongaApplication
        val repository = app.repository
        val chatCoordinator = app.chatCoordinator
        setContent {
            MongaTheme {
                val vm: MongaViewModel = viewModel(
                    factory = MongaViewModelFactory(
                        repository,
                        chatCoordinator,
                    )
                )

                MongaApp(vm)
            }
        }
    }
}

