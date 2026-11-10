# Context Folder: a tiny MCP server (stdio, JSON-RPC 2.0) that lets the
# Context Architect page save and reopen prompts inside ONE folder only.
#
# Layout:  <Root>\<Topic folder>\<prompt name>\session.json   (full session, used to reopen)
#                                              \prompt.md      (readable copy)
# It never deletes anything. It can create folders, write those two files,
# and move a prompt's folder to another topic folder.
param([string]$Root = (Join-Path $HOME "Context Engineering"))

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::InputEncoding  = $utf8
[Console]::OutputEncoding = $utf8
$stdin  = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
$stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8)
$stdout.AutoFlush = $true
if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root | Out-Null }
$Sep = [IO.Path]::DirectorySeparatorChar
$RootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')

function Send($obj) { $stdout.WriteLine(($obj | ConvertTo-Json -Depth 30 -Compress)) }
function Reply($id, $result) { Send @{ jsonrpc = "2.0"; id = $id; result = $result } }
function Fail($id, $code, $msg) { Send @{ jsonrpc = "2.0"; id = $id; error = @{ code = $code; message = $msg } } }
function TextResult([string]$text, [bool]$isError = $false) {
  @{ content = @(@{ type = "text"; text = $text }); isError = $isError }
}

# One folder or file-name segment: letters, digits, spaces and . _ - & ( ), no "..", no leading dot.
function Seg([string]$s, [string]$what) {
  $v = ([string]$s).Trim().TrimEnd('.')
  if ($v -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._&()-]{0,79}$' -or $v.Contains('..')) {
    throw "$what '$s' is not allowed. Use letters, digits, spaces, dots, dashes, underscores, & or ()."
  }
  return $v
}
# "Topic/prompt-name" -> full directory path, guaranteed to sit inside $Root.
function PromptDir([string]$path) {
  $parts = ([string]$path).Replace('\', '/').Split('/') | Where-Object { $_ -ne '' }
  if (@($parts).Count -ne 2) { throw "Path '$path' must look like 'Topic folder/prompt name'." }
  $dir = Join-Path (Join-Path $RootFull (Seg $parts[0] "Folder")) (Seg $parts[1] "Prompt name")
  $full = [IO.Path]::GetFullPath($dir)
  if (-not $full.StartsWith($RootFull + $Sep, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes the folder." }
  return $full
}

$tools = @(
  @{ name = "list_prompts"
     description = "List topic folders and saved prompt sessions, newest first. Returns {folder, folders:[name], prompts:[{path,folder,name,title,target,created,updated,followups,revisions}]}."
     inputSchema = @{ type = "object"; properties = @{} }
     annotations = @{ readOnlyHint = $true } },
  @{ name = "read_prompt"
     description = "Read one saved prompt session (its session.json) by path, e.g. 'Marketing/2026-11-10-cold-emails'."
     inputSchema = @{ type = "object"; properties = @{ path = @{ type = "string" } }; required = @("path") }
     annotations = @{ readOnlyHint = $true } },
  @{ name = "save_prompt"
     description = "Create or update a prompt session at <folder>/<name>/ (session.json + prompt.md), creating folders as needed. Pass previous_path to move an existing session to a new folder or name first."
     inputSchema = @{ type = "object"; properties = @{
         folder = @{ type = "string" }; name = @{ type = "string" }; record_json = @{ type = "string" }
         markdown = @{ type = "string" }; previous_path = @{ type = "string" } }
       required = @("folder", "name", "record_json", "markdown") }
     annotations = @{ readOnlyHint = $false; destructiveHint = $false } }
)

function ListPrompts {
  $folders = @(); $items = @()
  Get-ChildItem -LiteralPath $RootFull -Directory | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name | ForEach-Object {
    $folders += $_.Name
    $fname = $_.Name
    Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object {
      $sp = Join-Path $_.FullName "session.json"
      if (Test-Path -LiteralPath $sp) {
        try {
          $r = [IO.File]::ReadAllText($sp, $utf8) | ConvertFrom-Json
          $fu = 0; if ($r.followups) { $fu = @($r.followups).Count }
          $rv = 0; if ($r.versions) { $rv = @($r.versions).Count }
          $items += @{ path = "$fname/$($_.Name)"; folder = $fname; name = $_.Name; title = [string]$r.title
                       target = [string]$r.target; created = [string]$r.created; updated = [string]$r.updated
                       followups = $fu; revisions = $rv }
        } catch {
          $items += @{ path = "$fname/$($_.Name)"; folder = $fname; name = $_.Name; title = $_.Name
                       target = ""; created = ""; updated = ""; followups = 0; revisions = 0 }
        }
      }
    }
  }
  $sorted = @($items | Sort-Object -Property @{ Expression = { $_.updated } } -Descending)
  return (@{ folder = $RootFull; folders = $folders; prompts = $sorted } | ConvertTo-Json -Depth 6 -Compress)
}

function SavePrompt($a) {
  $folder = Seg ([string]$a.folder) "Folder"
  $name   = Seg ([string]$a.name) "Prompt name"
  $dir    = PromptDir "$folder/$name"
  $json   = [string]$a.record_json
  $rec    = $json | ConvertFrom-Json   # must be valid JSON
  $moved  = $false

  $prev = [string]$a.previous_path
  if ($prev) {
    $old = PromptDir $prev
    if ($old -ne $dir -and (Test-Path -LiteralPath $old)) {
      if (Test-Path -LiteralPath $dir) { throw "A prompt named '$name' already exists in '$folder'." }
      $parent = Split-Path $dir -Parent
      if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
      Move-Item -LiteralPath $old -Destination $dir
      $moved = $true
    }
  }

  $sp = Join-Path $dir "session.json"
  if ((-not $moved) -and (Test-Path -LiteralPath $sp) -and $rec.id) {
    try {
      $existing = [IO.File]::ReadAllText($sp, $utf8) | ConvertFrom-Json
      if ($existing.id -and $existing.id -ne $rec.id) { throw "EXISTS" }
    } catch { if ($_.Exception.Message -eq "EXISTS") { throw "A different prompt is already saved at '$folder/$name'. Pick another name." } }
  }
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [IO.File]::WriteAllText($sp, $json, $utf8)
  [IO.File]::WriteAllText((Join-Path $dir "prompt.md"), [string]$a.markdown, $utf8)
  return (@{ saved = $true; moved = $moved; path = "$folder/$name"; location = $dir } | ConvertTo-Json -Compress)
}

while ($true) {
  $line = $stdin.ReadLine()
  if ($null -eq $line) { break }
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  try { $msg = $line | ConvertFrom-Json } catch { Fail $null -32700 "Parse error"; continue }
  $id = $msg.id
  $hasId = $msg.PSObject.Properties.Name -contains "id"
  try {
    switch ($msg.method) {
      "initialize" {
        $pv = "2025-06-18"; if ($msg.params -and $msg.params.protocolVersion) { $pv = $msg.params.protocolVersion }
        Reply $id @{ protocolVersion = $pv; capabilities = @{ tools = @{} }
                     serverInfo = @{ name = "context-folder"; version = "2.0.0" } }
      }
      "ping"       { Reply $id @{} }
      "tools/list" { Reply $id @{ tools = $tools } }
      "tools/call" {
        $name = $msg.params.name; $a = $msg.params.arguments
        try {
          switch ($name) {
            "list_prompts" { Reply $id (TextResult (ListPrompts)) }
            "read_prompt" {
              $sp = Join-Path (PromptDir ([string]$a.path)) "session.json"
              if (-not (Test-Path -LiteralPath $sp)) { throw "No saved prompt at '$($a.path)'." }
              Reply $id (TextResult ([IO.File]::ReadAllText($sp, $utf8)))
            }
            "save_prompt" { Reply $id (TextResult (SavePrompt $a)) }
            default { Reply $id (TextResult "Unknown tool: $name" $true) }
          }
        } catch { Reply $id (TextResult $_.Exception.Message $true) }
      }
      default { if ($hasId -and $null -ne $id) { Fail $id -32601 "Method not found: $($msg.method)" } }
    }
  } catch { if ($hasId -and $null -ne $id) { Fail $id -32603 $_.Exception.Message } }
}
