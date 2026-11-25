#Requires -Version 7
<#
.SYNOPSIS
    Runs the static check and the unit tests for the Build 42 Lua using the shared toolkit scripts.
.DESCRIPTION
    media\ (Build 41) is left out of the check because the Build 42 stubs would flag its API.
.PARAMETER Filter
    Only runs spec files whose name matches this wildcard.
#>
param(
    [string]$Filter = "*"
)

$toolkit = "$PSScriptRoot\..\project-zomboid-mod-toolkit"
& "$toolkit\check_lua.ps1" -SourceRoot $PSScriptRoot -Ignore "media/**"
$checkExit = $LASTEXITCODE
& "$toolkit\run_tests.ps1" -SourceRoot $PSScriptRoot -Filter $Filter
exit ($checkExit -or $LASTEXITCODE) ? 1 : 0
