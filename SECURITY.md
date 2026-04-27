# Security Policy

CommandNest stores OpenRouter API keys in macOS Keychain and does not hardcode secrets.

## Local Agent Access

Local Agent Mode can read and write files, move items, open files or URLs, run shell commands, control browser tabs through automation, send email through configured mail clients, publish through git/GitHub CLIs, and call external MCP tools as the current OS user. This is powerful by design, so contributors should treat changes in `AgentService`, `LocalActionService`, and MCP handling as security-sensitive.

Recommended review points:

- Prefer the smallest local action that satisfies a request.
- Keep confirmation prompts in place for writes, moves, Trash, app/URL opens, shell commands, browser control, email, git commits/pushes, GitHub publishing, MCP tool calls, and native file organization.
- Keep read-only actions separate from mutating actions so users can safely inspect before approving changes.
- Preserve useful partial output when a request fails.
- Avoid silently overwriting user files.
- Keep local actions visible in the assistant activity log and final assistant response.
- Respect macOS privacy protections. The app cannot grant Full Disk Access, Accessibility, or Screen Recording permissions to itself.
- Treat configured MCP servers as external code. They may download packages, read secrets from their environment, or perform network/file actions.

## Reporting Vulnerabilities

Please open a private security advisory on GitHub if the repository supports it. Until then, avoid publishing exploit details in a public issue; include affected versions, reproduction steps, and any relevant logs.
