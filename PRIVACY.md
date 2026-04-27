# Privacy

CommandNest sends prompts, conversation context, selected model IDs, and enabled tool-call payloads to OpenRouter when you ask it to use an AI model.

Your OpenRouter API key is stored in macOS Keychain. It is not committed to the repository and is not saved in `UserDefaults`.

Local Agent Mode can read local files, write files, move items, run shell commands, open files/apps/URLs, automate browser tabs, prepare or send email, run git/GitHub commands, and call MCP stdio servers using your current OS user account. CommandNest does not bypass OS privacy protections; protected folders and app automation may still require Full Disk Access, Accessibility, Automation, or Screen Recording permission depending on the action.

When MCP tools are used, tool names, arguments, and tool outputs may pass through the configured MCP server. Built-in MCP presets launch external npm packages with `npx`, so review server behavior before approving MCP actions.
