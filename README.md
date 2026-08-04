# Monga

## v0.1 Skeleton Milestone

현재 상태는 Monga의 첫 안정 기준점입니다.

- Android 12 이상 지원
- Room 데이터 구조 구현
- Chat, Core Memory, Memory History, Settings, Backup and Restore의 5개 화면 구현
- Storage Access Framework 기반 JSON 백업/복원 골격 구현
- `testDebugUnitTest` 단위 테스트 통과
- `assembleDebug` 실행 및 debug APK 생성 성공
- Galaxy S22 실기기 설치 및 실행 성공

실제 AI 모델 추론은 아직 연결되지 않았으며, 현재 응답은 로컬 추론 연결 전 단계의 자리표시자입니다.

Android 12 이상에서 동작하는 완전 오프라인 AI 동반자 앱의 첫 번째 구현 단계입니다. 현재 응답은 로컬 추론 대신 명시적인 자리표시자 응답을 저장합니다.

## 구현 계획

1. Compose 단일 Activity와 Chat, Core Memory, Memory History, Settings, Backup & Restore 화면을 구성합니다.
2. Room에 Conversation, Message, CoreMemory, EpisodicMemory, DailySummary를 저장하고 Repository/ViewModel을 통해 UI와 연결합니다.
3. 날짜별 메시지 조회와 핵심 기억 CRUD를 제공합니다.
4. 모든 테이블을 버전이 포함된 JSON으로 내보내고 트랜잭션으로 복원합니다.
5. Storage Access Framework의 폴더 선택 및 문서 생성/열기로 백업 파일을 처리합니다.
6. Manifest에 인터넷 권한이 없는지 검사하고 단위 테스트 및 Android 빌드를 실행합니다.

## 주요 구조

```text
app/src/main/java/com/monga/app/
├── MongaApplication.kt
├── MainActivity.kt
├── data/
│   ├── local/      # Room entities, DAO, database
│   ├── backup/     # JSON snapshot codec, SAF backup store
│   └── MongaRepository.kt
├── ui/
│   ├── MongaApp.kt # navigation and five screens
│   ├── MongaViewModel.kt
│   └── theme/Theme.kt
└── util/DateTime.kt
```

## 로컬 빌드

JDK 17, Android SDK, Gradle 8.13이 준비된 환경에서 먼저 `gradle wrapper`로 래퍼 바이너리를 생성한 뒤 `gradlew.bat testDebugUnitTest assembleDebug`를 실행합니다.
