param(
    [switch]$NoAgentRules
)

$ErrorActionPreference = "Stop"

$repoDir = $PSScriptRoot
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$hooksDir = Join-Path $codexDir "hooks"
$hookScript = Join-Path $hooksDir "cc-codex-hook.js"
$hooksJson = Join-Path $codexDir "hooks.json"
$configToml = Join-Path $codexDir "config.toml"
$agentsFile = Join-Path $codexDir "AGENTS.md"
$blockStart = "<!-- cc-hooks-rules:start -->"
$blockEnd = "<!-- cc-hooks-rules:end -->"

function Convert-ToUnixPath($path) {
    return ($path -replace "\\", "/")
}

function Ensure-HooksFeature($path) {
    if (!(Test-Path $path)) {
        Set-Content -Encoding UTF8 -Path $path -Value "[features]`nhooks = true`n"
        return
    }

    $text = Get-Content -Encoding UTF8 -Raw -Path $path
    if ($text -match "(?ms)^\[features\]\s*(.*?)(?=^\[|\z)") {
        $section = $Matches[0]
        if ($section -match "(?m)^\s*hooks\s*=") {
            $updatedSection = $section -replace "(?m)^\s*hooks\s*=.*$", "hooks = true"
            $text = $text.Replace($section, $updatedSection)
        } else {
            $text = $text.Replace($section, ($section.TrimEnd() + "`nhooks = true`n"))
        }
    } else {
        $text = $text.TrimEnd() + "`n`n[features]`nhooks = true`n"
    }
    Set-Content -Encoding UTF8 -Path $path -Value $text
}

function Merge-AgentRules($target, $source) {
    $rules = Get-Content -Encoding UTF8 -Raw -Path $source
    $block = "$blockStart`n$rules`n$blockEnd"
    $existing = if (Test-Path $target) { Get-Content -Encoding UTF8 -Raw -Path $target } else { "" }
    if ($existing -match "(?s)<!-- cc-hooks-rules:start -->.*?<!-- cc-hooks-rules:end -->") {
        $next = [regex]::Replace($existing, "(?s)<!-- cc-hooks-rules:start -->.*?<!-- cc-hooks-rules:end -->", $block)
    } elseif ([string]::IsNullOrWhiteSpace($existing)) {
        $next = $block + "`n"
    } else {
        $next = $existing.TrimEnd() + "`n`n" + $block + "`n"
    }
    Set-Content -Encoding UTF8 -Path $target -Value $next
}

New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
Copy-Item -Force (Join-Path $repoDir "hooks\codex-hook.js") $hookScript

$command = "& `"node`" `"$(Convert-ToUnixPath $hookScript)`""
$settings = if (Test-Path $hooksJson) {
    $rawHooksJson = Get-Content -Encoding UTF8 -Raw -Path $hooksJson
    if ([string]::IsNullOrWhiteSpace($rawHooksJson)) {
        [pscustomobject]@{ hooks = [pscustomobject]@{} }
    } else {
        $rawHooksJson | ConvertFrom-Json
    }
} else {
    [pscustomobject]@{ hooks = [pscustomobject]@{} }
}
if (-not $settings.hooks) {
    $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}

$events = @(
    @{ name = "PreToolUse"; status = "Checking repository safety policy" },
    @{ name = "PermissionRequest"; status = "Checking approval policy" },
    @{ name = "PostToolUse"; status = "Checking git commit metadata" }
)

foreach ($event in $events) {
    $name = $event.name
    if (-not $settings.hooks.PSObject.Properties[$name]) {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name $name -Value @()
    }
    $entries = @($settings.hooks.$name)
    $entries = @($entries | Where-Object {
        $json = $_ | ConvertTo-Json -Depth 10 -Compress
        $json -notmatch "cc-codex-hook\.js"
    })
    $entries += [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type = "command"
                command = $command
                commandWindows = $command
                timeout = 30
                statusMessage = $event.status
            }
        )
    }
    $settings.hooks.$name = $entries
}

$settings | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $hooksJson
Ensure-HooksFeature $configToml
if (-not $NoAgentRules) {
    Merge-AgentRules $agentsFile (Join-Path $repoDir "AGENTS.md")
}

Write-Host "Codex hooks installed to $hooksJson"
Write-Host "Hook script: $hookScript"
Write-Host "Next step: restart Codex or run /hooks to review and trust the hook."
