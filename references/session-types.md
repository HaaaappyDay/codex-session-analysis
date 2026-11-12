# Versioned Codex session type reference

## Scope and evidence

Checked on 2026-11-12 against **OpenAI's `openai/codex` repository, tag `rust-v0.167.2`**, matching the `cli_version` in the three local session files inspected. Full source files were fetched and the relevant enum definitions, serializers, payload structures, and persistence branches were read. This is an implementation reference for that release, not a public compatibility guarantee.

Source-confirmed names and persistence rules are distinguished below from analysis recommendations and local observations. For another version, consult its tag; retain unfamiliar records without silently normalizing or discarding them. Do not assume current `main` matches an installed binary.

Primary sources:

- [Rollout wire envelope](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/history/src/rollout_payload.rs): `RolloutItemWire`, custom serialization and compatibility transformations.
- [History types](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/history/src/lib.rs): `RolloutLine`, `RolloutItem`, `ResponseItemEnvelope`, `CompactedItem`.
- [Protocol events and metadata](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/protocol/src/protocol.rs): `EventMsg`, `SessionMeta`, `TokenUsageRecord`, `WorldStateItem`, `TurnContextItem`.
- [Model response types](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/protocol/src/models.rs): `ResponseItem`, message content, tool payloads and aliases.
- [Turn items](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/protocol/src/items.rs): the typed item inside `item_completed`.
- [Persistence policy](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/rollout/src/policy.rs): which records survive live append, including mode-dependent filtering and truncation.
- [Extension items](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/ext/items/src/lib.rs), [realtime items](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/protocol/src/realtime.rs), [retained context](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/history/src/retained_context.rs), [security scores](https://github.com/openai/codex/blob/rust-v0.167.2/codex-rs/protocol/src/security_risk.rs): specialized payload families.

[type-inventory.json](type-inventory.json) contains every variant in the explicitly indexed enums and selected nested schemas, wire names, aliases, source line numbers, source hashes, and persistence labels. Read it when a precise name or coverage check is needed. It is not a JSON Schema validator. Counts: 13 outer types; 18 ResponseItem variants (16 persistable); 86 EventMsg variants (including 2 non-serializable internal variants); 19 TurnItem variants; 3 extension kinds. Nested content and realtime variants are also indexed.

## Keep the protocol layers separate

A local rollout record has `timestamp`, optional `ordinal`, `type`, and `payload`; a `response_item` may also carry a sibling `metadata` object. `ordinal` is not a physical file line number. Retain both when present.

```text
record.type = response_item
  payload.type = function_call
record.type = event_msg
  payload.type = item_completed
    payload.item.type = CommandExecution
record.type = event_msg
  payload.type = item_completed
    payload.item.type = Extension
    payload.item.kind = web.search
```

The last two levels matter: `TurnItem` uses PascalCase names; extension `kind` uses a namespaced string. Some payload fields use camelCase, such as `McpToolCall`'s `connectorId`, `content` structures or extension-specific fields. Do not apply a blanket snake_case conversion to JSON keys.

`codex exec --json` stdout is a different event stream: its `item.completed` examples are documented in [OpenAI's skills evaluation guide](https://developers.openai.com/blog/eval-skills). App-server notifications and Responses API SSE are also distinct protocols. Do not copy their dotted or camelCase type names into a local rollout allowlist.

## All 13 outer types

Names and payload roles below are source-confirmed by the wire envelope and referenced payload definitions. The interpretation column gives analysis guidance.

| `record.type` | Payload and interpretation |
| --- | --- |
| `session_meta` | Session identity, CLI version, source, cwd, instructions, Git metadata when supplied, history mode and lineage. A fork or inherited prefix can contain metadata that needs identity reconciliation. |
| `dynamic_tools_updated` | `thread_id` and a complete `tools` catalog, including an empty catalog. Treat as replacement, not an incremental addition. |
| `response_item` | A model-history item; inspect `payload.type` and preserve optional sibling `metadata`. Not all entries are assistant outputs: user/developer messages also appear here. |
| `inter_agent_communication` | Agent author/recipient, other recipients, content, optional encrypted content and `trigger_turn`. Describe a communication, not proof of task execution. |
| `inter_agent_communication_metadata` | `trigger_turn` side metadata for communication. It is not an independent user instruction or a message body. |
| `compacted` | Compaction checkpoint: `message`, optional `replacement_history`, retained/guardian context, window identifiers, usage/resume information. Nested history may contain response items. It is not merely a UI notification. |
| `turn_context` | Durable per-turn configuration and context baseline, also recorded after relevant compaction. Read actual model, directory and permission fields rather than assuming they are unchanged. |
| `token_usage_record` | Best-effort usage for one completed response: `response_id`, `usage`, plus `turn_token_usage` and `thread_token_usage` totals. Do not sum the totals as per-response increments. |
| `world_state` | Resume baseline for model-visible state comparisons: `full=true` establishes a baseline; `full=false` updates it. Do not present a patch as a full filesystem snapshot. |
| `retained_context` | Host-side retained evidence updates. `verified_answer` is one subtype. The in-memory `delivered_assistant_message` variant is serialized as a compatibility `response_item/message` in this tag; never reinterpret assistant delivery as user authorization. |
| `security_risk_score` | Classifier scores with optional call/action attribution and sampling time. This is internal assessment metadata, not an execution result or proof of unsafe behavior. Summarize its role instead of treating scores as model reasoning. |
| `event_msg` | Runtime event payload; inspect its own `type`, persistence policy, and nested item when present. |
| `realtime_item` | Sparse presentation facts with `id`, `realtime_session_id` and flattened content type. Persisted only in paginated history by the inspected policy. |

Realtime subtypes: `realtime_session_started`, `transcript_segment` (role and text), `bem_item_promoted` (reference to an existing turn/item and presentation), and `realtime_session_closed` (outcome). The promoted item's presentation types are `whole_item`, `inline_markdown`, and `inline_visualization` (with an index). These are not ordinary model tool calls. See the linked realtime source.

## ResponseItem types: 16 durable, 2 excluded

All names below come from `ResponseItem` in models.rs, checked against `should_persist_response_item` in policy.rs.

| `payload.type` | Meaning and fields to inspect |
| --- | --- |
| `additional_tools` | Tool declarations available in model history; `role`, `tools`, optional ID. Not evidence that any tool ran. |
| `message` | `role`, `content`, optional `phase`, `status`, metadata and encrypted content. Inspect every content part. |
| `agent_message` | Structured agent-to-agent message: `author`, `recipient`, content. Distinct from an ordinary assistant `message` and from `event_msg/agent_message`. |
| `reasoning` | Visible `summary`, optional `content`, and optional `encrypted_content`; do not infer hidden text. |
| `local_shell_call` | Legacy shell call with optional `call_id`/ID, status, and an action such as `exec`. Inspect command, directory and timeout when present. |
| `function_call` | `name`, optional namespace, `call_id`, and JSON encoded as the `arguments` string. Parse arguments as data, never evaluate them. |
| `function_call_output` | `output` is a string or a structured-content array; `call_id` is optional in this version. Preserve unmatched outputs rather than forcing adjacency-based pairing. |
| `custom_tool_call` | Freeform tool `input`, tool name, call ID and optional namespace/status. Input is not necessarily JSON. |
| `custom_tool_call_output` | Output paired by `call_id`, with the same string-or-content-array encoding as function outputs. |
| `tool_search_call` | Tool discovery request: execution mode, structured arguments, optional call ID/status. Distinguish discovery from invoking a discovered tool. |
| `tool_search_output` | Returned tool declarations, status and execution mode. |
| `web_search_call` | Hosted search action and status. Actions include `search`, `open_page`, `find_in_page`, plus an unknown fallback; this is not the standalone extension record. |
| `image_generation_call` | Hosted image generation: status, revised prompt when present, result. Avoid rendering raw image bytes/base64 as text. |
| `compaction` | Opaque compaction item; accepts the deserialization alias `compaction_summary`. Not the same as outer `compacted`. |
| `configuration_update` | Durable backend input control at this history position, currently carrying reasoning configuration. Not user-facing answer text. |
| `context_compaction` | Context-compaction response item, optionally encrypted. Preserve separately from the checkpoint and UI events. |
| `compaction_trigger` | Defined request control, explicitly excluded from durable response items by this policy. Recognize if seen in another version/import; do not expect it in normal live appends. |
| `other` / unknown | `Other` is the Rust deserialization fallback and is excluded from persistence. When analyzing raw JSON, preserve the original unfamiliar type rather than rewriting it as `other`. |

Message `content[].type`: `input_text`, `input_image`, `input_audio`, `output_text`. Images/audio can use inline URLs or file IDs. Agent-message content supports `input_text` and `encrypted_content`. Reasoning summaries use `summary_text`; optional reasoning content supports `reasoning_text` and `text`. These are content discriminators, not rollout events. Function/custom-tool output arrays support `input_text`, `input_image`, `input_audio`, and `encrypted_content`. In contrast, `TurnItem/AgentMessage` content uses the PascalCase discriminator `Text`. The inventory keeps response-agent-message content and turn-agent-message content in separate groups; preserve their distinct structures.

`encrypted_content` is not exclusive to reasoning: this version also defines it on messages, several calls, compaction, and inter-agent content. Omit opaque content at any nesting level. Its presence does not establish that a readable reasoning summary exists.

## EventMsg persistence and meaning

The source declares 86 Rust variants. **This does not mean 86 event types normally appear in JSONL.** policy.rs filters live appends as follows:

| Class | Wire names | Interpretation |
| --- | --- | --- |
| Durable in both modes (7) | `task_started`, `task_complete`, `thread_settings_applied`, `token_count`, `thread_goal_updated`, `thread_rolled_back`, `turn_aborted` | Turn lifecycle, configuration, usage, goal updates and legacy rollback. `task_complete` says the turn ended, not that tests passed. Rollback changes the effective history being reconstructed. |
| Legacy-only (11) | `user_message`, `agent_message`, `agent_reasoning`, `agent_reasoning_raw_content`, `entered_review_mode`, `exited_review_mode`, `patch_apply_end`, `context_compacted`, `mcp_tool_call_end`, `web_search_end`, `image_generation_end` | Older display/result representations. In paginated history, look for typed completed items instead. |
| Conditional | `item_completed` | Paginated mode keeps all TurnItem variants. Legacy mode keeps only `FunctionCallOutput`, `Plan`, `Extension` with `kind=clock.sleep`, and `SubAgentActivity` with `kind=completed`. |
| Conditional | `sub_agent_activity` | Only legacy mode and only kinds other than `completed`; completion is represented as a typed completed item. |
| Transient (64) | Listed by family below and individually in the JSON inventory | Defined in the runtime protocol but filtered from normal live append at this tag. Recognize in older/imported/diagnostic logs without expecting their presence. |
| Internal only (2) | Rust `NetworkApprovalResolved`, `PrivateSessionEvent` | Marked `serde(skip)` and filtered. No normal serialized wire record is promised for these variants; their inventory names are descriptive, not an expectation of on-disk events. |

The serialized turn names are `task_started` and `task_complete`; deserialization accepts `turn_started` and `turn_complete` as aliases. Preserve the raw spelling and use a separate normalized label for grouping.

All transient families, with source-confirmed wire names:

| Family | Names | Analysis guidance if encountered |
| --- | --- | --- |
| Errors, recovery and notices | `error`, `warning`, `auth_recovery_started`, `auth_recovery_completed`, `guardian_warning`, `stream_error`, `deprecation_notice` | Distinguish terminal failure from warning/retry/recovery. An absent record does not establish error-free execution. |
| Model/safety presentation | `model_reroute`, `model_verification`, `turn_moderation_metadata`, `safety_buffering`, `guardian_assessment` | Routing or review state, not task success. Inspect reported status without inventing hidden decisions. |
| Session/environment/queue | `session_configured`, `environment_connected`, `environment_disconnected`, `thread_queue_changed`, `shutdown_complete` | Session configuration, connectivity, queued messages, and shutdown. |
| Realtime transport | `realtime_conversation_started`, `realtime_conversation_realtime`, `realtime_conversation_closed`, `realtime_conversation_sdp`, `realtime_conversation_list_voices_response` | Transport/lifecycle events; separate from durable `realtime_item` presentation facts. |
| MCP setup and calls | `mcp_startup_update`, `mcp_startup_complete`, `mcp_tool_call_begin`, `dynamic_tool_call_request`, `dynamic_tool_call_response` | Initialization versus invocation; inspect server/tool/call ID and structured result/error. |
| Command execution | `exec_command_begin`, `exec_command_output_delta`, `terminal_interaction`, `exec_command_end`, `view_image_tool_call` | Trace process invocation, output and interaction. `exec_command_output_delta.chunk` is Base64-encoded bytes in the protocol; decoding those bytes is valid and unrelated to decrypting `encrypted_content`. |
| Requests/approvals | `exec_approval_request`, `request_permissions`, `request_user_input`, `elicitation_request`, `elicitation_abandoned`, `apply_patch_approval_request` | A request is not an approval. Find the actual subsequent response/action evidence. |
| Patches, plans, media starts | `patch_apply_begin`, `patch_apply_updated`, `turn_diff`, `plan_update`, `web_search_begin`, `image_generation_begin` | Proposed/updated changes and progress; use completion payloads for results. |
| Raw output and item lifecycle | `raw_response_item`, `raw_response_completed`, `item_started`, `hook_started`, `hook_completed` | Backend/lifecycle or hook data; raw response events may mirror already recorded items. |
| Text/reasoning deltas | `agent_message_content_delta`, `plan_delta`, `reasoning_content_delta`, `reasoning_raw_content_delta`, `agent_reasoning_section_break` | Partial output or section boundaries, not independent full messages; only explain text actually visible. |
| Collaboration lifecycle | `collab_agent_spawn_begin`, `collab_agent_spawn_end`, `collab_agent_interaction_begin`, `collab_agent_interaction_end`, `collab_waiting_begin`, `collab_waiting_end`, `collab_close_begin`, `collab_close_end`, `collab_resume_begin`, `collab_resume_end` | Correlate parent/child threads and operations; begin/end is not proof the delegated goal was achieved. |

These persistence rules explain why missing begin/delta/error events are not reliable evidence that an action, stream update, or error never occurred. `SessionMeta.history_mode` defaults to legacy when absent according to protocol deserialization; state that this is a version-specific fallback.

## All 19 TurnItem types under item_completed

Read `payload.item.type` exactly as serialized below. The source does not rename this enum to snake_case. `payload.item.id`, `thread_id`, `turn_id`, and timing fields support correlation, but not every item has a separate `call_id`. Treat ID equivalence across representations as a hypothesis until supported by actual records.

| `payload.item.type` | Evidence to inspect |
| --- | --- |
| `UserMessage` | User input content and optional client ID. |
| `FunctionCallOutput` | Tool name/namespace and string or structured output body. |
| `HookPrompt` | Prompt fragments and hook attribution; distinguish hook input from direct user input. |
| `AgentMessage` | Assistant text parts, optional phase/delivery/questions. This is not `response_item/agent_message`, which is inter-agent communication. |
| `Plan` | Plan text; it is intended work, not proof of completed work. |
| `Reasoning` | Available summary/raw-content fields only; do not invent missing reasoning. |
| `CommandExecution` | `command`, `cwd`, `process_id`, `source`, `status`, `aggregated_output`, `exit_code`, duration and interaction input. Status may be `in_progress`, `completed`, `failed`, or `declined`. |
| `DynamicToolCall` | Tool, arguments, status, content items, success/error and duration. |
| `CollabAgentToolCall` | Tool operation, sender/receiver threads/agents, prompt, status and agent states. |
| `SubAgentActivity` | `kind`, agent thread/path, optional model/effort. Kinds: `started`, `interacted`, `interrupted`, `completed`. |
| `WebSearch` | Hosted search query/action and optional results. |
| `ImageView` | Referenced image path. |
| `Extension` | Read the flattened `kind` discriminator: `image_gen.generation`, `clock.sleep`, or `web.search` in this tag. Preserve unfamiliar kinds. |
| `ImageGeneration` | Hosted generation status, revised prompt, result and optional saved path. |
| `EnteredReviewMode` | Review request context and target. |
| `ExitedReviewMode` | Review output and findings where present, not proof every finding was fixed. |
| `FileChange` | Per-path changes, status, approval indication and stdout/stderr. Validate task success separately. |
| `McpToolCall` | Server, tool, arguments, status, result/error and optional connector/UI metadata; this struct uses camelCase field serialization. |
| `ContextCompaction` | Display-level compaction item; inspect outer checkpoint records for replacement history and resume state. |

Paginated persistence truncates command aggregated output above **64 KiB**, and applies a **64 KiB** MCP-result truncation limit. This is separate from the reader script's 2,000-character display truncation. Rereading the file can recover display-truncated text, but cannot recover output already discarded before persistence.

## Local observations and limits

The saved [local structural observations](local-observations.json) record per-file byte boundaries, complete-line counts, versions, history modes, nested item types and extension kinds, without conversation bodies. A bounded structural inventory of three local JSONL files identified `cli_version=0.167.2` and `history_mode=paginated`. Besides the previously sampled outer types, it observed `inter_agent_communication_metadata` and `response_item/agent_message`. Completed items included `CommandExecution`, `FileChange`, `McpToolCall`, `CollabAgentToolCall`, `SubAgentActivity`, `UserMessage`, `AgentMessage`, `Reasoning`, and `Extension` with `kind=web.search`.

This validates examples and casing, not exhaustiveness. No dangerous action, forced compaction, realtime session, or permission escalation was needed to manufacture rarer records. Their inclusion comes from the official source, not a claim that they were observed locally. The parser remains generic for unknown future types; the inventory is a reference, never a reason to discard valid JSON.

## Applying the reference

1. Read the session's version and history mode; report any mismatch with this reference.
2. Classify outer type, payload type, nested item type, and extension kind separately.
3. Look up persistence before interpreting a missing event. Keep physical line numbers, optional ordinals, and identity fields distinct.
4. Explain operation-specific outcomes and distinguish mirrored records from separate executions. Unknown status is not success.
5. Preserve unknown types/fields; label them unverified for the installed version, and consult the corresponding official source when needed.
