# Trusted Windows tollgate orchestrator

Implementation is in progress under TG-AUTO-02-EXT. No live bridge execution or
scheduler registration is authorized in this implementation phase.

## Implemented foundation

`Orchestrator.Lock.ps1` exposes `Enter-TollgateOrchestratorLock`. The returned
FileStream must be held across prepare, executor, and reporter, then disposed in
`finally`. Acquisition errors must stop processing before any stage runs. A
contender must never interpret an acquisition failure as permission to proceed.
The persistent lock file is not a task status and must not be deleted on release.
The intended production location is `.tollgate-local/orchestrator/orchestrator.lock`.
All orchestrator invocations for this repository must use that same location.
This protects cooperating orchestrator processes; direct bridge invocations do
not acquire this lock and must not overlap a future orchestrated run.

`tests/Test-OrchestratorLock.ps1` tests duplicate acquisition, concurrent Windows
PowerShell process exclusion, and reacquisition after release. Its isolated
fixtures are retained in `tests/state/`; it never opens the real approval queue.

## Observed bridge integration contracts

- `prepare-tollgate-task.ps1` already calls `watch-tollgate.ps1 -StageResult`.
  Calling prepare therefore provides watcher then prepare without duplicate polling.
- The queue resides in `.tollgate-local/pending`. Invoke the existing executor with
  `-RunPending -TaskFile <canonical pending JSON>` only when an eligible task exists.
- Reporter accepts `-ResultFile` and owns terminal SHA validation and reported
  idempotency. The orchestrator must not manufacture or rewrite lifecycle records.
- The executor currently discovers Codex through `Get-Command codex`. A future
  adapter must discover a validated executable and expose its directory only in
  the executor child's environment, without permanent PATH changes.

## Remaining work

Iteration 2 adds `run-tollgate-orchestrator.ps1`, currently a synthetic-only entry
point with trusted scriptblock stage adapters. It holds the lock across prepare,
at most one pending execution, and completed/failed reporting. Adapters must return
exactly one integer exit code (zero for success); errors stop the pipeline and
release the lock. Routing does not alter lifecycle records. Reporter retains
responsibility for terminal validation and idempotency. Synthetic paths must be
under `tests/state/`; reparse points are rejected. Do not supply adapters from
approval contents or other untrusted data.

`tests/Test-OrchestratorRouting.ps1` verifies no-work, pending and terminal routing,
stage errors, pending preservation, and lock release using retained isolated
fixtures. Production adapter wiring into the entry point,
pipeline concurrency verification, and scheduler scripts remain unimplemented.
The entry point cannot yet run the production pipeline. Synthetic tests do not
establish real reporter SHA validation or actual Codex permission separation.

Implement the single entry point, isolated stage fixtures, child credential and
network configuration, CLI discovery, terminal/error routing, and current-user
scheduler install/uninstall scripts. Validate them using Windows PowerShell 5.1.
Lock tests alone do not demonstrate pipeline-wide duplicate prevention.
Live GitHub, actual Codex permission separation, scheduler operation, and unattended
E2E remain unverified and require the separately approved execution phase.

## Executor environment helper (iteration 3)

`Orchestrator.ExecutorEnvironment.ps1` discovers an existing `codex.exe` from an
explicit absolute local path or recursively within operator-supplied trusted
installation roots. It does not depend on PATH, hardcode version directories,
execute candidates, or select arbitrarily between multiple installations. Missing
or ambiguous results fail closed. Reparse entries are skipped during discovery;
explicit paths and root ancestors reject reparse points. The operator remains
responsible for trusting the installation contents; filename checks are not
publisher/signature verification.

`New-TollgateExecutorStartInfo` constructs but never launches a Windows PowerShell
child. It clears inherited environment variables and adds an OS/profile allowlist,
a child-only PATH with the selected Codex directory, an absent GitHub config path,
and disabled global/system Git configuration and interactive credential prompts.
No tokens, proxies, SSH agent variables or inherited Codex overrides are copied.
It does not modify the parent's environment or permanent PATH. Bridge arguments
are integrated by the iteration 4 stage adapter; entry-point wiring remains pending.

Environment scrubbing is not a network sandbox or filesystem credential barrier.
The retained user profile permits Codex authentication; accessible on-disk secrets,
credential managers, local Git configuration and tools colocated with Codex require
separate runtime permission verification. This helper grants no network permission
and makes no network calls. Actual Codex execution remains untested and unauthorized
in this local implementation phase.

