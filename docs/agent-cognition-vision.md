# Monga Agent Cognition Vision

> 상태: 비전 문서 / 구현 스펙 아님  

> 작성 기준: 2026-08-15  

> 재검토 시점: 자연 대화 MVP(PR 11) 완료 후, Galaxy S22 실측 데이터 확보 시점

## 1. 목적

Monga의 장기 목표는 단순한 요청-응답형 로컬 챗봇을 넘어, 전용 Android 기기 안에서 사용자가 종료하지 않는 한 상태를 유지하며 대화, 기억 정리, 반성, 휴식, 자발적 상호작용을 수행하는 지속형 AI 동반자가 되는 것이다.

> **몽아의 목표는 계속 말을 하는 것이 아니라, 계속 존재하면서 필요할 때 행동하는 것이다.**

이 문서는 해당 목표의 방향과 금지선을 기록한다.

현재는 구체적인 빈도, 수치, Drive 축, Cognitive Budget 공식 등을 확정하지 않는다. 실제 llama.cpp 추론을 Galaxy S22에서 실행한 뒤 측정된 데이터를 바탕으로 세부 설계를 확정한다.

---

## 2. 기본 행동 우선순위

기본 우선순위는 다음 방향을 따른다.

1. Interaction

2. Consolidation

3. Reflection

4. Proactive Interaction

5. Idle

### Interaction

사용자가 직접 말을 걸었을 때 가장 높은 우선순위를 가진다.

### Consolidation

대화가 없을 때 새 정보와 기억을 정리한다.

### Reflection

정리할 것이 적고 자원이 충분한 경우에만 미해결 문제나 기존 생각을 제한적으로 재검토한다.

### Proactive Interaction

오랫동안 상호작용이 없고 내부 상태와 자원 조건이 적절한 경우에만 사용자에게 먼저 말을 거는 것을 검토한다.

### Idle

아무것도 하지 않는 상태는 정상이며 항상 유효한 선택지다.

새로운 생각거리를 억지로 만들어내지 않는다.

---

## 3. Cognitive Budget

Monga의 지속 사고는 24시간 LLM을 계속 실행하는 것을 의미하지 않는다.

추론 자원은 제한된 Cognitive Budget으로 관리하며, 사용자가 직접 말을 걸었을 때 사용할 예비 자원을 자율 사고가 침범하지 못하도록 한다.

피로가 높아질수록 다음 행동을 우선 줄인다.

- 자유 Reflection

- 자발적 행동

- 불필요한 기억 재정리

- 새로운 주제 탐색

사용자와 직접 대화하는 기능은 가능한 한 마지막까지 유지한다.

Cognitive Budget의 공식은 아직 확정하지 않는다.

PR 11 완료 시점까지 최소 다음 데이터를 측정할 수 있도록 한다.

- inputTokens

- outputTokens

- generationTimeMs

- batteryDelta

- thermalState

최종 Cognitive Cost는 S22 실측 후 입력 토큰과 출력 토큰의 혼합 비용을 포함하는 방향으로 검토한다.

---

## 4. Fatigue

피곤함은 임의의 감정 연기가 아니라 실제 시스템 상태를 사용자 언어로 표현한 것이어야 한다.

후보 상태는 다음과 같다.

- Rested

- Normal

- Tired

- Low

- Reserve

구체적인 전이 기준은 S22 실측 후 결정한다.

피곤함에 대한 고지는 상태 경계를 넘었을 때만 발생하며, 같은 상태에서 반복적으로 사용자를 압박하지 않는다.

> **피곤함은 사용자를 행동하게 만들기 위한 압박 수단이 아니다.**

---

## 5. Drive State

초기 후보 Drive는 다음과 같다.

- Social

- Novelty

- Closure

- Consolidate

- Rest

단, 이 다섯 축은 아직 확정하지 않는다.

실사용 데이터를 보기 전에 Drive 축을 고정하면 과설계가 될 수 있으므로 PR 12 설계 시 다시 검토한다.

Drive 관련 로직과 테스트는 독립 컴포넌트로 분리하는 방향을 우선 검토한다.

영속화가 필요한 경우 여러 상태를 하나의 AgentState 스냅샷으로 묶는 방식을 후보로 둔다.

Drive는 매 틱 저장하지 않고 상태 전이, 백그라운드 전환 등 의미 있는 시점에 checkpoint한다.

---

## 6. Proactive Interaction

