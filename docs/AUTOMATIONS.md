---
title: Automations
---

# Automations

Automations do routine work for you: *when* something happens in Colony, *then* it does the steps you picked. No code, no AI and no
setup outside Colony. They're built from blocks you pick from lists, and every automation also reads as one plain sentence.

```
WHEN     A task becomes overdue
ONLY IF  It's in Sales              (optional)
THEN     Set priority to Urgent
         Notify me: "[Task name] is overdue"
```

> When a task becomes overdue, if it's in Sales, set its priority to Urgent and notify me: "[Task name] is overdue".

## Making one

Open **Automations** in the sidebar and press **+** (or ⌥⌘A, or ⌘K → *New automation*):

1. **Pick a recipe or start from scratch.** Recipes are complete automations, filled in from your workspace (channels, agents).
2. **When** – pick what starts it.
3. **Only if** – optional filters. All of them must match.
4. **Then** – add steps. They run top to bottom. Use a block's ⋯ menu to move, duplicate or remove it, or the small + between blocks to insert one.
5. **Test** – shows what it *would* do with a real example from your workspace, without changing anything.
6. Switch it **On**.

Text fields take *blanks* like **[Task name]** or **[Customer]**: click a chip under the field and Colony fills it in when the
automation runs.

## Triggers

| When | Can filter on |
| --- | --- |
| A task is created | project, priority, name contains, flagged |
| A task changes status (to To do, In progress, In review or Done) | project, priority, name contains, flagged |
| A task becomes overdue | project, priority, name contains, flagged |
| A customer changes stage (to Lead, Proposal, Won, …) | company contains, deal worth at least |
| A customer is added | company contains, deal worth at least |
| Someone posts a message (in any channel or one) | message contains |
| On a schedule: every hour, every day, on weekdays or once a week | – |

## Steps

| Then | Works with |
| --- | --- |
| Create a task (optional project, priority and due date) | any trigger |
| Change its priority / Change its status / Flag it / Move it to a project / Set its due date | task triggers |
| Move the customer (to a stage) | customer triggers |
| Post in a channel | any trigger |
| Add to Updates | any trigger |
| Notify me | any trigger |
| Ask an agent (it runs with your prompt) | any trigger |
| Clear old completed tasks | any trigger |

## How they run

- Automations run on your devices while Colony is open (on the Mac, also from the menu bar). A change you make on any device starts
  the automations on that device, so each change triggers each automation once.
- Steps made by an automation can start other automations, up to 3 in a row, so two automations can't loop forever.
- Scheduled automations run once per slot, even with several devices. If Colony was closed at the time, it catches up when it
  opens within 2 hours; after that the run is skipped rather than done late.
- Each automation keeps its last 25 runs under **Activity**: what started it, which filter stopped it, and what each step did.
- If a step can't run (for example, its channel was deleted), Colony shows a warning on the block and in Activity.

## Privacy

Automations and their runs are stored in your iCloud with the rest of your workspace. They don't contact any server. **Notify me**
uses local notifications and **Ask an agent** uses the on-device model (see [Agents](AGENTS/)).
