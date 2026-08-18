# Whisper Prompt Technique

The push-to-talk dictation system in `hammerspoon/.hammerspoon/init.lua` uses `whisper-cpp` for
speech-to-text transcription. Whisper accepts a `--prompt` parameter that biases its vocabulary
towards specific terms — dramatically improving recognition accuracy for domain-specific jargon.

## How It Works

Whisper's prompt is not a system instruction — it's a conditioning prefix. The model treats it as
if it were the immediately preceding transcription, so it expects more text in the same style and
vocabulary. This means:

1. **Use complete sentences** — fragments don't condition the model effectively.
2. **Embed the exact spellings** — if you want "PostgreSQL" not "Postgres SQL", write "PostgreSQL"
   in the prompt.
3. **Use the terms in context** — "Deploy the Terraform module" works better than a bare list of
   words.

## Generating a Domain-Specific Prompt

### Step 1: Collect vocabulary

Gather terms from your work environment:

- **Repository names** — `gh repo list yourorg --limit 100 --json name -q '.[].name'`
- **PR titles** — `gh search prs --owner yourorg --limit 100 --json title -q '.[].title'`
- **Internal glossary** — acronyms, product names, service names, team names
- **Tech stack** — frameworks, libraries, tools, infrastructure components

### Step 2: Compose contextual sentences

Write 3-5 sentences that naturally incorporate your most common terms. The goal is density —
pack as many domain terms into natural-sounding sentences as possible.

**Bad** (bare list):
```
Terraform PostgreSQL Redis Kubernetes Docker NuGet xUnit
```

**Good** (contextual sentences):
```
Software engineering discussion. Deploy the Terraform module to the staging cluster.
The API uses PostgreSQL with Redis caching and runs on Kubernetes via Helm charts.
Run the xUnit tests with NSubstitute mocks and WireMock for HTTP stubs.
Check the Datadog monitors and OpenTelemetry traces for the payment service.
```

### Step 3: Test and iterate

1. Record a few test clips dictating typical sentences from your workday.
2. Transcribe with and without the prompt — compare accuracy.
3. Add terms that were misrecognised; remove terms you never actually say.

## Configuration

Edit the `WHISPER_PROMPT` variable near the top of `hammerspoon/.hammerspoon/init.lua`. It is a
plain Lua string concatenation — add a sentence as its own `..` line:

```lua
    .. "Software engineering discussion at Acme Corp. The OrderService API is deployed via Helm. "
```

`~/.hammerspoon/init.lua` is a Stow symlink to that file, so the edit is live once Hammerspoon
reloads its config (`hs -c 'hs.reload()'`, or the menu-bar Reload Config item).

This value is deliberately *not* hydrated from `config.env` — one line per sentence keeps
`.githooks/pre-commit` able to scan added lines individually, whereas a single long
`config.env` entry re-stages every term in the prompt on any edit and trips the identity guard.

## Hard limits and traps

Measured against whisper-cpp 1.9.2 with `large-v3-turbo-q8_0` on an Apple M4.

- **The prompt has a hard ceiling of `n_text_ctx / 2` tokens** — 224 for large-v3 — per
  `whisper-cli --help`. Overflow keeps the *last* tokens, so it silently eats the *front*
  of the prompt. No warning was emitted even at 4× the ceiling, and `-np` in init.lua
  would suppress one anyway, so **never assume you will be told**. Add vocabulary by
  displacing terms you no longer say, not by appending.
- **Never set `-mc 0`** (`--max-context 0`). The prompt reaches later decode windows via
  carried text context; with `-mc 0` biasing collapses — compound product names split into
  separate words and surnames become phonetic guesses. Verified by A/B.
- **`--carry-initial-prompt` is not needed.** It is the documented fix for prompt decay,
  but on a 45s two-window clip it produced byte-identical output — default context
  carrying already propagates the prompt.
- **`-ac` (`--audio-ctx`) below the default is unsafe as a blanket setting.** It bounds the
  encoder's audio context (1500 frames = 30s), so it is tempting: `-ac 1000` cut a 3s
  transcription from 1691ms to 1036ms with byte-identical text. But on a 45s clip it
  silently collapsed a whole clause, and `-ac 512` emitted the transcript twice. init.lua
  therefore applies it only to recordings under 15s.
- **Dictation longer than ~30s can silently lose a clause** at Whisper's window boundary.
  Confirmed independent of VAD, of `--no-fallback`, and of both flags above; decoding the
  affected window in isolation recovers the words, so the audio is intact. Dictate in
  bursts under 30s.

## Tips

- Refresh the prompt periodically as your vocabulary evolves, displacing stale terms.
- Acronyms work best when used in a sentence: "The CQRS pattern in the OrderService" rather
  than just "CQRS OrderService".
- To confirm a term is actually being biased, transcribe the same clip with and without
  `--prompt` — the difference is the prompt's contribution.