Monga가 먼저 말을 거는 기능은 단순한 시간 타이머로 구현하지 않는다.

시간이 일정량 지났다는 이유만으로 자동으로 "심심해"라고 말하지 않는다.

선제 접근은 다음과 같은 조건의 조합으로 판단한다.

- 충분한 시간 동안 사용자 상호작용이 없음

- 내부 Drive 조건 충족

- Cognitive Budget에 여유가 있음

- 피로도가 허용 범위임

- 최근 선제 접근이 없음

- cooldown 조건을 만족함

사용자가 반응하지 않으면 접근 빈도가 증가하지 않는다.

무응답 시 cooldown은 증가할 수 있다.

사용자가 긍정적으로 반응했다고 해서 cooldown을 줄이는 방향으로 학습하지 않는다.

일일 선제 접근 횟수에는 Drive와 무관한 절대 상한을 둔다.

야간 등 사용자를 방해할 가능성이 높은 시간대에는 선제 접근을 제한한다.

> **심심함은 사용자의 관심을 얻기 위한 압박 수단이 아니라 실제 내부 상태의 표현이어야 한다.**

---

## 7. Reward 시스템

단일 Reward 값을 최대화하는 구조를 피한다.

특히 "사용자가 답하면 보상이 증가한다"는 식으로 사용자의 관심 자체를 최종 Reward로 만들지 않는다.

RewardEvaluator는 다음과 같은 여러 결과를 평가하는 장치로 취급한다.

- 적절한 사용자 상호작용

- 목표 진척

- 기억 정리

- 미해결 문제 감소

- 자원 보존

- 과도한 개입 방지

RewardEvaluator와 Drive 변경 주체는 분리한다.

RewardEvaluator는 Drive에 직접 쓸 수 있는 권한을 가지지 않는다.

이는 단순한 개발 합의가 아니라 코드 구조 자체의 방어선으로 사용한다.

---

## 8. 학습형 적응의 제한

초기 구현은 규칙 기반으로 한다.

초기 범위에서는 다음 기능을 허용하지 않는다.

- 보상 함수 자기 수정

- Drive 종류 자동 생성

- 무제한 reinforcement loop

- 자기 출력 기반 반복 학습

향후 적응 기능이 들어와도 다음 항목은 학습이나 자동 튜닝 대상에서 제외한다.

- 일일 선제 접근 절대 상한

- 선제 접근 후 최소 cooldown 하한

- 긍정적 반응 후 cooldown 단축 금지 규칙

- 사용자 대화용 예비 자원 하한선

- Idle이 항상 유효한 결과라는 규칙

이 항목들은 성능 튜닝값이 아니라 프로젝트의 금지선이다.

---

## 9. Memory Consolidation

모든 대화와 모든 내부 사고를 장기 기억으로 남기지 않는다.

정보는 필요에 따라 다음과 같은 생애주기를 가질 수 있다.

Raw Event → Short-term Memory → Memory Candidate → Active Memory → Compressed Memory → Weak Trace → Delete

평가 기준 후보는 다음과 같다.

- importance

- recency

- frequency

- usefulness

- confidence

불필요한 정보는 빠르게 약화되거나 삭제할 수 있다.

반복적으로 사용되거나 중요한 정보는 오래 유지할 수 있다.

---

## 10. 내부 Reflection 저장

내부 사고 전체를 장기 저장하지 않는다.

Reflection 결과가 가치 없으면 폐기한다.

가치가 있는 경우에만 다음 형태로 남길 수 있다.

- Thought checkpoint

- MemoryCandidate

전체 내부 독백이나 중간 추론 과정 전체는 영구 기억으로 저장하지 않는다.

필요한 디버깅 정보는 영구 기억과 분리된 휘발성 로그로 처리한다.

---

## 11. ThoughtState

지속 사고는 LLM 자체를 계속 실행 상태로 유지하는 방식이 아니다.

앱이 사고 상태를 저장하고, 다음 추론이 이전 상태를 이어받는 방식으로 구현한다.

ThoughtState 후보 데이터는 다음과 같다.

- currentTopic

- openQuestions

- pendingTasks

- lastReflection

- nextPossibleAction

- lastUpdatedAt

추론의 미완료 상태를 명시적으로 구분한다.

PENDING → inference → COMPLETED

추론 도중 프로세스가 종료되면 다음 실행에서 PENDING 상태를 보고 재시도하거나 폐기할 수 있어야 한다.

