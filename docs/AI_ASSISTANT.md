# In-App + External AI Assistant

This project now includes a hybrid assistant:

1. In-app AI routing and actions (navigation + app-aware responses)
2. External AI fallback for general/supportive conversation

## Features

1. Available to all users, including `individual`
2. Detects app-related requests first
3. Executes app actions automatically (for example: "I want to go live")
4. Queries app data for in-app requests (for example: open counselor slots in same institution)
5. Uses external AI for non-app/general conversation

## External AI Configuration

You can now run hybrid external AI with OpenAI and/or Gemini.

Provider selector:

1. `EXTERNAL_AI_PROVIDER=auto|openai|gemini` (default: `auto`)

OpenAI keys (new names):

1. `OPENAI_API_KEY`
2. `OPENAI_BASE_URL` (default: `https://api.openai.com/v1`)
3. `OPENAI_CHAT_PATH` (default: `/chat/completions`)
4. `OPENAI_MODEL` (default: `gpt-4o-mini`)

OpenAI legacy names are still supported:

1. `EXTERNAL_AI_API_KEY`
2. `EXTERNAL_AI_BASE_URL`
3. `EXTERNAL_AI_CHAT_PATH`
4. `EXTERNAL_AI_MODEL`

Gemini keys:

1. `GEMINI_API_KEY`
2. `GEMINI_BASE_URL` (default: `https://generativelanguage.googleapis.com`)
3. `GEMINI_GENERATE_PATH` (default: `/v1beta/models/{model}:generateContent`)
4. `GEMINI_MODEL` (default: `gemini-2.5-flash`)

Source-file fallback (no dart-define needed):

1. Edit constants in `lib/features/ai/data/assistant_repository.dart`
2. Set `_externalAiProviderSource`
3. Set `_externalAiApiKeySource` and/or `_geminiApiKeySource`

## Example Run

```bash
flutter run -d chrome ^
  --dart-define=EXTERNAL_AI_PROVIDER=auto ^
  --dart-define=OPENAI_API_KEY=YOUR_OPENAI_KEY ^
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_KEY
```

PowerShell multiline with backtick:

```powershell
flutter run -d chrome `
  --dart-define=EXTERNAL_AI_PROVIDER=auto `
  --dart-define=OPENAI_API_KEY=YOUR_OPENAI_KEY `
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_KEY
```

## Live Auto-Create from AI

When AI executes "go live", it navigates to:

`/live-hub?openCreate=1`

Live Hub now auto-opens the create-live sheet when this flag is present and user permissions allow it.
