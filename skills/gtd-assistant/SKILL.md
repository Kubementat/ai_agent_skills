---
name: gtd-assistant
description: A GTD-style productivity assistant that combines open loop collection with intelligent brainstorming to generate actionable next steps, priorities, and refinement suggestions for your Obsidian vault.
---

# GTD Assistant

A unified productivity agent that doesn't just collect your open loops—it helps you make sense of them. By combining systematic data collection with embedded GTD analysis patterns, this assistant generates comprehensive reports with actionable recommendations tailored to personal productivity contexts.

## What Makes This Different?

Traditional GTD tools tell you what's unfinished. The GTD Assistant tells you:
- **What to tackle first** (context-aware priority suggestions)
- **What can be combined or eliminated** (pattern recognition across loose ends)
- **What needs clarification before action** (identifying vague items that need more thought)
- **How to convert ideas into actionable tasks** (turning dangling thoughts into concrete steps)

## Vault Configuration

| Setting          | Value                 |
| ------------------| -----------------------|
| **Vault path**   | `$HOME/main_vault`    |
| **Obsidian CLI** | Always use `obsidian` |

The vault layout follows the standard structure:
- `00-Tasks/` — all task files organized by domain
- Subfolders like `Work/`, `Privat/`, etc. for project-specific tasks

## When to Use

Activate when the user says:
- "Run a GTD sweep" / "Full GTD review"
- "Help me understand my backlog"
- "What's really unfinished in my vault?"
- "Open loops sweep"
- "Weekly review" / "Monthly review"
- "I feel overwhelmed — what do I have open?"
- "Deeper analysis" (after morning briefing)

## Relationship to Other Skills

### Captain's Log Integration (quest-system)

The GTD Assistant provides **strategic, comprehensive analysis** of all open loops in your vault. For daily tactical planning (what to focus on TODAY), use the `quest-system` skill (Captain's Log briefing — goal-first, with calendar and task collection):

```bash
# For deep dive: GTD assistant
gtd review / help me understand my backlog / open loops sweep

# For daily kickoff: quest-system Captain's Log
good morning / captain's log / what to focus on today?
```

When the `quest-system` briefing completes, it can offer:
- **"Deeper analysis?"** — call `gtd-assistant` for comprehensive view including dangling thoughts and stub notes
- **"Weekly review?"** — recommend full GTD sweep instead of daily briefing

## Workflow Overview

### Phase 1: Comprehensive Collection

Follow the three-pass workflow:

**Pass 1 — Open Tasks**
```bash
# Get total count
obsidian tasks todo total=true

# Get all open tasks grouped by file (JSON format for parsing)
obsidian tasks todo verbose=true format=json
```
Parse JSON output. Group tasks by domain:
- **Inbox / Urgent**: files in `00-Tasks/`
- **Work**: files in `Work/` or with `#work` tag
- **Music / Creative**: files in `03-denkfabrik/` or tagged `#music`
- **House / Personal**: `06 - Tasks - Haus`, `Privat/`, etc.
- **Projects**: everything else

Show top items per group (max 5–7 per group). Skip recurring tasks (`🔁`) in the main list — note them separately.

**Pass 2 — Dangling Thoughts **(keyword search)
```bash
obsidian search query="TODO" format=json limit=30
obsidian search query="idea" format=json limit=30
obsidian search query="later" format=json limit=20
obsidian search query="?" format=json limit=20
```
**Filter out**:
- Files already in `00-Tasks/` (covered in Pass 1)
- Files in `copilot-conversations/`, `ZZ-Archiv/`, `Evernote Import/`
- Lyrics files (`03-denkfabrik/Lyrics/`)

Present as a deduplicated list of notes with dangling content. For each, read a snippet to show *what* is dangling.

**Pass 3 — Stub Notes **(incomplete / abandoned)
```bash
# Run the stub collection script
bash skills/obsidian-open-loops-collector/scripts/collect_stubs.sh $HOME/main_vault
```
This returns lines like: `3\tSome Note.md` (line count, filename).

Group stubs by folder/domain. Highlight any stubs that look like project or idea notes (not just reference stubs). Read the content of interesting-looking ones.

### Phase 2: GTD Analysis Workflow

Apply the following analysis patterns directly to the collected data:

#### Priority Assessment
Given [X] open tasks, [Y] dangling thoughts, and [Z] stub notes across domains like work, music production, house maintenance, and personal projects:
- Identify 3–5 concrete next actions that would give the highest satisfaction return
- Consider context: time available, energy level, upcoming commitments
- Factor in urgency (deadlines visible in task descriptions)
- Balance quick wins with meaningful challenges based on user's stated goals

### Phase 3: Unified Report Generation

Present a structured output that combines both perspectives:

```
## 📊 GTD Assistant Report — [Date]

---

### 🎯 Quick Summary
- **[N] Open Tasks** across [M] domains
- **[P] Dangling Thoughts** in [Q] notes  
- **[R] Stub Notes** requiring attention

---

### 🔥 Suggested First Actions (Top 3-5)

Based on context, urgency, and effort assessment:

1. **Action Item** — *Why:* [brief reasoning]
   - Related to: [domain/file]
   - Estimated effort: [Quick/Medium/Long]
   - Context needed: [work/home/focus time/etc.]

2. ...

---

### 📋 Full Breakdown

#### Open Tasks by Domain
[Grouped list with counts and highlights]

#### Dangling Thoughts
[Notes containing TODOs, ideas, later items, questions]

#### Stub Notes
[Incomplete notes with line counts and recommendations]

---

### 💡 GTD Analysis Insights

**Consolidation Opportunities:**
- Identify tasks that could be combined into single actions
- Flag items suitable for delegation or elimination
- Suggest breaking down complex items into smaller sub-tasks
- Mark items appropriate for intentional deferral

**Clarification Needed:**
- Highlight vague or incomplete open loops
- Suggest specific questions to make each item actionable

**Pattern Recognition:**
- Identify recurring themes across domains
- Note areas with unusually high accumulation
- Surface potential bottlenecks (e.g., too many pending reviews, unprocessed inbox items)

---

### 🛠️ Available Actions

1. **"Dive in"** — Read any specific note in full
2. **"Close it"** — Mark tasks as done, move notes to archive
3. **"Capture it"** — Turn a dangling thought into a proper task
4. **"Save report"** — Write the report as a vault note
5. **"Focus session"** — Generate a focused 25-min task list from top priorities
```

## Interaction Patterns

After presenting the unified report, offer these follow-up actions:

### Focus Session Generator

When the user asks for a focus session after the GTD report, produce:
- **One concrete next step** to start immediately
- **Estimated time:** 25 minutes (one Pomodoro)
- **Context needs:** tools, environment, prerequisite info

Format:
> "Your next 25 minutes: [specific action] in [file/tool]. Start by [first micro-step]."

### Task Creation from Ideas
```bash
obsidian create name="Task: [Description]" content="[task details]"
```

### Report Saving (Optional)

Ask the user whether he wants to save the report.

```bash
obsidian create name="GTD Report — $(date +%Y-%m-%d)" content="[full report markdown]"
```

## Example Usage

**Initial Request:**
> "Run a full GTD sweep and give me actionable next steps."

**Follow-up Options the User Can Ask:**
- "What's the quickest thing I can complete right now?"
- "Can you break down that big project task into smaller steps?"
- "Which of these are actually urgent vs. just important?"
- "Generate a focus session plan for my next 25 minutes"
- "Save this report to my vault so I can reference it later"