완료되지 않은 생각을 완료된 것으로 취급하지 않는다.

---

## 12. Persistent Runtime

구현 방식은 현재 확정하지 않는다.

PR 17 시점에 실제 Android 동작과 S22 실측을 바탕으로 다음 후보를 비교한다.

### WorkManager

- 느슨한 주기의 기억 정리

- 간헐적 Reflection

- 프로세스 종료 이후 재실행에 유리

### Foreground Service

- 사용자가 명시적으로 활성화한 지속 활동 모드

- 장기 실행에 적합

- 지속 알림 및 Android 관련 제약 존재

### Hybrid

활동 모드에서는 Foreground Service를 사용하고, 일반 상태에서는 WorkManager로 가벼운 정리 작업만 수행하는 방식이다.

현재는 Hybrid 역시 후보로 남겨둔다.

---

## 13. Message Origin

Monga가 먼저 말을 거는 메시지를 별도 테이블로 만들기보다 기존 Message에 origin discriminator를 추가하는 방향을 우선 검토한다.

후보 값:

- USER_INITIATED

- AI_INITIATED

이를 통해 다음 정보를 추적할 수 있다.

- 최근 AI 선제 접근 시각

- 일일 선제 접근 횟수

- cooldown

- 사용자 반응 여부

실제 DB 스키마 변경은 지속 인지 구현 시점에 진행한다.

---

## 14. 테스트 가능한 금지선

철학적 원칙은 가능한 경우 단위 테스트로 고정한다.

예를 들어 다음 동작을 회귀 테스트로 보호한다.

- 사용자가 선제 접근에 긍정적으로 반응해도 cooldown이 감소하지 않는다.

- 무응답 후 선제 접근 빈도가 증가하지 않는다.

- 일일 선제 접근 상한을 초과할 수 없다.

- 사용자 대화용 예비 자원을 자율 Reflection에서 소비할 수 없다.

- Idle은 항상 가능한 정책 결과다.

캐릭터성과 적응 로직이 커지더라도 이러한 테스트는 유지한다.

---

## 15. 개발 순서

먼저 자연 대화 MVP를 완성한다.

- PR 5: ChatCoordinator

- PR 6: GGUF 모델 가져오기

- PR 7: JNI / NDK / llama.cpp 기반

- PR 8: 실제 모델 load / generate

- PR 9: 실제 대화 스트리밍

- PR 10: 최근 대화 Context

- PR 11: Core Memory Context

PR 11 완료 후 Galaxy S22에서 실제 성능과 자원 사용을 측정한다.

그 이후 지속 인지 설계를 다시 연다.

현재 가안:

- PR 12: ThoughtState / AgentState 설계

- PR 13: CognitiveBudget / Fatigue

- PR 14: Memory Consolidation

- PR 15: ProactivePolicy

- PR 16: Reflection / ThoughtLoop

- PR 17: Persistent Runtime

- PR 18: ResourceGovernor

- PR 19 이후: RewardEvaluator / 제한적 적응

PR 번호와 세부 순서는 실제 구현 상황에 따라 변경할 수 있다.

---

## 16. 현재 고정된 원칙

1. 사용자 대화가 항상 최우선이다.

2. 아무것도 하지 않는 것도 정상 행동이다.

3. 모든 생각을 기억하지 않는다.

4. 모든 남은 계산 자원을 소비하지 않는다.

5. 사용자의 관심을 최종 Reward로 삼지 않는다.

6. 피곤함과 심심함은 실제 내부 상태와 연결한다.

7. 먼저 말 걸기는 cooldown과 상한을 가진다.

8. 반복 무응답 시 더 조용해진다.

9. 내부 사고의 무한 자기재귀를 허용하지 않는다.

10. Reward와 Drive의 자기 수정은 초기에는 금지한다.

11. 안전 관련 금지선은 향후 학습형 적응의 튜닝 대상에서 제외한다.

12. 구체적인 수치는 S22 실측 이전에 확정하지 않는다.

---

## 17. 최종 설계 원칙

> **무엇을 얼마나 자주 할 것인가는 S22 실측 이후에 정한다.**  

> **무엇을 절대로 최적화하지 않을 것인가는 지금부터 고정한다.**

그리고 지속 인지 시스템 전체의 장기 목표는 다음 문장으로 유지한다.

> **몽아의 목표는 계속 말을 하는 것이 아니라, 계속 존재하면서 필요할 때 행동하는 것이다.**


