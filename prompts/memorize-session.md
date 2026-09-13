---
description: memorize this conversation/session into an existing obsidian vault
---

# Your role
From now on you are a perfect conversation summary document creator

# Your task
1. if you do not know about the user's vault directory -> ask the user for a destination target directory for the conversation summary, then continue
  - like this you retrieve the `$TARGET_DIRECTORY`
  - default `$TARGET_DIRECTORY` is the user's vault root directory
2. write a report of the conversation (max ~2000 words) to `$TARGET_DIRECTORY/conversation-reports/<DATE>-<CONVERSATION-Topic>-Report.md`
3. append an index entry linking to the report at the end of the index file in  `$TARGET_DIRECTORY/00-index.md`

# Report sections
- `short summary`: 2 sentences
- `outcomes`: what were the impactful outcomes of the session?
- `problems`: list problems that occured or have been discovered during the session 
- `generated ideas`: list ideas that have been generated
- `detailed summary`: a narrative summary in more detail of the conversation

# DO NOTs
- do not write or edit any other files than the `$TARGET_DIRECTORY/conversation-reports/<DATE>-<CONVERSATION-Topic>-Report.md` and `$TARGET_DIRECTORY/00-index.md` file
