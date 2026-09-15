# Explicit stable update integration contract

Status: implemented on the existing dotfiles branch; awaiting main verification
and merge. Firstmate-side integration is separately owned and is not included.

## Entry points

- `dev-tools-apply-updates --explicit --json` requests stable discovery and
  guarded convergence, including no-mistakes, and records unfinished work.
- `dev-tools-apply-updates --resume --json` makes one attempt at the recorded
  obligations. It re-discovers stable releases and re-verifies installed state
  and artifacts; a saved target never authorizes a later mutation by itself.
- Existing invocation, preview and attended receipt rollback remain supported.
  Herdr activation is excluded in every mode. Legacy invocation retains its
  original lane guards; the hook must use the explicit entry points above.

## Usage authority

Firstmate supplies `DEV_TOOLS_APPLY_USAGE_BIN`, an absolute executable path.
The updater invokes it as `<path> <tool-name>` without a shell, on initial
assessment and again immediately before each mutation, after artifact and
receipt work. It must return exit 0 with one JSON object:

```json
{"schema_version":1,"status":"idle","detail":"authoritative usage assessment"}
```

`status` is `idle`, `busy`, or `unknown`. Missing, failed, timed-out, malformed,
or unsupported responses mean unknown, never idle. The authority must assess
all users of the installation, including background services and active
no-mistakes run records after their workers exit. Process liveness alone cannot
establish no-mistakes idleness. It must not restart services or alter runs.
The existing Firstmate active-lane guard remains an independent veto.

The Firstmate integration owns providing this authoritative reader. Dotfiles
owns fail-closed consumption and fresh checks. Neither a cached idle result nor
a caller's assertion that its own workers finished authorizes installation.

## Durable retry ownership

Dotfiles owns a private, atomic obligations document alongside existing updater
receipts under `DEV_TOOLS_APPLY_RECEIPT_DIR`. It records intent before work,
retains busy, unknown and failed work across process death, and removes an
obligation only after confirmed convergence. Concurrent explicit attempts and
attended rollback of their receipts serialize with Linux `flock`. Platforms
without `flock` refuse. Use one stable state directory for each installation.
Receipts remain the mutation and attended rollback authority.

Firstmate owns invoking the one-shot `--resume` after all relevant users finish
and recovering outstanding obligations when its explicit integration resumes
after restart. No timer, daemon, periodic schedule, or live-service restart is
introduced. Repeated busy/unknown responses retain the obligation for a later
completion event or explicit resume.

## Output

JSON retains tier and receipt evidence and adds an `obligations` object with
its durable path and remaining tool names. Per-tool statuses distinguish
`applied`, `up_to_date`, `skipped`, `deferred`, `refused`, and `failed`.
Busy and unknown usage are deferred with an explanatory detail. Exit 0 means
the attempt completed safely, possibly with durable deferred work; exit 1
means refusal/failure; exit 2 means invalid invocation or unusable state.
Callers must inspect remaining obligations rather than equating exit 0 with
all updates installed. Herdr remains attended and cannot be activated here.
