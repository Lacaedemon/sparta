#Requires -Version 5.1
<#
.SYNOPSIS
List orphaned Godot processes left behind by test/demo runs; kill them with -Force.

.DESCRIPTION
Headless Godot runs survive their calling shell on Windows (no process-tree
kill), so a hung run whose shell died lives forever as an orphan and starves
every later run on the machine. This sweep finds Godot processes whose command
line matches a NON-INTERACTIVE repo-run signature (headless import, GUT suite,
demo/benchmark recording) and classifies each as:

  Orphaned - the parent process is gone, so nothing is consuming the output
             (or the parent PID was recycled by a process younger than the
             child - a real parent always started first). Safe to kill by
             construction: killing Godot cannot lose git state.
  Overdue  - older than -MaxAgeHours (default 2h). No legitimate repo run
             takes that long.
  Child    - a matched process whose parent is itself being killed by this
             sweep. The Windows console build ships as a launcher exe that
             spawns the real Godot as a child; killing only the launcher
             would leave the real process running, orphaned by the sweep
             itself.
  Live     - everything else. Never touched.

Interactive Godot editor sessions never match the run signature, so they are
never listed or killed (killing one could lose unsaved scene work).

Dry-run by default: prints what it WOULD kill. Pass -Force to actually kill.

.PARAMETER Force
Actually kill the Orphaned/Overdue processes (default: dry-run).

.PARAMETER MaxAgeHours
Age ceiling in hours for the Overdue verdict (default 2).

.PARAMETER OnlyPids
Comma-separated PIDs to restrict the sweep to (still classified; everything
else is ignored). For a surgical kill, or for testing the sweep on a process
you spawned yourself without touching anyone else's runs.

.EXAMPLE
powershell -NoProfile -File tools/kill-orphan-godot.ps1
Dry run: list the candidates and what would be killed.

.EXAMPLE
powershell -NoProfile -File tools/kill-orphan-godot.ps1 -Force
Sweep: kill the Orphaned/Overdue runs.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [double]$MaxAgeHours = 2.0,
    [string]$OnlyPids = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Non-interactive run signature: every repo script / CI invocation matches at
# least one of these; an interactive editor session matches none. Keep in sync
# with tools/kill-orphan-godot.sh.
$runSignature = '--headless|--write-movie|--import|--rendering-driver|gut_cmdln|DemoInputRecorder|DemoRunner|BenchmarkRunner'

$onlyPidList = @()
if ($OnlyPids -ne '') {
    $onlyPidList = @($OnlyPids -split ',' | ForEach-Object { [int]$_.Trim() })
}

$now = Get-Date
$candidates = @(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'")

$rows = @()
foreach ($p in $candidates) {
    if ($onlyPidList.Count -gt 0 -and $onlyPidList -notcontains [int]$p.ProcessId) { continue }
    $cmd = $p.CommandLine
    # No command line (access denied) or no run signature: interactive/unknown -
    # never touch it.
    if ($null -eq $cmd -or $cmd -notmatch $runSignature) { continue }

    $started = $p.CreationDate
    $ageHours = 0.0
    if ($null -ne $started) { $ageHours = ($now - $started).TotalHours }

    # Parent-dead check with a PID-reuse guard: a recycled parent PID belongs to
    # a process YOUNGER than the child, and a real parent always started first.
    $parentAlive = $false
    try {
        $parent = Get-Process -Id $p.ParentProcessId -ErrorAction Stop
        $parentAlive = $true
        try {
            if ($null -ne $started -and $parent.StartTime -gt $started) { $parentAlive = $false }
        } catch {
            # StartTime can be access-denied (elevated parent); stay conservative
            # and keep treating the parent as alive.
        }
    } catch {
        # No such process: the parent is gone.
    }

    $verdict = 'Live'
    if (-not $parentAlive) { $verdict = 'Orphaned' }
    elseif ($ageHours -ge $MaxAgeHours) { $verdict = 'Overdue' }

    $shortCmd = $cmd
    if ($shortCmd.Length -gt 120) { $shortCmd = $shortCmd.Substring(0, 120) + '...' }
    $rows += [pscustomobject]@{
        Pid         = [int]$p.ProcessId
        AgeHours    = [math]::Round($ageHours, 2)
        ParentPid   = [int]$p.ParentProcessId
        ParentAlive = $parentAlive
        Verdict     = $verdict
        Command     = $shortCmd
    }
}

if ($rows.Count -eq 0) {
    Write-Output 'No non-interactive Godot run processes found.'
    exit 0
}

# Doom-propagation: a matched process whose parent is being killed must go too,
# or the sweep itself creates a fresh orphan (the console-launcher case above).
# Iterate to a fixpoint so launcher chains of any depth are covered.
$changed = $true
while ($changed) {
    $changed = $false
    $doomedPids = @($rows | Where-Object { $_.Verdict -ne 'Live' } | ForEach-Object { $_.Pid })
    foreach ($r in $rows) {
        if ($r.Verdict -eq 'Live' -and $doomedPids -contains $r.ParentPid) {
            $r.Verdict = 'Child'
            $changed = $true
        }
    }
}

$rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$doomed = @($rows | Where-Object { $_.Verdict -ne 'Live' })
if ($doomed.Count -eq 0) {
    Write-Output ("Nothing to kill: every run has a live parent and is under the {0}h ceiling." -f $MaxAgeHours)
    exit 0
}

if (-not $Force) {
    Write-Output ("DRY RUN: would kill {0} process(es) (Verdict Orphaned/Overdue above). Re-run with -Force to kill." -f $doomed.Count)
    exit 0
}

foreach ($d in $doomed) {
    try {
        Stop-Process -Id $d.Pid -Force -ErrorAction Stop
        Write-Output ("Killed PID {0} ({1}, age {2}h)." -f $d.Pid, $d.Verdict, $d.AgeHours)
    } catch {
        Write-Output ("Could not kill PID {0}: {1}" -f $d.Pid, $_.Exception.Message)
    }
}
