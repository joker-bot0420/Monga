package com.monga.app

import android.app.Application
import com.monga.app.data.MongaRepository
import com.monga.app.data.backup.SafBackupStore
import com.monga.app.data.local.MongaDatabase

class MongaApplication : Application() {
    val repository by lazy {
        MongaRepository(MongaDatabase.create(this), SafBackupStore(contentResolver))
    }
}

