# Antigravity CLI Skills and Context Optimization Guide

When starting a session or asking a small question in the Antigravity CLI (`agy`), the initial prompt context can occupy around **15k–17k tokens**. This guide explains how this context is composed, how skills are loaded, and how you can configure and restrict them to optimize token footprint if desired.

---

## 1. Why is the Context 17k Tokens?

The 17k token count is completely normal and expected for an advanced, agentic workspace assistant. The token footprint is composed of:

1. **System Prompt & Instructions**: Guidelines on how the agent operates, formatting rules, and guidelines. (~2k–3k tokens)
2. **Tool Declarations**: Antigravity equips the agent with 23 highly detailed, schema-defined tools (e.g., file reading/writing, git operations, subagents, and web search). These JSON schemas describe the parameters, arrays, and usage rules, which are essential for model function call planning. (~6k–8k tokens)
3. **Workspace File Tree & Git Status**: A snapshot of the files, directories, and git status of the current workspace so the agent knows what files are available. (~1k–2k tokens)
4. **Active File Context**: Open files in the editor, cursor selection, or recently viewed files. (~1k–4k tokens depending on the file size)
5. **Skill Summaries (Progressive Disclosure)**: Names and brief descriptions of all available skills. (~500 tokens)

> [!NOTE]
> Since modern LLMs (such as Gemini 3.5 Flash or Pro) have context windows of 1M to 2M tokens, a 17k baseline occupies less than 2% of the window and has negligible latency or cost impact.

---

## 2. Skill Loading: Progressive Disclosure

Antigravity uses a mechanism called **Progressive Disclosure** to prevent skills from inflating the context window:

* **Descriptions Only by Default**: Only the names and the YAML frontmatter descriptions of the skills are loaded into the initial context.
* **On-Demand Activation**: The full content of a skill (the instructions and workflows in `SKILL.md`) is **only** loaded if the agent (or the user via explicit activation) decides that the skill is relevant to the current task.

Therefore, having many skills registered does **not** significantly increase token consumption unless they are explicitly activated.

---

## 3. How to Configure and Exclude Skills

If you still want to prune or restrict the skills loaded in your workspace, you can explicitly configure them using a `skills.json` file.

### Configuration Locations
You can place `skills.json` in two customization roots:
1. **Workspace-Specific**: `.agents/skills.json` at the root of your project repository.
2. **Global (Machine-Local)**: `~/.gemini/config/skills.json` (applies to all projects).

### Schema of `skills.json`
You can declare which directories to scan for skills, or inherit from other configurations and apply filters (`include_only` or `exclude` regex patterns).

Here is a template to configure a minimal skills setup:

```json
{
  "entries": [
    {
      "path": ".agents/skills",
      "exclude": [
        "parenthesis-matching",
        "experimental-.*"
      ]
    }
  ]
}
```

### Exclude Built-in Skills
To override or exclude built-in system skills (like `antigravity-guide` or `permissioned-github`), you can define your global `~/.gemini/config/skills.json` and selectively inherit them:

```json
{
  "inherits": [
    {
      "path": "/root/.gemini/antigravity-cli/builtin/skills.json",
      "exclude": [
        "permissioned-github"
      ]
    }
  ]
}
```

---

## 4. How to Inspect Your Token Usage

In an active CLI session, you can run the following interactive slash commands to audit token consumption:

* **/context**: Prints a visual breakdown of your current token usage by category (System Prompt, Tools, History, Files, Skills, etc.).
* **/config** or **/settings**: Displays the active settings and configurations loaded from your `settings.json`.