`tests/Test-ExecutorEnvironment.ps1` uses inert executable fixtures under
`tests/state/environment-<GUID>/` and launches only a PowerShell environment probe.
It checks explicit/nested discovery, ambiguity, missing/relative/UNC rejection,
environment filtering, unchanged parent PATH, and isolation-path rejection.
Run locally with Windows PowerShell 5.1 using a process-only execution policy
override if local script policy requires it; no scheduler registration is involved.

## Bridge stage adapters (iteration 4)

`Orchestrator.BridgeStages.ps1` now builds production process descriptors for
prepare (which calls watcher), bounded `-RunPending -TaskFile -TimeoutSeconds`
execution, and `-Publish -ResultFile` reporting. The bridge directory is fixed
relative to this repository. Executor inputs must be direct pending JSON paths;
reporter inputs must be direct completed/failed JSON paths. The bridge retains
envelope, existence, SHA and idempotency validation. No lifecycle data is written
by these adapters. Reporter publication is implemented for future trusted-host
use only; it was not invoked in this iteration.

Executor descriptors use the discovery/environment helper. Prepare and reporter
retain the trusted host environment. Arguments are transported as quoted literal
values inside an encoded PowerShell command with named parameter splatting;
task contents are never evaluated. Child PowerShell uses a process-only execution
policy override. `Invoke-TollgateBridgeProcess` waits for completion, returns zero
only on success and throws on start/nonzero failures. It inherits output streams
to avoid redirected-pipe deadlocks. Executor timeout is delegated to the existing
bounded bridge; this runner adds no timeout for GitHub-facing stages.

`tests/Test-BridgeStages.ps1` passed under Windows PowerShell 5.1. It parses and
inspects generated commands without running them, checks literal transport for
spaces/apostrophes/metacharacters, rejects incorrect lifecycle paths and missing
Codex, and exercises process success/start/exit failures using harmless probes.
It also compares all six bridge file hashes before and after. Retained fixtures
are in `tests/state/adapters-<GUID>/`.

Production adapter wiring is complete (iteration 5 below); pipeline
concurrency verification and scheduler scripts remain to be completed. Live
bridge/Codex execution, publication, scheduler registration, on-disk credential
isolation and OS-level network enforcement remain unverified. No live queue was
opened by the adapter tests. The intended production lock/state locations remain
`.tollgate-local/orchestrator/orchestrator.lock` and `.tollgate-local/`.

## Entry-point integration (iteration 5; supersedes earlier remaining-work notes)

The single entry point now defaults to production bridge adapters, with a separate
`-Synthetic` parameter set for trusted local stage fixtures. Production state is
fixed at `.tollgate-local/` and the lock remains
`.tollgate-local/orchestrator/orchestrator.lock`. No production state override or
scriptblock injection is accepted. The lock covers prepare (including watcher),
bounded pending execution and terminal reporting. CLI discovery is deferred until
pending work exists; `-CodexExecutable` or `-TrustedSearchRoots` supplies trusted
operator configuration, and `-TimeoutSeconds` preserves the bridge timeout bounds.
The executor isolation directory is the lock directory, created during acquisition.
Do not invoke production mode during this local-only approval phase.

`tests/Test-EntryIntegration.ps1` copies the entry point and helpers byte-for-byte
into a retained isolated fixture repository and substitutes harmless bridge scripts.
It exercises real child PowerShell transport without invoking actual bridge/Codex
or GitHub. Windows PowerShell 5.1 checks passed for no-work without CLI discovery,
missing CLI failure, stage order/arguments, each stage failure, pending preservation,
and lock release. Existing synthetic routing regression also passed.

Pipeline concurrency verification and current-user scheduler install/uninstall
scripts remain outstanding. Actual credentials/network separation, real reporter
SHA/idempotency, scheduler operations and unattended E2E remain unverified.

## Scheduler entry points (manual development session)

The install/uninstall entry points are implemented. This work does not resume the
exhausted five-iteration executor, change approval comment `5563219043`, or produce
a tollgate terminal result. Its pending record remains pending. Earlier scheduler
and concurrency TODOs above are historical: the isolated concurrency suite exists
and passes; live acceptance remains outstanding.

`Orchestrator.Scheduler.ps1` contains definitions only. Dot-sourcing either entry
script returns without connecting to Task Scheduler. Registration/removal requires
explicit invocation with `&` or `powershell.exe -File`. `-WhatIf` validates the
installation configuration but does not even connect to Task Scheduler.

Future operator commands, **only after separate live-execution authorization and
resolution of the exhausted pending approval** (do not run during this session):

