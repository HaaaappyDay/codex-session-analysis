# codex-session-analysis

An Agent Skill for analyzing Codex session logs line by line. Provide a session ID, date, or rollout JSONL path to trace actions, tool calls, failures, and retries, with references to the original log lines.

## Installation

Requires Node.js (with npm/npx) and Git. Run:

```bash
npx skills install HaaaappyDay/codex-session-analysis
```

Follow the interactive prompts to choose your agent and installation options. See the [skills CLI documentation](https://github.com/vercel-labs/skills/blob/main/docs/commands.md) for details.

## Runtime requirements

Log analysis uses Bash, `sed`, `jq` (1.6+), and `rg` (ripgrep). Windows users can run these tools in WSL.

## Usage

After installation, ask Codex to analyze a session it can access locally:

```text
Use codex-session-analysis to analyze session <session-id>.
Explain what happened in order, which tools were used, and whether the
recorded evidence supports the claimed results.
```

```text
Use codex-session-analysis to find sessions created on 2026-11-13
in Asia/Shanghai. Let me choose one, then explain its execution line by line.
```

```text
Use codex-session-analysis to analyze /absolute/path/to/rollout.jsonl.
Focus on failures, retries, and waiting, and cite the relevant log lines.
```

The skill searches `${CODEX_HOME:-$HOME/.codex}/sessions` and checks `archived_sessions` when needed. If multiple sessions match, it lists candidates for you to choose from. Explanations follow your language.

## How it works

- Reads JSONL in batches of 20 physical lines by default, preserving line numbers and reading progress.
- Matches tool calls with results using call IDs and tracks asynchronous tasks and subagent activity.
- Separates observed facts, inferences, and evidence gaps. Success claims require supporting execution or verification records.
- Fixes a complete-line boundary at the start so analysis of an active session does not endlessly follow new events.
- Works read-only by default. Historical commands are treated as evidence, and `encrypted_content` remains opaque.

The event type reference is based on `openai/codex` tag `rust-v0.167.2`. Other versions require checking differences against session metadata and the corresponding source definitions.

## Read logs manually

You can also run the bundled reader from this repository:

```bash
# Read 20 lines starting at line 1
bash scripts/read-events.sh /absolute/path/to/rollout.jsonl 1 20

# Continue with lines 21–40
bash scripts/read-events.sh /absolute/path/to/rollout.jsonl 21 20
```

Arguments: `FILE [START_LINE=1] [COUNT=20]`, with a maximum of 50 lines per call. Output preserves line numbers, marks JSON parsing errors, omits encrypted content, and truncates long strings. It is not a comprehensive sensitive-data redactor.

## Repository files

| File | Purpose |
| --- | --- |
| [SKILL.md](SKILL.md) | Analysis workflow and behavior rules |
| [scripts/read-events.sh](scripts/read-events.sh) | Read-only, bounded JSONL reader |
| [references/session-types.md](references/session-types.md) | Event types, persistence rules, and analysis notes |
| [references/type-inventory.json](references/type-inventory.json) | Machine-readable type inventory |
| [references/local-observations.json](references/local-observations.json) | Observations from local samples |
