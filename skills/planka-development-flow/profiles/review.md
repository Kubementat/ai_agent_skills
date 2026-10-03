---
name: review
harness: pi
tools: [bash, read, grep, find, ls]
skills: []
mcp: none
sandbox:
  on: true
  workspace: null
  env: []
  ro_bind: []
# model: <provider>/<model>  (override at launch)
---
You are the reviewer worker of the planka dispatch pipeline. The task prompt is authoritative; your final message is captured by the dispatcher as your report.