```powershell
# Set this to the absolute path of this checkout.
$repo = 'C:\path\to\android-ai-monga-kotlin-jetpack-compose'
& "$repo\tools\tollgate-orchestrator\install-tollgate-scheduler.ps1" -CodexExecutable 'C:\trusted\codex\codex.exe' -WhatIf
# Alternatively discover exactly one codex.exe beneath trusted installation roots:
& "$repo\tools\tollgate-orchestrator\install-tollgate-scheduler.ps1" -TrustedSearchRoots 'C:\trusted\CodexInstallation' -WhatIf
# Explicit registration; omit WhatIf only in the authorized live phase:
& "$repo\tools\tollgate-orchestrator\install-tollgate-scheduler.ps1" -CodexExecutable 'C:\trusted\codex\codex.exe'
# Explicit ownership-checked removal:
& "$repo\tools\tollgate-orchestrator\uninstall-tollgate-scheduler.ps1" -WhatIf
& "$repo\tools\tollgate-orchestrator\uninstall-tollgate-scheduler.ps1"
```

Use Windows PowerShell 5.1 as the normal current user. No administrator launch,
SYSTEM principal, highest run level, saved password or permanent PATH update is
needed. A machine policy that denies normal-user registration is a blocker; the
scripts propagate that error and do not attempt elevation or policy changes.

Configuration is fixed: a time trigger starts five minutes after installation,
repeats every five minutes indefinitely, and runs only while that user is logged
on (InteractiveToken, LeastPrivilege). It does not wake the machine, catch up
missed starts, or allow on-demand starts. Battery operation is allowed. IgnoreNew
prevents overlapping scheduler instances; the existing repository lock also
protects cooperating manual invocations. There is no scheduler execution time
limit, avoiding forced termination during a bridge stage; executor timeout defaults
to 300 seconds, configurable with `-TimeoutSeconds` (30..1800). Prepare/reporter
have no timeout, so a hung stage can block later runs and needs separate operator
recovery. Registration does not call a start API, but the enabled trigger can run
production work after five minutes.

The task lives in the root scheduler folder, named `Tollgate-Orchestrator-` plus
SHA-256 of the normalized repository path and current-user SID. Registration uses
TASK_CREATE only and refuses every existing task, including an owned one; a
concurrent collision also fails rather than overwriting. To change configuration,
explicitly uninstall then install. Uninstall checks the exact path, integration
marker, repository, SID, least-privilege interactive principal, single executable
action, absolute PowerShell/working-directory paths and action-argument hash before
removing that exact name. Missing tasks are a no-op; lookup/permission failures
are errors. Ownership metadata is an accidental-collision guard, not protection
against a malicious actor with permission to rewrite the task. Scheduler lookup
and deletion are not atomic against external task replacement.

The installer reuses `Resolve-TollgateCodexExecutable` and pins its validated
absolute result in encoded literal arguments to the existing orchestrator. No
Codex candidate or orchestrator is executed during install. If an installation
moves or disappears, explicitly reinstall with the new trusted path; discovery
never guesses between candidates. Uninstall needs no Codex installation. Perform
uninstall from the original checkout path and same user before moving the checkout;
a moved checkout derives a different task identity. Ambiguous/modified ownership
requires separate manual inspection, never wildcard cleanup. Uninstall removes
future scheduling and does not stop an already running process or touch any queue
record. Wait for an existing run to finish before reinstalling.

`tests/Test-Scheduler.ps1` copies entry scripts/helpers unchanged into a unique
`tests/state/scheduler-<GUID>/` fixture. Every COM construction is intercepted by
an in-memory scheduler fake with no start API. Tests cover side-effect-free import
and WhatIf, discovery failure, literal paths with spaces/apostrophes/metacharacters,
principal/schedule settings, create-only registration, exact owned removal, absent
tasks, unknown/modified collisions, race rejection and service errors. The encoded
action is parsed only; an inert orchestrator tripwire is never executed. Run it in
a separate Windows PowerShell process because its mocks are process-local:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tools\tollgate-orchestrator\tests\Test-Scheduler.ps1
```

Isolated tests establish configuration and routing behavior, not actual Task
Scheduler schema/service acceptance, normal-user machine-policy compatibility,
logged-on trigger execution or unattended E2E. Real reporter SHA/idempotency,
Codex credentials/filesystem separation and OS network enforcement remain live
acceptance issues. No live scheduler, production pipeline or publication is part
of this manual development session. No recovery/reclassification of approval
`5563219043` is performed or implied.
