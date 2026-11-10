# Folder saving setup

Context Architect can save every prompt to a folder on your computer, organized like this:

```
<your folder>/
  Marketing/
    2026-11-10-cold-outreach/
      prompt.md      readable copy: brief, interview, prompt, follow-ups, earlier versions
      session.json   full session, used to reopen it in the Library
  Coding/
    ...
```

This uses `context-folder-server.ps1`, a small [MCP](https://modelcontextprotocol.io) server that the Claude desktop app runs locally.

## What the helper can and can't do

| It can | It can't |
|---|---|
| List topic folders and saved prompts | Delete anything |
| Read a prompt's `session.json` | Read or write outside your chosen folder |
| Write `session.json` and `prompt.md`, creating folders as needed | Run other programs or connect to the internet |
| Move a prompt into another topic folder | Touch files other than those two names |

Names that try to leave the folder, such as `..`, are rejected.

## Windows

1. Download or clone this repository, for example to `C:\Tools\context-architect`.
2. Pick a folder for your prompts, for example `D:\Prompts`.
3. Open the Claude desktop app's config file.
   - **Settings → Developer → Edit Config**. If you don't see *Developer*, enable it under **Help → Troubleshooting → Enable Developer Mode**.
   - Or open `%APPDATA%\Claude\claude_desktop_config.json` in Notepad. The exact location can vary by install.
4. Add this at the top level of the JSON, next to any existing keys, with a comma between entries. Use your own two paths and keep the double backslashes:

   ```json
   "mcpServers": {
     "context-folder": {
       "command": "powershell.exe",
       "args": [
         "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
         "-File", "C:\\Tools\\context-architect\\server\\context-folder-server.ps1",
         "-Root", "D:\\Prompts"
       ]
     }
   }
   ```

   `-ExecutionPolicy Bypass` applies to this one process only. It lets Windows run the unsigned script without changing your system settings.

5. **Fully quit** Claude: right-click the tray icon and choose **Quit**, or end it in Task Manager. Then reopen it. Closing the window isn't enough.
6. Open Context Architect in the desktop app, build a prompt, and click **Save to folder**. Choose **Allow** when the app asks about `context-folder`.

## macOS / Linux (untested)

Install PowerShell 7 (`brew install powershell`), then use `"command": "pwsh"` with the same `args`, minus the `-ExecutionPolicy` pair, and with Unix paths. On macOS the config file is `~/Library/Application Support/Claude/claude_desktop_config.json`.

## Troubleshooting

| You see | Fix |
|---|---|
| *Folder not connected* | The app isn't running the helper. Check the config, then fully quit and reopen Claude. |
| *The app didn't approve the save (cancelled)* | Click **Save to folder** directly and choose **Allow** when asked. Saves need a click to approve. |
| The Library is empty in a browser | Expected. Folder saving only works in the Claude desktop app. |
| The Settings → Developer list shows an error | Usually a missing comma or brace in the JSON. |
