# Monga

Monga는 Android 기기에서 완전히 로컬로 동작하는 개인 AI 동반자 앱입니다.

현재 개발 기준 기기는 Galaxy S22이며, GGUF 모델을 llama.cpp를 통해
기기 내부에서 직접 실행합니다.

인터넷 기반 AI API에 의존하지 않고 대화, 기억, 모델 추론을
로컬에서 처리하는 것을 목표로 합니다.

---

## 현재 개발 상태

현재 Monga는 초기 UI skeleton 단계를 넘어
실제 로컬 AI 대화 파이프라인이 동작하는 Early Alpha 단계입니다.

현재 구현된 주요 기능:

- Android 12 이상 지원
- Kotlin + Jetpack Compose UI
- Room 기반 로컬 데이터 저장
- Conversation / Message 저장
- Core Memory CRUD
- Episodic Memory / Daily Summary 데이터 구조
- Settings
- JSON Backup & Restore
- Storage Access Framework 기반 백업 파일 처리
- GGUF 모델 가져오기 및 로컬 저장
- llama.cpp 기반 로컬 모델 로드
- JNI 기반 Kotlin ↔ native inference 연결
- SYSTEM / USER / ASSISTANT 구조화 메시지
- llama.cpp chat template 적용
- 토큰 단위 streaming generation
- generation 취소
- 최근 대화 문맥 전달
- Core Memory 기반 system prompt
- 정확한 chat-template token 계산
- context budget 초과 시 오래된 대화 턴 제거
- native model context hard guard

Galaxy S22 실기기에서 모델 로드, 대화 생성 및 streaming 응답을
확인한 상태입니다.

---

## 현재 대화 처리 흐름

```text
사용자 입력
    ↓
Room에 USER 메시지 저장
    ↓
Core Memory 기반 SYSTEM prompt 생성
    ↓
최근 대화 메시지 조회
    ↓
SYSTEM / USER / ASSISTANT 메시지 구성
    ↓
chat template 적용 및 token 수 계산
    ↓
context budget 검사
    ↓
필요 시 오래된 대화 턴 제거
    ↓
llama.cpp 로컬 추론
    ↓
token streaming
    ↓
화면 출력
    ↓
Room에 ASSISTANT 메시지 저장
```

현재 최근 대화는 최대 20개 메시지를 가져옵니다.

---

## Context Budget

현재 사용 중인 모델은 32768 token의 training context size를 보고합니다.

다만 모바일 환경에서의 메모리 사용량과 prompt prefill 비용을 제한하기 위해
Monga는 현재 4096 token을 operational context budget으로 사용합니다.

실제 사용 가능한 context 크기는 다음 중 작은 값입니다.

```text
min(model context size, runtime context budget)
```

generation 전에 실제 llama.cpp chat template을 적용한 prompt의 token 수를
계산합니다.

```text
prompt tokens + generation reserve > context budget
```

인 경우 오래된 대화 턴부터 제거합니다.

그래도 context에 들어가지 않는 경우 generation을 시작하지 않습니다.

native 계층에서도 모델이 지원하는 최대 context를 넘는 요청을 다시 차단합니다.

---

## Memory

현재 Monga의 기억 구조는 다음과 같습니다.

```text
Recent Conversation
├─ 현재 대화를 이어가기 위한 단기 문맥
└─ 최대 20개 최근 메시지

Core Memory
├─ 사용자가 직접 관리하는 핵심 기억
└─ system prompt에 포함되어 추론에 사용

Episodic Memory
└─ 데이터 구조 구현

Daily Summary
└─ 데이터 구조 구현
```

현재 Core Memory는 실제 system prompt에 사용됩니다.

다만 Core Memory 자체의 별도 token budget은 아직 구현되지 않았습니다.

따라서 다음 주요 개발 단계에서는 Core Memory가 전체 context를 과도하게
점유하지 않도록 별도의 budget 정책을 추가할 예정입니다.

Episodic Memory와 Daily Summary는 아직 실제 inference context 선택에
적극적으로 사용되지 않습니다.

---

## 주요 구조

```text
app/src/main/java/com/monga/app/
├── MongaApplication.kt
├── MainActivity.kt
│
├── chat/
│   ├── ChatCoordinator.kt
│   ├── SystemPromptProvider.kt
│   ├── DefaultSystemPromptProvider.kt
│   ├── CoreMemoryProvider.kt
│   └── DefaultCoreMemoryProvider.kt
│
├── inference/
│   ├── InferenceEngine.kt
│   ├── LlamaInferenceEngine.kt
│   ├── LlamaNativeBridge.kt
│   ├── LlamaModelLoader.kt
│   ├── ContextBudgetPolicy.kt
│   └── Utf8StreamDecoder.kt
│
├── data/
│   ├── local/
│   ├── backup/
│   ├── model/
│   └── MongaRepository.kt
│
└── ui/
    ├── MongaApp.kt
    ├── MongaViewModel.kt
    └── theme/
```

Native inference:

```text
app/src/main/cpp/
├── CMakeLists.txt
├── monga_native.cpp
└── third_party/
    └── llama.cpp
```

llama.cpp는 Git submodule로 고정된 commit을 사용합니다.

---

## 기술 스택

- Kotlin
- Jetpack Compose
- Room
- Kotlin Coroutines / Flow
- Android NDK
- JNI
- CMake
- llama.cpp
- GGUF

현재 Android native build는 arm64-v8a를 대상으로 합니다.

---

## 현재 개발 원칙

Monga는 기능을 한꺼번에 확장하기보다
작고 검증 가능한 단계로 개발합니다.

현재 우선순위는 다음과 같습니다.

```text
로컬 추론 안정화
    ↓
context 안전성
    ↓
Core Memory budget
    ↓
기억 계층화
    ↓
Episodic / Summary context 활용
    ↓
장기 기억 retrieval
    ↓
동반자 UX
    ↓
Alpha 안정화
```

현재 단계에서는 다음 기능을 의도적으로 먼저 도입하지 않습니다.

- Vector DB
- Embedding retrieval
- 자동 memory extraction
- RAG
- Agent loop
- 여러 모델 동시 실행
- 복잡한 tool calling

기억과 context 구조를 먼저 안정화한 뒤 필요성을 검증하면서 추가할 예정입니다.

---

## 테스트 및 검증

일반적인 개발 검증은 다음 순서로 수행합니다.

```powershell
.\gradlew.bat testDebugUnitTest `
    --no-daemon `
    --max-workers=1 `
    --project-prop=kotlin.compiler.execution.strategy=in-process

.\gradlew.bat assembleDebug `
    --no-daemon `
    --max-workers=1 `
    --project-prop=kotlin.compiler.execution.strategy=in-process
```

필요한 경우 native build를 별도로 확인합니다.

```powershell
.\gradlew.bat externalNativeBuildDebug `
    --no-daemon `
    --max-workers=1
```

최종적으로 Galaxy S22 실기기에 debug APK를 설치하여
model load 및 실제 streaming generation을 확인합니다.

---

## 다음 개발 단계

다음 주요 작업은 Core Memory Budget입니다.

목표:

- Core Memory가 전체 context를 무제한 점유하지 않도록 제한
- 기존 token counting 기능 재사용
- relevance scoring 없이 결정론적으로 memory 선택
- 최근 추가 또는 수정된 기억을 우선 유지
- 기존 ChatCoordinator / InferenceEngine 책임 분리 유지

이 단계가 완료된 뒤 Episodic Memory와 Daily Summary를 실제 inference
context에 어떻게 조합할지 설계합니다.