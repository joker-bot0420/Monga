package com.monga.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.monga.app.data.local.CoreMemory
import com.monga.app.data.local.Message
import java.time.format.DateTimeFormatter

private enum class Destination(val route: String, val label: String) {
    Chat("chat", "Chat"), Core("core", "Core Memory"), History("history", "History"), Settings("settings", "Settings"), Backup("backup", "Backup")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MongaApp(vm: MongaViewModel) {
    val nav = rememberNavController()
    val snackbarHostState = remember { SnackbarHostState() }
    val backStack by nav.currentBackStackEntryAsState()
    val current = backStack?.destination?.route ?: Destination.Chat.route
    val notice by vm.notice.collectAsStateWithLifecycle()
    Scaffold(
        topBar = { TopAppBar(title = { Text("Monga") }) },
        bottomBar = {
            NavigationBar {
                Destination.entries.forEach { item ->
                    NavigationBarItem(selected = current == item.route, onClick = {
                        nav.navigate(item.route) { popUpTo(nav.graph.findStartDestination().id) { saveState = true }; launchSingleTop = true; restoreState = true }
                    }, icon = { Text(item.label.take(1)) }, label = { Text(item.label) })
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        LaunchedEffect(notice) {
            notice?.let { snackbarHostState.showSnackbar(it); vm.clearNotice() }
        }
        NavHost(nav, Destination.Chat.route, Modifier.padding(padding)) {
            composable(Destination.Chat.route) { ChatScreen(vm) }
            composable(Destination.Core.route) { CoreMemoryScreen(vm) }
            composable(Destination.History.route) { MemoryHistoryScreen(vm) }
            composable(Destination.Settings.route) { SettingsScreen(vm) }
            composable(Destination.Backup.route) { BackupScreen(vm) }
        }
    }
}

@Composable private fun ChatScreen(vm: MongaViewModel) {
    val conversations by vm.conversations.collectAsStateWithLifecycle()
    val messages by vm.messages.collectAsStateWithLifecycle()
    var input by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = vm::newConversation) { Text("새 대화") }
            conversations.take(3).forEach { c -> TextButton(onClick = { vm.selectConversation(c.id) }) { Text(c.title) } }
        }
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages, key = { it.id }) { MessageCard(it) }
            if (messages.isEmpty()) item { Text("Monga와 오프라인 대화를 시작하세요.") }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(input, { input = it }, Modifier.weight(1f), label = { Text("메시지") })
            Spacer(Modifier.width(8.dp))
            Button(onClick = { vm.send(input); input = "" }, enabled = input.isNotBlank()) { Text("전송") }
        }
    }
}

@Composable private fun MessageCard(message: Message) {
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) { Text(message.role.name, fontWeight = FontWeight.Bold); Text(message.content) } }
}

@Composable private fun CoreMemoryScreen(vm: MongaViewModel) {
    val memories by vm.coreMemories.collectAsStateWithLifecycle()
    var input by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("핵심 기억", style = MaterialTheme.typography.headlineSmall)
        Row { OutlinedTextField(input, { input = it }, Modifier.weight(1f), label = { Text("기억") }); Button(onClick = { vm.addMemory(input); input = "" }) { Text("추가") } }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) { items(memories, key = { it.id }) { MemoryEditor(it, vm) } }
    }
}

@Composable private fun MemoryEditor(memory: CoreMemory, vm: MongaViewModel) {
    var text by remember(memory) { mutableStateOf(memory.content) }
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) { OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth()); Row { TextButton({ vm.updateMemory(memory, text) }) { Text("저장") }; TextButton({ vm.deleteMemory(memory) }) { Text("삭제") } } } }
}

@Composable private fun MemoryHistoryScreen(vm: MongaViewModel) {
    val date by vm.selectedDate.collectAsStateWithLifecycle()
    val messages by vm.datedMessages.collectAsStateWithLifecycle()
    val summaries by vm.dailySummaries.collectAsStateWithLifecycle()
    val episodes by vm.episodicMemories.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Memory History", style = MaterialTheme.typography.headlineSmall)
        Row(verticalAlignment = Alignment.CenterVertically) { Button({ vm.changeDate(-1) }) { Text("이전") }; Text(date.format(DateTimeFormatter.ISO_DATE), Modifier.padding(16.dp)); Button({ vm.changeDate(1) }) { Text("다음") } }
        LazyColumn { item { Text("이날의 대화 (${messages.size})", fontWeight = FontWeight.Bold) }; items(messages, key = { "m${it.id}" }) { MessageCard(it) }; item { Text("일일 요약 (${summaries.size}) · 에피소드 기억 (${episodes.size})", Modifier.padding(top = 16.dp), fontWeight = FontWeight.Bold) } }
    }
}

@Composable private fun SettingsScreen(vm: MongaViewModel) {
    val selectedModelName by vm.selectedModelName.collectAsStateWithLifecycle()

    val modelLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let(vm::importModel)
    }

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall)
        ListItem(headlineContent = { Text("실행 모드") }, supportingContent = { Text("완전 오프라인") })
        ListItem(
            headlineContent = { Text("로컬 모델") },
            supportingContent = {
                Text(selectedModelName ?: "선택된 모델 없음")
            }
        )

        Button(
            onClick = {
                modelLauncher.launch(arrayOf("*/*"))
            }
        ) {
            Text("GGUF 모델 선택")
        }
        ListItem(headlineContent = { Text("최소 Android") }, supportingContent = { Text("Android 12 (API 31)") })
    }
}

@Composable private fun BackupScreen(vm: MongaViewModel) {
    val context = LocalContext.current
    val folderLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { it?.let { uri -> vm.export(context, uri) } }
    val fileLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::restore) }
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Backup and Restore", style = MaterialTheme.typography.headlineSmall)
        Text("선택한 Monga 폴더에 모든 대화와 기억을 JSON으로 저장합니다.")
        Button(onClick = { folderLauncher.launch(null) }) { Text("Monga 폴더 선택 및 내보내기") }
        OutlinedButton(onClick = { fileLauncher.launch(arrayOf("application/json", "text/json", "text/plain")) }) { Text("JSON 백업에서 복원") }
        Text("복원은 현재 데이터를 백업 내용으로 교체합니다.", color = MaterialTheme.colorScheme.error)
    }
}
