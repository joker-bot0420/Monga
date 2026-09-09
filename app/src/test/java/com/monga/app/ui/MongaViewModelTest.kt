package com.monga.app.ui

import androidx.lifecycle.ViewModelStore
import com.monga.app.chat.ChatCoordinator
import com.monga.app.chat.ChatResult
import com.monga.app.data.MongaRepository
import com.monga.app.data.model.ModelPreferences
import com.monga.app.data.model.ModelStore
import com.monga.app.inference.LlamaModelLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyLong
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

@OptIn(ExperimentalCoroutinesApi::class)
class MongaViewModelTest {

    @get:Rule
    val mainDispatcherRule = MongaMainDispatcherRule()

    private val viewModelStore = ViewModelStore()

    @After
    fun tearDown() {
        viewModelStore.clear()
    }

    private data class Fixture(
        val vm: MongaViewModel,
        val repository: MongaRepository,
        val coordinator: ChatCoordinator,
    )

    private fun fixture(): Fixture {
        val repository = mock(MongaRepository::class.java)
        val coordinator = mock(ChatCoordinator::class.java)
        val modelStore = mock(ModelStore::class.java)
        val modelPreferences = mock(ModelPreferences::class.java)
        val llamaModelLoader = mock(LlamaModelLoader::class.java)

        `when`(repository.conversations).thenReturn(flowOf(emptyList()))
        `when`(repository.coreMemories).thenReturn(flowOf(emptyList()))
        `when`(repository.episodicMemories).thenReturn(flowOf(emptyList()))
        `when`(repository.dailySummaries).thenReturn(flowOf(emptyList()))
        `when`(modelPreferences.selectedModelName)
            .thenReturn(flowOf<String?>(null))

        val vm = MongaViewModel(
            repository = repository,
            chatCoordinator = coordinator,
            modelStore = modelStore,
            modelPreferences = modelPreferences,
            llamaModelLoader = llamaModelLoader,
        )

        viewModelStore.put("test", vm)

        return Fixture(vm, repository, coordinator)
    }

    private suspend fun stubSend(
        coordinator: ChatCoordinator,
        result: ChatResult,
        onSend: (String, (String) -> Unit) -> Unit = { _, _ -> },
    ) {
        // Mockito의 null 매처를 Kotlin의 non-null 함수 인자에 전달하기 위한
        // 테스트 전용 제네릭 어댑터.
        fun <T> anyKotlin(): T = org.mockito.ArgumentMatchers.any<T>()

        doAnswer { invocation ->
            val text = invocation.getArgument<String>(1)
            val onSaved =
                invocation.getArgument<(String) -> Unit>(2)

            onSend(text, onSaved)
            result
        }.`when`(coordinator).send(
            anyLong(),
            anyString(),
            anyKotlin(),
            anyKotlin(),
        )
    }

    @Test
    fun savedNotificationClearsDraft() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        var submittedText: String? = null

        stubSend(
            coordinator = f.coordinator,
            result = ChatResult.Completed,
            onSend = { text, onSaved ->
                submittedText = text
                onSaved(text)
            },
        )

        f.vm.editChatDraft("  안녕  ")
        f.vm.sendChatDraft()
        runCurrent()

        assertEquals("  안녕  ", submittedText)
        assertEquals("", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
    }

    @Test
    fun failedSendWithoutSavedNotificationRetainsDraft() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        val failure = IllegalStateException("save failed")

        stubSend(
            coordinator = f.coordinator,
            result = ChatResult.Failed(failure),
        )

        f.vm.editChatDraft("다시 보낼 메시지")
        f.vm.sendChatDraft()
        runCurrent()

        assertEquals("다시 보낼 메시지", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
        assertTrue(f.vm.notice.value.orEmpty().contains("save failed"))
    }

    @Test
    fun oldSavedNotificationDoesNotClearNewDraft() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        var oldCallback: ((String) -> Unit)? = null

        stubSend(
            coordinator = f.coordinator,
            result = ChatResult.Completed,
            onSend = { text, onSaved ->
                oldCallback = onSaved
                onSaved(text)
            },
        )

        f.vm.editChatDraft("첫 메시지")
        f.vm.sendChatDraft()
        runCurrent()

        assertEquals("", f.vm.chatDraft.value.text)
        assertNotNull(oldCallback)

        // 이전 전송 이후 사용자가 같은 문장을 다시 입력한다.
        f.vm.editChatDraft("첫 메시지")
        oldCallback!!.invoke("첫 메시지")

        assertEquals("첫 메시지", f.vm.chatDraft.value.text)
    }

    @Test
    fun conversationCreationFailureRetainsDraftAndReportsError() = runTest {
        val f = fixture()
        val failure = IllegalStateException("create failed")

        doAnswer {
            throw failure
        }.`when`(f.repository).createConversation()

        // 대화를 선택하지 않은 상태이므로 새 대화 생성 경로로 들어간다.
        f.vm.editChatDraft("보존할 메시지")
        f.vm.sendChatDraft()
        runCurrent()

        assertEquals("보존할 메시지", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
        assertTrue(f.vm.notice.value.orEmpty().contains("create failed"))
    }

    @Test
    fun editBeforeSavedCallbackRetainsNewDraft() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        stubSend(
            coordinator = f.coordinator,
            result = ChatResult.Completed,
            onSend = { text, onSaved ->
                // 저장 완료 알림이 오기 전에 사용자가 입력을 수정한다.
                f.vm.editChatDraft("새로 작성한 초안")
                onSaved(text)
            },
        )

        f.vm.editChatDraft("전송할 메시지")
        f.vm.sendChatDraft()
        runCurrent()

        assertEquals("새로 작성한 초안", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
    }

    @Test
    fun duplicateSendBeforeCoroutineStartsIsIgnored() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        val submittedTexts = mutableListOf<String>()

        stubSend(
            coordinator = f.coordinator,
            result = ChatResult.Completed,
            onSend = { text, onSaved ->
                submittedTexts += text
                onSaved(text)
            },
        )

        f.vm.editChatDraft("한 번만 전송")
        f.vm.sendChatDraft()
        f.vm.sendChatDraft()

        // 아직 예약된 코루틴을 실행하지 않았으므로 전송은 시작되지 않았다.
        assertTrue(f.vm.isGenerating.value)
        assertTrue(submittedTexts.isEmpty())

        runCurrent()

        assertEquals(listOf("한 번만 전송"), submittedTexts)
        assertEquals("", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
    }

    @Test
    fun clearingViewModelBeforeSendStartsResetsGeneratingState() = runTest {
        val f = fixture()
        f.vm.selectConversation(1L)

        f.vm.editChatDraft("보존할 초안")
        f.vm.sendChatDraft()

        // StandardTestDispatcher에서는 전송 코루틴이 아직 실행되지 않았다.
        assertTrue(f.vm.isGenerating.value)

        // 코루틴 본문이 시작되기 전에 ViewModel을 종료한다.
        viewModelStore.clear()
        runCurrent()

        assertEquals("보존할 초안", f.vm.chatDraft.value.text)
        assertFalse(f.vm.isGenerating.value)
    }

}

@OptIn(ExperimentalCoroutinesApi::class)
class MongaMainDispatcherRule(
    private val dispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {

    override fun starting(description: Description) {
        Dispatchers.setMain(dispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}
