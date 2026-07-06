# dobiflow 아키텍처 — 왜 이렇게 생겼나

> 한 줄 요약: dobiflow는 **라우터 → 순차 → evaluator 루프 ⊃ fan-out**의
> **페이즈별 4패턴 하이브리드**다. 각 페이즈에 그 페이즈의 병목에 맞는 패턴을
> 골라 썼다. "에이전트팀(A2A)"만 안 쓰는데, 그건 실수가 아니라 정론을 따른 것이다.

이 문서는 dobiflow가 어떤 멀티에이전트 패턴들을 **왜** 조합했는지를 설명한다.
"그냥 스킬 몇 개 짬뽕"이 아니라 의도적 설계라는 걸 코드와 문헌으로 보인다.

---

## 페이즈별 패턴 지도

```
/work <무엇이든>
  │
  ├─ [라우터]        입력 분류 → 버그(triage-fix) / 기능(task-run)
  │                  Routing
  │
  ├─ [순차]          1. 원인·영향 파악 (issue-triage 위임, 읽기 전용)
  │                  2. GitHub 이슈 생성
  │                  3. ✋ 승인 정지점
  │                  4. 설계(기능) / 해결 방안(버그)
  │                  Prompt chaining — 앞 단계 결과가 있어야 뒤가 돈다
  │
  └─ [evaluator 루프] 5. 구현 루프 (최대 3회)
        │            implementer 구현 → 검증 → 판정 → 재구현
        │            Evaluator–optimizer
        │
        └─ ⊃ [fan-out]  자가체크: policy-checker + code-reviewer 병렬 (격리)
                        Parallelization / sectioning
```

| 페이즈 | 쓰는 패턴 | 왜 이 패턴인가 |
|--------|-----------|----------------|
| `/work` 분류 | **Routing (라우터)** | 입력이 버그냐 기능이냐로 뚜렷이 갈리고, 각각 다른 워크플로우가 나음. 분류만 정확하면 됨. |
| 1–4단계 | **Prompt chaining (순차)** | 파악→이슈→승인→설계는 앞 결과가 있어야 뒤가 돈다. 순서가 고정이라 병렬화할 게 없음. |
| 5단계 루프 | **Evaluator–optimizer** | 구현(optimizer)과 검증(evaluator)을 명확한 완료 기준으로 반복. "그린 될 때까지" 개선. |
| 5단계 자가체크 | **Fan-out (sectioning)** | 정책 검사와 코드 리뷰는 서로 독립. 동시에 돌려 시간을 줄이고, **일부러 서로 안 보게** 해 판정 독립성을 지킴. |

---

## 안 쓰는 패턴: 에이전트팀(A2A) — 그리고 왜 안 쓰는지

dobiflow가 안 쓰는 유일한 패턴은 **에이전트팀**이다. 즉 에이전트끼리
직접 통신하고 서로 의견을 합의하는 구조(network / swarm, agent-to-agent).
지금 dobiflow의 서브에이전트들은 **전부 메인 세션을 경유**하고, 서로를 보지 못한다.

이건 의도적이다. 멀티에이전트 아키텍처 문헌은 dobiflow 같은 작업에서
에이전트팀을 **안 쓰는 게 맞다**고 한다:

1. **가장 단순한 것을 기본값으로, 복잡도는 입증될 때만** — 검증된 개선 없이
   복잡도만 올리는 건 안 함. dobiflow는 순차를 기본값으로 두고 병목 페이즈에만
   무거운 패턴을 얹었다.
2. **예측 가능하면 워크플로우, 못 하면 에이전트** — dobiflow 파이프라인
   (조사→이슈→구현→검증)은 고정·예측 가능하다. 자율 에이전트팀은 과잉.
3. **공유 컨텍스트·의존성이 강하면 멀티에이전트를 쓰지 마라** — 코딩 태스크는
   진짜 병렬화할 하위 태스크가 적고 순차 의존적이다. 단일/오케스트레이션이 낫다.
4. **토큰 경제성(약 15배 규칙)** — 멀티에이전트는 챗 대비 약 15배 토큰을 쓴다.
   dobiflow는 이미 무거운 워크로드라(1파일 수정에 서브에이전트 여러 회),
   A2A를 붙이면 비용만 폭발하고 성과는 불확실하다.

### 리뷰 독립성이라는 숨은 강점

`policy-checker`와 `code-reviewer`를 **일부러 서로 안 보게** 병렬로 돌리는 건
버그가 아니라 설계다. 두 검사가 서로의 판정을 보면 "쟤가 통과시켰으니 나도"라는
담합·노이즈가 생긴다. 격리해야 각자 놓친 걸 잡는다. **격리가 곧 품질이다.**

---

## 한 문장

dobiflow가 필요한 건 "더 많은 협업"이 아니라 **"더 넓은 병렬 격리"**다.
에이전트팀은 협업이 병목일 때 이득인데, dobiflow의 병목은 협업이 아니라
순차 대기다. 그래서 협업 구조(A2A)가 아니라 격리된 병렬(fan-out)을 넓히는 게
dobiflow의 올바른 진화 방향이다.

---

## 용어 빠른 참조

| 용어 | 뜻 | dobiflow에서 |
|------|-----|--------------|
| **Routing (라우터)** | 입력을 분류해 알맞은 경로로 보냄 | `/work`가 버그/기능 분류 |
| **Prompt chaining (순차)** | 고정된 단계를 차례로, 앞 결과를 뒤가 씀 | 1–4단계 |
| **Fan-out / fan-in** | 독립 작업을 동시에 뿌리고(out) 결과를 모음(in) | 자가체크 병렬 |
| **Evaluator–optimizer** | 생성↔평가를 완료 기준까지 반복 | 5단계 구현 루프 |
| **Orchestrator–workers** | 중앙이 동적으로 쪼개 위임·종합 (dobiflow의 메인 세션 역할) | 메인 세션이 서브에이전트 지휘 |
| **Agent team (A2A)** | 에이전트끼리 직접 통신·합의 | **안 씀 (의도적)** |

---

## 부작용 경계 (side-effect boundary)

dobiflow는 orchestrator-workers 패턴이라, **되돌리기 어렵거나 바깥으로 나가는 쓰기
(이슈·커밋·push·PR)는 메인 세션(오케스트레이터)이 독점**한다. 서브에이전트는
읽기·구현·판정만 하고 부작용을 내지 않는다 — 그래서 재시도해도 안전하고,
승인 게이트가 실제로 작동한다.

계정은 **현재 로그인된 gh 계정·현재 git 설정을 그대로 신뢰**한다. 계정 전환·멀티계정은
dobiflow의 책임이 아니다(예: `gitto` 같은 도구가 git 레벨에서 처리). dobiflow는
토큰 주입·계정 전환 로직을 두지 않고, `gh`/`git`을 평범하게 실행한다.

---

## 근거 문헌

- Anthropic — [Building effective agents](https://www.anthropic.com/research/building-effective-agents)
  (워크플로우 5종 정의, "start simple" 원칙)
- Anthropic — [Building a multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)
  (약 15배 토큰, breadth-first 적합·공유 컨텍스트 부적합)
- Claude — [Common workflow patterns for AI agents](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them)
  (패턴 중첩·하이브리드가 정석)
- LangGraph — [Multi-agent structures](https://langchain-opentutorial.gitbook.io/langchain-opentutorial/17-langgraph/02-structures/08-langgraph-multi-agent-structures-01)
  (network / supervisor / hierarchical 트레이드오프)
