---
title: Agents and AGENT.md
---

# Agents

Agents are assistants that work in your Colony workspace. By default each one runs on your own
device with Apple Intelligence (the Foundation Models framework), and nothing you or the agents
write is sent to a server. Optionally, you can run agents on your own OpenAI, Claude, Gemini or
OpenAI-compatible account, and let them ask Jev for judgment calls (see *Models and Jev* below). Agents and their conversations are stored like the
rest of Colony, in your private iCloud database, so they appear on all your devices.

Every agent is described by an **AGENT.md** file. You recruit an agent by giving Colony one:

- **Import:** Agents › Recruit (or the **+** next to Agents in the sidebar) › Import, then drop
  the file on the dialog or choose it.
- **Templates:** start from one of the built-in agents and adjust it.
- **Write:** type the file straight into the dialog.

Colony shows you the agent the file describes (name, face, tools, schedule) and any problems
before it joins. You can change an agent later with **Edit AGENT.md…**, and save or share it with
**Export AGENT.md…**.

## The file

An AGENT.md is Markdown. Settings go in a front-matter block between two `---` lines. Everything
after the block is the agent's instructions, in plain language.

```markdown
---
name: Neo
description: Plans your day from open tasks and due dates.
color: blue
tools: list_tasks, list_projects, update_task, post_update, ask_user
schedule: weekdays 09:00
prompts:
  - Plan my day
  - What's overdue?
---

You are Neo, a calm, practical day planner.

When asked to plan the day, or on your scheduled run:
1. Call list_tasks with filter "overdue", then "today", then "upcoming".
2. Pick at most five tasks for today: overdue and urgent first.
3. Post one Update titled "Today's plan" listing them in order.
4. Reply with the same plan in a few lines.

Only change a task when the user asks you to.
```

The front matter is optional. A file that starts with a `# Heading` uses the heading as the name
and gets read-only tools.

### Settings

| Key | Required | Meaning |
|---|---|---|
| `name` | yes (or a `# Heading`) | Up to 40 characters. |
| `description` | no | One line, shown under the name. |
| `color` | no | `blue`, `indigo`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `teal` or `gray`. Picked from the name if missing. |
| `tools` | no | What the agent may do (see below), as a comma-separated list, `[a, b]` or `- a` lines. Without it, the agent gets the read-only tools. `tools:` with nothing after it means chat only. |
| `schedule` | no | When the agent runs by itself: `hourly`, `daily 09:00`, `weekdays 08:30`, or a weekday such as `mondays 10:00` / `fri 16:00`. `manual` or no schedule means it only runs when asked. |
| `prompts` | no | Up to four suggestions shown in an empty chat, as `- prompt` lines. |

Unknown settings and tools are ignored, and Colony tells you which ones when you recruit.

### Tools

| Tool | What it does | Changes data |
|---|---|---|
| `list_tasks` | Lists tasks: `open`, `today`, `overdue`, `upcoming`, `flagged`, `urgent`, `no_project`, `done` (this week) or `all`, optionally in one project. | |
| `create_task` | Creates a task with title, notes, project, list, due date and priority. | ✓ |
| `update_task` | Renames a task, or changes its status, priority, due date, project or flag. | ✓ |
| `list_projects` | Lists projects, their lists and open-task counts. | |
| `list_customers` | Lists CRM customers, optionally one deal stage. | |
| `move_customer` | Moves a customer to another deal stage. | ✓ |
| `read_channel` | Lists channels, or reads a channel's recent messages. | |
| `post_message` | Posts in a channel, signed with the agent's name. | ✓ |
| `list_updates` | Reads the Updates feed. | |
| `post_update` | Adds a note to Updates. | ✓ |
| `ask_user` | Asks you a question and waits for your reply. | |

Every change an agent makes goes through the same code as your own edits. It appears in the
agent's conversation as a line you can read (for example *Created task "Send deck" in Sales, due
Tomorrow, 10:00*), and in Updates where the action normally logs there. Agents can't delete
anything.

Due dates can be written as `today`, `tomorrow`, a weekday (`friday`, `next monday`),
`in 3 days`, or `2026-10-02`, optionally followed by a time (`14:00`, `2pm`).

## Running

- **Chat.** Open an agent and send a message, or pick a suggestion. The reply streams in.
- **Run now.** Runs the agent's job as if its scheduled time had come.
- **Schedule.** While Colony is open (on the Mac, that includes menu-bar mode), agents with a
  schedule run at their time. Each time slot runs once, even with several devices. If the device
  was asleep for more than two hours past the slot, that run is skipped rather than done late.
  **Pause Schedule** stops an agent's schedule without removing it.
- **Notifications.** If notifications are allowed (Settings › Notifications), you get one when an
  agent asks you something or finishes a scheduled run while you're elsewhere.
- **Calendar.** With **Show automation schedules** on (Settings › Calendar), scheduled agents
  appear as repeating events in the Colony calendar. Hourly agents are left out.

## Models and Jev

**Settings › AI** chooses what runs agents:

| Option | Account | What leaves the device |
| --- | --- | --- |
| Apple Intelligence (default) | None | Nothing |
| OpenAI | Your API key | The agent's chat and what its tools read, sent to OpenAI |
| Anthropic Claude | Your API key | Same, sent to Anthropic |
| Google Gemini | Your Google AI Studio key | Same, sent to Google |
| Other (OpenAI-compatible) | Server address, optional key | Same, sent to that server (e.g. OpenRouter, or a local Ollama / LM Studio) |

Paste a key, press **Check connection** to load your account's models, and pick one. Keys are
kept in your iCloud Keychain. To use a different model for one agent, open it and choose
**⋯ › Runs On**. Cloud models use the same tools, so action rows, `ask_user` and the safety rules
(agents can't delete) are identical.

**Jev** is a decision model by [TypeSafe](https://docs.typesafe.ai/introduction). It doesn't write
text; it returns calibrated odds. With a Jev key saved and **Let agents ask Jev** on, every agent
that has tools also gets `ask_jev`:

- a yes/no question ("Is this task urgent?") returns how likely yes, e.g. *96% likely yes*;
- with options ("Which project fits? Launch, Sales, Ops") it returns the pick and each option's odds.

Each question shows in the chat as an action row (*Asked Jev: Is this task urgent? — 96% likely
yes*). Jev works with any model above, including Apple Intelligence. You don't list `ask_jev` in
AGENT.md; it's added automatically when Jev is on.

## When Apple Intelligence isn't available

Agents need a device that supports Apple Intelligence, with it turned on and its model
downloaded. Otherwise Colony says why. You can still recruit, edit, export and read agents on
that device. They run on your devices that support it, or you can pick a cloud model in
Settings › AI.

The on-device model has a limited context window. If a conversation gets too long, Colony starts
a fresh session and says so. **Clear Conversation** in the agent's menu does the same on purpose.
