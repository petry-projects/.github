# Persona scaffold — copy me

Copy this directory to **`.github-private/personas/<id>/`** to onboard a new
agentic persona. It is governed by
[`standards/persona-standards.md`](../../persona-standards.md) and validated
against [`persona.schema.json`](../persona.schema.json).

## What's here

```
persona.yml            # the manifest (index-of-record) — fill every CHANGE-ME
README.md              # this file — replace with a short note about your persona
agents/                # (optional) drop a copilot-profile <id>.md here, or delete
prompts/               # (optional) workflow prompt library, or delete
evals/                 # STARTER dev/ + holdout/ pair — move it to .github-private
                       #   evals/<id>/ (NOT into personas/) so validate-cases.py
                       #   and holdout-guard.yml cover it. Do not keep it here.
```

Delete the layer directories you do not use — most personas use one or two.
The `evals/` starter is copied out to the repo `evals/<id>/` tree, not kept
inside `personas/<id>/`.

## Onboarding order

1. **Copy & rename.** `cp -r standards/personas/TEMPLATE .github-private/personas/<id>`.
2. **Pick your definition layer(s)** in `persona.yml` `definition.layers[]`.
   Prefer wrapping a vendored framework agent where a good upstream exists
   (pin `vendor_pin` to its `VENDOR.md`); layer local behavior via
   `local_overrides`, never by hand-editing `frameworks/`.
3. **Fill the trigger matrix.** One row per surface. `default_mode: advisory`.
   Every `write` surface needs a `gate_label`. Define an `opt_out_label`.
4. **Set the trust floor** (`[OWNER, MEMBER, COLLABORATOR]` unless you have a
   reason to differ).
5. **Add evals.** Move the starter into `.github-private` `evals/<id>/`: ≥
   `min_cases` held-out cases under `evals/<id>/holdout/` and proposer-visible
   cases under `evals/<id>/dev/`. See `.github-private` `evals/README.md`.
6. **Register the canary entry** — one `agents.<id>` block in
   `standards/canary-rings.json` (the *only* place rings are written). Point
   `persona.yml` `canary.agent` at it.
7. **Validate & scan.** Manifest validates against the schema; AgentShield passes;
   no immutable file touched.
8. **Roll out** `next → ring0 → ring1 → stable`, eval gate green before `stable`.

The full gate is the **Definition of Done** checklist in
[`persona-standards.md` §7](../../persona-standards.md).

## Worked example

**Murat** (`.github-private/personas/murat/`) wraps the vendored
`bmad-test-architecture` Test Architect — the reference for the
*wrap-a-vendored-agent*, advisory-everywhere path.
