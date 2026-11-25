#Requires -Version 7
<#
.SYNOPSIS
    Deploys this mod to the local Workshop cache using the shared deploy script.
#>
param(
    [switch]$Undeploy
)

& "$PSScriptRoot\..\project-zomboid-mod-toolkit\deploy_local.ps1" -ModId pass-out -SourceRoot $PSScriptRoot -Undeploy:$Undeploy
