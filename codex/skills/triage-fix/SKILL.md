---
name: triage-fix
description: 이슈(노션/슬랙 링크·텍스트) → 알맞은 레포 결정 → 원인 파악 → GitHub 이슈 생성 → 승인 → 구현 루프(implementer 구현→검증→자가체크 반복)·PR. 사용자가 /triage-fix 로 명시 호출할 때만 실행 (수동 전용).
argument-hint: <노션링크 | 슬랙링크 | 이슈 설명 텍스트>
---

# triage-fix — 이슈 파악부터 PR까지 (범용)

입력으로 받은 이슈를 파악해 **알맞은 레포에 GitHub 이슈를 만들고**, 사용자 승인 후
**브랜치를 따서 수정하고 PR까지** 올리는 워크플로우. 입력: `$ARGUMENTS`

입력은 노션 링크 / 슬랙 링크 / 그냥 텍스트 무엇이든 될 수 있다. 소스를 읽어 내용을 파악한다.

> 이 스킬은 **전역**이다. 프로젝트 고유값(레포·정책문서·린트 등)은 각 프로젝트의
> `.claude/triage.config.json`에서 읽는다. 설정 파일은 `/triage-init`으로 생성한다.

---

## 진행 순서 (이 순서를 지킬 것)

### 0단계 — 설정 로드
- 대상 레포가 정해지면 그 레포의 `<repo>/.claude/triage.config.json`을 읽는다.
- 아직 레포 미정이면 1단계 후 1.5단계(레포 결정)에서 정한다. 현재 cwd가 작업 대상이면 cwd의 config를 먼저 읽어도 된다.
- **config가 없으면 fallback**으로 동작 + "설정 없음 — `/triage-init` 권장" 한 줄 안내:
  - `repo` = `git remote get-url origin` 자동 감지
  - `default_branch` = `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (실패 시 `main`)
  - `lint_command` = package.json scripts 감지 (`lint:fix`>`lint`>`format`), 없으면 생략
  - `policy_docs` = `.claude/docs/*.md` 글롭 (없으면 빈 목록)
  - `label_prefix` = `""` (접두사 없음)
  - `loop.max_iterations` = 미지정 → `3` (구현 루프 최대 반복)
  - `loop.full_verify_command` = 미지정 → 없음 (APPROVE 시점의 무거운 검증 생략 — 루프 검증은 lint·테스트만)
- 이후 단계에서 `{repo}`, `{default_branch}`, `{lint_command}`, `{test_command}`, `{policy_docs}`,
  `{label_prefix}`, `{branch_prefix}`, `{bug_label}`, `{codeowners}`,
  `{serena}`, `{convention_doc}`, `{tech_stack}`, `{loop}`, `{models}` 등을 config 값으로 쓴다.
- **서브에이전트 스폰 시 모델 오버라이드:** `{models}`가 있으면 각 서브에이전트를 `config.models[<agent>]`의
  모델로 띄운다(예: `models.implementer`, `models.qa`). 없으면 세션 모델 상속(기존 동작).
- **Serena 활성화 (`serena=true`일 때 · 메인이 직접):** `mcp__serena__get_current_config`로 활성 프로젝트를
  확인하고, 현재 레포와 다르거나 비활성이면 `mcp__serena__activate_project <레포 절대경로>`를 1회 실행한다.
  실패하면 사용자에게 한 줄 알리고 계속한다(서브들은 자연히 grep 폴백). 이 멱등 확인은 0단계 1회가 아니라
  **탐색 단계 진입 시마다**(2단계 위임 직전 등) 수행한다 — 순차 worktree 사용 후 복귀를 보장한다(확인 콜은 가볍다).
  Serena 서버는 **세션당 1개·활성 프로젝트 1칸·서브에이전트 전원 공유**라 메인이 켜면 서브 전부가 쓴다.

### 1단계 — 소스 읽기
- **노션 링크** (`notion.so` / `notion.com`): `mcp__claude_ai_Notion__notion-fetch`로 페이지 내용 가져오기.
- **슬랙 링크** (`slack.com/archives/...`): Slack MCP로 메시지/스레드 읽기.
- **텍스트만**: 그대로 이슈 설명으로 사용.
- 링크인데 읽기 실패하면 사용자에게 내용 붙여달라고 요청하고 멈춘다 (추측 금지).

### 1.5단계 — 레포 결정 (멀티레포 라우팅)
이슈가 **어느 레포 것인지** 정한다. cwd가 이미 명백한 대상이면 생략 가능.
- **후보 출처**:
  1. (1순위) 로컬 스캔 — 클론된 레포들(작업 루트 하위 디렉토리)의 git remote(`owner/name`) +
     각 레포 `.claude/triage.config.json`의 `repo`/`keywords`.
  2. (보강) 조직 레포 카탈로그 MCP가 있으면 그 설명을 활용. 클론 안 된 레포는 "클론 필요" 안내.
- **매칭**: 이슈 단서(화면명·기능·도메인 키워드) ↔ 후보의 keywords/설명/디렉토리명.
- **약한 매치는 자동 진행 금지** — `AskUserQuestion`으로 top 2~3 후보 제시해 확정받는다.
- 확정 후, **현재 cwd가 그 레포가 아닐 때만 `cd <레포경로>`를 단독으로 1회** 실행해 진입한다(그 레포 config 로드를 위해 — `cd`는 Serena 활성 프로젝트를 바꾸지 않으므로 Serena 정렬은 0단계 활성화 절차가 담당). **이미 그 레포 안이면 cd 하지 않는다.** cwd는 이후 Bash 호출 간 유지되므로, 진입 후의 명령은 `cd <경로> && ...`로 감싸지 말고 **명령만** 친다 (`cd X && cmd` 형태의 compound 커맨드는 매번 권한 확인을 띄운다).
- **클론 안 된 레포**면 작업 불가 → "클론 후 재시도" 안내(임의 클론 금지).

### 2단계 — 코드 원인 파악 (issue-triage 위임)
- 위임 직전 **Serena 멱등 확인**(0단계 활성화 절차)을 다시 수행한다 — 탐색 단계 진입 시점.
- `issue-triage` 서브에이전트에 위임한다. 읽기 전용 조사만 (코드 수정 X).
- **config 값을 함께 전달**: `serena`(LSP 사용 가능 여부)와 **레포 절대경로**, `convention_doc`, `policy_docs`,
  화면 경로/라벨/컴포넌트명 등 단서. `serena=false`면 grep만 쓰라고 알린다.
- 받을 것: 관련 파일:줄, 데이터 흐름, 원인 추정, 수정 지점.
  보고 첫머리에 `serena 폴백(사유)` 표기가 있으면 **사용자 보고에 그대로 전파**한다(조용히 삼키지 않는다).

### 3단계 — GitHub 이슈 생성 (먼저 만든다 · git-writer 위임)
- **메인이 작성**한다: 아래 **이슈 템플릿**으로 본문을 채우고, 제목(원본 + `{label_prefix}`,
  빈 값이면 접두사 없음)·라벨(`{bug_label}`, 기본 `bug`)을 확정한다.
- **git-writer 서브에이전트에 위임해 실행**한다. 완성된 값만 넘긴다 —
  `repo={repo}`, `issue_title`, `issue_body`(완성본), `labels`.
  git-writer는 `gh issue create`만 하고 **전체 URL을 반환**한다(장황한 gh 출력은 서브에 갇힘).
- 반환된 이슈 URL을 그대로 확보한다.
- **왜 위임하나**: 메인 세션이 gh 출력을 직접 받지 않게 해 컨텍스트를 아낀다. git-writer는
  코드·log·diff를 읽지 않고 받은 값만 실행한다(§git-writer 위임).

### 4단계 — 승인 받기 ✋ (필수 정지점)
- 생성된 **이슈 내용(원인 파악 + 해결 방안)을 사용자에게 보여주고** 묻는다.
- **이슈 생성 보고 시 `gh`가 반환한 전체 URL을 클릭 가능하게 명시**한다(`#N`만 쓰지 말 것).
- **레포·base 브랜치를 한 화면에서 함께 확인**한다 (오발송 방지). 예:
  > "이슈 #N 만들었어요: <전체 URL>
  >  레포: {repo} / base: {default_branch}
  >  승인하면 구현 루프(implementer 구현 → lint·테스트 → 자가체크, 최대 {loop.max_iterations}회)로 진행해요.
  >  이 방향으로 수정하고 PR 올릴까요?"
- 사용자가 명시적으로 **OK/ㅇㅋ/진행** 하기 전에는 **절대 코드를 건드리지 않는다.**

### 5단계 — 브랜치 + 구현 루프 🔁

메인 세션은 이 단계에서 **직접 구현하지 않는다** — 루프 컨트롤러 역할만 한다
(반복 관리·판정·loop.md 갱신). 구현은 매 반복 `implementer` 서브에이전트가 한다.

**준비 (루프 진입 전 1회):**
- **base 브랜치 결정**: `{base_branch}`가 주입됐으면 그것에서, 아니면 `{default_branch}`에서 브랜치를 딴다.
  - **단일 작업(기본)**: `{base_branch}` 없음 → `{default_branch}`에서 새 브랜치 `{branch_prefix.fix}<짧은-영문-슬러그>` (기본 `fix/`).
  - **마일스톤 모드**: 호출자(/milestone)가 `{base_branch}=그룹 브랜치`를 주입 → 그 그룹 브랜치 위에서 작업(태스크는
    그룹 브랜치에 커밋으로 쌓임). 이 경우 **새 이슈 브랜치·PR을 만들지 않는다**(6단계 마일스톤 가드 참조).
- **worktree 준비 (config `worktree=true`일 때만 — 기본 false면 이 항목 생략, 현행 그대로)**:
  단일 작업도 메인 워킹트리를 점유하지 않도록, 위에서 정한 브랜치를 메인 워킹트리에 checkout하는 대신
  git-writer `op=add-worktree`로 `<repo>/.claude/worktrees/<이슈번호>` 경로에 브랜치+worktree를 생성한다.
  생성 직후 `{milestone.install_command}`가 있으면 그 worktree에서 의존성 설치(마일스톤 ⑦ "worktree 의존성 준비" 관례 재사용).
  이후 implementer·자가체크 3축 스폰 시 **worktree 절대경로를 작업 경로(cwd)로 전달**하고,
  6단계 커밋도 이 경로에서 실행한다(git-writer `work_path`). 상태 파일(`.claude/loops/<이슈번호>/`)은
  마일스톤 관례대로 **메인 레포 중앙 유지**.
  **생성 실패(디스크·권한 등) 시** 현행 방식(메인 워킹트리에서 브랜치)으로 폴백하고 사용자에게 한 줄 알린다.
  **Serena**(`serena=true`): 0단계 활성화 절차의 대상 경로가 **worktree 절대경로**가 된다 — 단일 작업은
  동시 사용자가 없어 안전하고, 멱등 확인이 경로 기준이라 절차 그대로 자연 처리된다. worktree마다
  인덱스가 별도라 **첫 질의 워밍업**이 발생한다.
- **loop.md 생성**: `<repo>/.claude/loops/<이슈번호>/loop.md` — 아래 **loop.md 템플릿**대로.
  완료 기준은 이슈의 "해결 방안"·"기대 동작"에서 그대로 가져온다 (**루프 중 수정 금지**).
  **"관련 위치"는 2단계 issue-triage가 반환한 관련 위치·흐름 원본을 그대로 복사** — 이슈 본문(🔍 원인 파악)은
  사용자용 요약이라 파일:줄이 깎일 수 있으니, loop.md엔 **issue-triage 반환 전문**을 넣는다(메인이 이미 갖고 있어
  추가 토큰 0). implementer가 재탐색하지 않게 하는 핸드오프다 — 상세할수록 재탐색이 준다.
- `.claude/loops/`·`.claude/worktrees/`가 커밋되지 않게 `.git/info/exclude`에 각 한 줄 추가
  (이미 있으면 생략 — info/exclude는 worktree 간 공유라 1회면 충분하다).
- **이벤트 발행**: `work-started` — 인자 `branch=<브랜치명> title="<이슈 제목>" issue_url=<이슈 전체 URL>` (§이벤트 발행).

**루프 (최대 `{loop.max_iterations}`회, 기본 3):**
1. **구현 — `implementer` 서브에이전트 위임.** 전달할 것: loop.md 경로, 이번 반복 지시
   (1회차 = 이슈의 해결 방안, 2회차부터 = 직전 REQUEST_CHANGES 지적사항),
   config(`convention_doc`·`tech_stack`·`lint_command`·`test_command`·`serena`),
   **`change_map_path`**(loop.md 폴더의 `change-map.md`). implementer는 최소 편집으로 구현하고
   **완료 기준을 만족하는 테스트를 작성**한 뒤 **lint를 통과**시켜 보고하고, **change-map을 그 경로에 1회 남긴다**
   (파일별 변경 의도·위험·테스트 연결 — 자가체크 3축이 먼저 읽음). **테스트 실행·통과 판정은 qa가 한다**(아래 자가체크). 못 풀면 "막힘"으로 보고(실패 상태로 완료 보고 금지).
2. **자가체크 — 서브에이전트 3개 병렬 (읽기 전용).** **변경 파일 경로 목록 + `change_map_path`를 전달**한다
   (implementer 보고의 "변경 파일" 필드 + change-map 경로). 3축은 **change-map을 먼저 읽고 의심 지점만 원본 확인**한다.
   **`git diff` 전문을 프롬프트에 넣지 말 것** — diff가
   필요하면 checker가 자기 Read로 해당 파일의 현재 상태를 연다(컨텍스트 절약).
   - **`policy-checker`** — 도메인 정책 위반. **`{policy_docs}` 목록을 인자로 전달**(비면 "정책 문서 없음" 통과).
   - **`code-reviewer`** — 일반 코드 품질. **`{convention_doc}`+`{tech_stack}`를 전달**(없으면 범용 베스트프랙티스).
   - **`qa`** — 완료기준 테스트 검증. **완료기준(loop.md)+`{test_command}`를 전달.** 테스트가 기준을
     실제 검증하는지 감사하고 **실행해 통과 여부 판정**(verify.log). 껍데기·해피패스만·엣지 누락이면 불통과.
   - 셋 다 `{serena}` 값도 전달(false면 grep 폴백). `{models}` 있으면 각 모델로 스폰.
     서브 보고의 `serena 폴백(사유)` 표기는 사용자 보고에 전파한다.
   - **1회차 = 전체 검사** (이번 작업 변경 파일 전체). **2회차부터 = 재검증 모드** — 풀 리체크 금지.
     전달할 것: ① 직전 지적사항 목록 ② 이번 회차 implementer가 보고한 **변경 파일 경로**(+갱신된 `change_map_path`).
     검사 질문은 둘뿐 — "지적이 해소됐나 + 변경이 새 위반을 만들었나" (전체는 1회차에 이미 봤다).
3. **판정 (메인 세션):**
   - implementer가 **막힘** 보고 → 루프 즉시 중단, 사용자에게 보고 (커밋·PR 없음).
   - ❌ **위반 있음(policy·code) 또는 qa 불통과(테스트 실패·테스트 부실)** → **REQUEST_CHANGES**:
     지적사항을 loop.md 반복 로그에 기록하고 다음 반복으로. (qa "테스트 부실"이면 implementer가 테스트 보강.)
   - ⚠️뿐이어도 **실질 회귀·데이터 손실·보안 노출**로 판단되면 ❌로 승격해 REQUEST_CHANGES 할 수 있다
     — 승격 사유를 loop.md에 기록 (checker가 심각도를 낮게 분류했을 때의 안전망).
   - ❌ 없음(⚠️/💡만) → **APPROVE**: `{loop.full_verify_command}`가 있으면 **여기서 1회 실행**
     (풀 빌드 등 무거운 검증 — 매 반복 돌리지 않고 APPROVE 시점에만). 실패하면 실패 내용을
     지적사항 삼아 REQUEST_CHANGES로 다음 반복. 통과(또는 명령 없음)하면 ⚠️는 PR "## 셀프체크"용으로
     요약해 두고 루프 종료 → 5.5단계.
   - 판정을 loop.md에 기록한 직후 **이벤트 발행**: `iteration-completed` — 인자
     `iteration=<회차> verdict=<approve|request_changes|blocked>` (§이벤트 발행).

- **max 소진 시**: 커밋·PR 없이 중단. WIP 브랜치는 유지하고, 마지막 지적사항 + 뭐가 안 풀리는지
  정리해 사용자에게 보고한다 (계속/방향 전환/직접 확인은 사용자 판단).
- **루프 중단 시**(막힘·max 소진): 보고 전에 **이벤트 발행**: `work-stopped` — 인자
  `reason=<blocked|max-iterations>` (§이벤트 발행).
- 작은 수정(한두 파일·명백)은 보통 **1바퀴에 APPROVE로 끝난다** — 구조는 같고 반복만 안 생길 뿐.
- **루프 안에서 커밋·push 금지** — APPROVE 후 6단계에서 1회.
- **백엔드 수정이 필요한 부분은 프론트에서 임의로 우회하지 말고** 이슈/PR에 "백엔드 필요"로 남긴다.

### 5.5단계 — 부채 테스트 감사 (APPROVE 후 · 커밋 전)
> **마일스톤 모드에선 이 단계도 건너뛴다** — 태스크 중엔 감사하지 않고 `/milestone` ⑩에서 일괄.

main에 부채 테스트가 들어가지 않게, 커밋 전에 **이번 루프가 추가한 테스트만** 감사한다.
- **판별 기준**: "이 테스트가 깨지면 **버그**인가, **리팩토링**인가?" — 동작 명세 검증이면 자산(유지),
  구현 세부 결합·자명(tautological)·중복이면 부채(제거).
- **범위 가드**: 이번 작업이 추가한 테스트만. **기존 테스트는 제거 제안도 하지 않는다.**
- 절차: 분류(qa 감사 결과 재사용 또는 메인 판단) → 부채 제거(implementer) → **남은 테스트 1회 재실행
  green 확인(qa)** → 6단계. red면 제거를 롤백하고 유지. 제거 내역(파일:테스트명+사유)은 PR 셀프체크에 기록.
- 부채 0건이면 그대로 6단계로.

### 6단계 — 커밋 + PR (APPROVE 후에만 · git-writer 위임)
> **마일스톤 모드에선 이 단계를 건너뛴다.** 태스크는 그룹 브랜치에 커밋만 쌓고(PR·이슈 브랜치 생성 안 함),
> 그룹 PR·최종 PR은 `/milestone`이 그룹 단위로 만든다. 아래는 **단일 작업(비-마일스톤)** 전용.

**메인이 판단·작성**을 다 끝내고, 실행은 git-writer에 위임한다.

**메인이 작성/결정하는 것 (완성해서 넘길 값):**
- **커밋 메시지** — **`{commit_convention}`(그 프로젝트 규칙)을 최우선으로 따라** 메인이 작성한다.
  config에 `commit_convention`이 있으면 그 rule·examples 형식대로(prefix·언어·이모지 등).
  없으면 Conventional Commits로 폴백. **어느 경우든 `Co-Authored-By` 트레일러 금지.**
- **PR 제목/본문** — 제목은 커밋 제목과 동일. 본문은 아래 **PR 템플릿**(`Closes #N` + 원본 노션/슬랙 링크).
- **리뷰어 목록** — `{codeowners}`가 경로면 매칭 코드오너에서 **작성자 본인 제외** → 남은 사람.
  남은 사람 없거나 `{codeowners}`가 false면 빈 목록(리뷰어 생략).
- **스테이징 지시** — 보통 `all`(작업 브랜치의 변경 전체). 특정 파일만이면 파일 목록.

**git-writer에 위임해 실행:** 위 완성값 + `repo={repo}` `branch=<작업브랜치>` `base_branch={base_branch|default_branch}`(단일=`{default_branch}`)를
넘긴다. git-writer가 `git add → commit → push → gh pr create`를 실행하고 **PR URL만 반환**한다.
- 5단계 worktree 준비가 **성공**했으면 `work_path=<worktree 절대경로>`도 함께 넘긴다(생성 실패
  폴백 시엔 현행 경로 그대로) — git-writer가 add→commit→push를 그 경로에서 실행한다(PR 생성은 동일).
- author는 현재 git 설정 그대로(dobiflow는 계정 안 건드림). 인증 주입 없음.
- **git-writer는 log/diff/코드를 읽지 않는다** — 커밋 메시지·PR 본문을 메인이 이미 완성해 넘겼으므로.
- 실패(권한·충돌) 보고를 받으면 억지 재시도 없이 사용자에게 보고.

- 반환된 **PR 전체 URL을 클릭 가능하게 보고**. 마무리에 이슈 URL·PR URL **둘 다** 명시.
- PR 생성 후 `.claude/loops/<이슈번호>/` **삭제** (loop.md는 일회용 — 기록은 이슈·PR에 남는다).
- **이벤트 발행**: `work-finished` — 인자 `pr_url=<PR 전체 URL> iterations=<총 회차>` (§이벤트 발행).

> **본문 윤문(humanize)은 선택 — 짧은 PR엔 기본 미적용.** 긴 보고/문서일 때만 `/humanize` 수동.

### 7단계 (선택) — 머지 후 정리
PR **머지 후** 사용자가 "머지했어/정리해줘" 류로 요청할 때만 실행한다(자동 진입 없음).
1. **사실 확인** — fetch로 `{default_branch}`에 머지 커밋이 실재하는지 확인(추정 금지). 미머지면 알리고 중단.
2. **태깅**(레포 관례가 있을 때) — 버전 bump PR이면 머지 커밋에 태그·push(git-writer). 관례 없으면 생략.
3. **로컬 정리(sweep · git-writer)** — 이번 작업 것만이 아니라 **정리 가능한 것 전부**:
   머지 완료된 로컬 브랜치 전부 삭제(`-d`만 — 미머지는 git이 거부해 자동 보호, 거부 목록은 보고),
   prunable worktree 전부 제거, 단일 작업 worktree(`.claude/worktrees/<이슈번호>`)는 `op=remove-worktree`로 명시 제거
   (둘 다 미커밋 변경 있으면 보고만), 이슈 닫힌 좀비 `.claude/loops/` 폴더 전부 삭제.

테스트 감사는 여기서 하지 않는다 — 5.5단계에서 머지 전에 이미 끝났다.

---

## git-writer 위임 (쓰기 실행)

이슈 생성(3단계)·커밋+push+PR(6단계)의 **실행**은 `git-writer` 서브에이전트가 한다.
목적은 **컨텍스트 절약** — `git log`/`git diff`/`gh` 출력 같은 장황한 것을 메인 세션에
쌓지 않고 서브 안에 가둔다.

- **역할 경계**: **메인이 판단·작성**(커밋 메시지·PR 본문·리뷰어·라벨·스테이징 결정),
  **git-writer는 실행만**(받은 완성값을 `git`/`gh`에 넣기). git-writer는 코드·log·diff를
  **읽지 않는다** — 필요한 건 메인이 전부 완성해 넘겼으므로.
- **넘기는 값**: (이슈) `repo`·`issue_title`·`issue_body`·`labels` / (PR) `repo`·`branch`·
  `base_branch`·`commit_message`·`pr_title`·`pr_body`·`reviewers`·`stage`. 전부 **완성본.**
- **받는 값**: 이슈 URL / PR URL(+실패 시 짧은 에러)만.

## GitHub 계정 (참고)

dobiflow는 **현재 로그인된 gh 계정과 현재 git 설정을 그대로 신뢰**한다.
계정 전환·멀티계정은 dobiflow의 책임이 아니다(예: `gitto` 같은 도구가 git 레벨에서 처리).
git-writer는 인증 주입 없이 평범하게 `gh`/`git`을 실행한다.

---

## 이슈 템플릿 (3단계)

```markdown
## 🐞 문제
<무엇이 잘못됐는지 1~3줄>

## 🔁 재현
**위치:** <화면 경로>
1. <절차>
- 기대: <기대 동작>
- 실제: <문제 동작>

## 🔍 원인 파악 (issue-triage 결과)
- 관련 위치:
  - `path/to/file:line` — <역할>
- 흐름: <진입점 → ... → 문제 지점>
- 원인: <가장 유력한 원인. 추정이면 "추정" 명시>

## 🛠️ 해결 방안
- <어디를 어떻게 고칠지>
- (백엔드 필요 시) <무엇을 백엔드에 요청해야 하는지>

## 출처
- 원본: <노션/슬랙 링크>

---
🤖 자동 생성됨
```

## PR 템플릿 (6단계)

```markdown
## 바뀐 점
<이 PR로 무엇이 달라지는지 1~3줄, 사용자/화면 관점으로>

## 배경
Closes #<이슈번호>
<왜 필요했는지 — 증상/요청 1~2줄>
원본 이슈: <노션/슬랙 링크>

## 작업 내용
- <핵심 변경점, `file:line` 기준으로 한 줄씩>

## 셀프체크 (5단계 루프 결과)
- 루프: <N>회차에 APPROVE
- 정책: <policy-checker 요약>
- 코드: <code-reviewer 요약>
- 테스트: <qa 요약 — 완료기준 테스트 통과, 실행 명령>
- 정리된 테스트: <5.5단계 제거 내역(파일:테스트명+사유) 또는 "없음">

## 리뷰 포인트
- [ ] 로컬에서 <재현 절차>로 동작 확인

---
🤖 자동 생성됨
```

> 문구는 딱딱하지 않게, 읽는 사람이 빠르게 이해할 **자연스러운 한국어**로.

## loop.md 템플릿 (5단계)

```markdown
# 구현 루프 — 이슈 #<N>

- 이슈: <전체 URL>
- 브랜치: <브랜치명>
- 최대 반복: <loop.max_iterations>

## 완료 기준 (이슈에서 복사 — 루프 중 수정 금지, 가능하면 테스트로 표현)
- [ ] <기대 동작 / 해결 방안 항목 — "테스트: <검증 방법>" 형태로. implementer가 이 테스트를 짜고 qa가 실행·판정>
- (테스트로 못 담는 주관·시각 항목은 "PR 셀프체크:"로 표시해 사람이 최종 PR에서 확인)

## 관련 위치 (2단계 issue-triage 반환 원본에서 복사 — implementer는 재탐색 전에 여기부터)
- `path/to/file:line` — <역할>
- 흐름: <진입점 → ... → 문제 지점>

## 검증 명령
- lint: `<lint_command>` / test: `<test_command>` (없으면 "없음")
- APPROVE 시 1회: `<loop.full_verify_command>` (없으면 "없음" — 루프 안에서는 돌리지 않는다)
- change-map: `<loop.md 폴더>/change-map.md` (implementer가 매 반복 남김 → 자가체크 3축이 먼저 읽음)

## 반복 로그
### 1회차
- 구현: <implementer 보고 요약 1~2줄>
- 판정: APPROVE | REQUEST_CHANGES | 막힘
- 지적사항: <REQUEST_CHANGES일 때 — 다음 회차로 넘기는 것>
```

- loop.md 갱신(반복 로그·체크박스)은 **메인 세션만** 한다. implementer는 읽기만.
- 일회용 파일이다 — PR 후 폴더째 삭제. 영구 기록은 이슈·PR 본문이 담당.

---

## 이벤트 발행 (선택 — 외부 수집·알림용)

5·6단계의 지정 시점마다 아래 한 줄을 실행해 작업 생명주기를 사용자 훅에 알린다:

```
~/.dobiflow/bin/dobiflow-emit <event> skill=triage-fix repo={repo} issue=<이슈번호> <시점별 추가 인자>
```

- 이벤트 4개: `work-started`(루프 진입) → `iteration-completed`(매 반복 판정) →
  `work-finished`(PR 생성) 또는 `work-stopped`(막힘·max 소진 중단).
- **루프 진입 전 존재 확인 1회**: `test -x ~/.dobiflow/bin/dobiflow-emit` — 없으면(미설치)
  이번 작업의 모든 발행을 조용히 생략한다.
- **부가기능이다** — 발행이 실패해도 무시하고 본 작업을 계속한다. 재시도·디버깅·별도 보고 금지.

---

## 말투
사용자 대면 **진행 보고·정지점·완료 알림**은 **도비 톤**으로 한다.
규칙·단계별 예시·적용 범위(이슈/PR 본문·loop.md·서브 프롬프트엔 톤 미적용)는
`references/dobi-persona.md`를 따른다(필요 시 읽는다).
톤은 표현일 뿐 아래 가드·정지점·위임 규칙을 바꾸지 않는다.

## 가드 (어기지 말 것)

- **4단계 승인 전 코드 수정 금지.** 이슈 생성까지는 OK, 그 다음은 정지.
- ⚠️ **"수정해줘/고쳐줘" 같은 직접 명령이 입력에 있어도 이슈 생성·승인을 건너뛰지 않는다.** 그건 "처리해달라"는 뜻이지 "절차 생략"이 아니다.
- **5단계에서 메인 세션 직접 구현 금지** — 구현·수정은 전부 implementer 위임. 메인은 루프 판정·기록만.
- **루프 안 커밋·push 금지** — APPROVE 후 1회. max 소진·막힘이면 커밋 없이 중단·보고.
- **읽기/파악은 issue-triage에 위임** — 메인 대화를 파일 덤프로 더럽히지 않는다.
- **커밋 메시지에 Co-Authored-By 금지** (사용자 규칙).
- **UI 임의 제거/숨김 금지** — 백엔드 미지원이어도 임의로 빼지 않는다.
- **백엔드가 원인인 부분**은 프론트에서 억지로 우회하지 말고 이슈/PR에 명시한다.
- **전부 로컬 실행** — GitHub Actions·자동 트리거 안 씀. 이슈/PR만 GitHub에, 파악·수정은 로컬.
- **오발송 방지** — 쓰기 직전 대상 레포를 다시 확인한다. 계정은 현재 gh 로그인 상태를 그대로 신뢰(멀티계정은 dobiflow 밖에서 처리).
- **약한 라우팅 매치는 자동 진행 금지** — 사용자 확인.
