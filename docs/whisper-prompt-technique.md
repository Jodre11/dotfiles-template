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

Set the `WHISPER_PROMPT` variable in `config.env`:

```sh
WHISPER_PROMPT="Software engineering discussion at Acme Corp. The OrderService API..."
```

Or edit `hammerspoon/.hammerspoon/init.lua` directly — the `WHISPER_PROMPT` variable is near the
top of the file.

## Tips

- Keep the prompt under ~200 tokens (roughly 150 words). Longer prompts slow down inference
  without proportional accuracy gains.
- Refresh the prompt quarterly as your vocabulary evolves.
- Acronyms work best when used in a sentence: "The CQRS pattern in the OrderService" rather
  than just "CQRS OrderService".
