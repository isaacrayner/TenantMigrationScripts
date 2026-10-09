#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Repository tests: structure, parameter binding, dashboard parity and orchestrator behaviour.
    Run:  Invoke-Pester ./tests        (or: tests/run-tests.sh, which runs these too when pwsh exists)
#>

BeforeDiscovery {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:PhaseScripts = Get-ChildItem -Path $Root -Recurse -File |
        Where-Object { $_.FullName -match '[\\/]0\d-[A-Za-z]+[\\/]' -and $_.Extension -in '.ps1', '.sh' } |
        ForEach-Object { @{ Rel = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/'); Path = $_.FullName; Ext = $_.Extension } }
    $script:AllPs1 = Get-ChildItem -Path $Root -Recurse -File -Filter *.ps1 |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|migration-data)[\\/]' } |
        ForEach-Object { @{ Rel = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/'); Path = $_.FullName } }
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
}

Describe 'PowerShell scripts' {
    It '<Rel> parses without errors' -ForEach $AllPs1 {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It '<Rel> has param() as its first statement (so parameters bind)' -ForEach $AllPs1 {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $hasParamKeyword = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.ParamBlockAst] }, $false)
        if ($hasParamKeyword) { $ast.ParamBlock | Should -Not -BeNullOrEmpty }
    }

    It '<Rel> has no parameter default that depends on a variable (defaults run before config loads)' -ForEach ($PhaseScripts | Where-Object Ext -eq '.ps1') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $bad = @()
        foreach ($p in $ast.ParamBlock.Parameters) {
            if ($p.DefaultValue) {
                $vars = $p.DefaultValue.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $n.VariablePath.UserPath -notin 'true', 'false', 'null' }, $true)
                if ($vars) { $bad += $p.Name.VariablePath.UserPath }
            }
        }
        $bad | Should -BeNullOrEmpty
    }

    It '<Rel> loads the shared params file' -ForEach ($PhaseScripts | Where-Object Ext -eq '.ps1') {
        (Get-Content $Path -Raw) | Should -Match 'migration-params\.ps1'
    }
}

Describe 'Bash scripts' {
    It '<Rel> parses and sources the shared params file' -ForEach ($PhaseScripts | Where-Object Ext -eq '.sh') {
        if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'bash not installed'; return }
        bash -n $Path 2>&1 | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 0
        (Get-Content $Path -Raw) | Should -Match 'migration-params\.sh'
    }
}

Describe 'Layout and docs' {
    It 'every phase script appears in dashboard.html' -ForEach $PhaseScripts {
        (Get-Content (Join-Path $Root 'dashboard.html') -Raw) | Should -Match ([regex]::Escape($Rel))
    }

    It 'every phase script appears in the runbook' -ForEach $PhaseScripts {
        (Get-Content (Join-Path $Root 'Docs/Runbook.md') -Raw) | Should -Match ([regex]::Escape($Rel))
    }

    It 'phase scripts are numbered NN-Name and unique per folder' {
        $names = $PhaseScripts.Rel
        $names | Where-Object { $_ -notmatch '^0\d-[A-Za-z]+/\d\d-[A-Za-z0-9]+\.(ps1|sh)$' } | Should -BeNullOrEmpty
        ($names | ForEach-Object { ($_ -split '/')[0] + '/' + ($_ -split '/')[1].Substring(0, 2) } | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }
}

Describe 'Configuration' {
    It 'tracked params files hold placeholders only' {
        $guid = [regex]'[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'
        foreach ($f in 'migration-params.ps1', 'migration-params.sh') {
            foreach ($m in $guid.Matches((Get-Content (Join-Path $Root $f) -Raw))) {
                $m.Value | Should -Be '00000000-0000-0000-0000-000000000000'
            }
        }
    }

    It 'migration-params.local.ps1 overrides the template' {
        $tmp = Join-Path $TestDrive 'cfg'; New-Item -ItemType Directory $tmp | Out-Null
        Copy-Item (Join-Path $Root 'migration-params.ps1') $tmp
        Set-Content (Join-Path $tmp 'migration-params.local.ps1') '$sourceSubscriptionId = "override"'
        $out = pwsh -NoProfile -Command ". '$tmp/migration-params.ps1'; `"`$sourceSubscriptionId|`$sourceSubscription`""
        $out | Should -Be 'override|override'
    }
}

Describe 'Start-Migration.ps1 orchestrator' {
    BeforeAll {
        # Copy the repo, replace every phase script with a stub that just reports its name.
        $script:Sandbox = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory $Sandbox | Out-Null
        Get-ChildItem $Root -Force | Where-Object Name -notin '.git', 'migration-data', 'tests' | Copy-Item -Destination $Sandbox -Recurse
        Get-ChildItem $Sandbox -Recurse -File | Where-Object { $_.FullName -match '[\\/]0\d-[A-Za-z]+[\\/]' } | ForEach-Object {
            if ($_.Extension -eq '.ps1') { Set-Content $_.FullName 'Write-Output "RAN:$($MyInvocation.MyCommand.Name)"' }
            elseif ($_.Extension -eq '.sh') { Set-Content $_.FullName "echo RAN:$($_.Name)" }
        }
        Set-Content (Join-Path $Sandbox 'migration-params.local.ps1') '$sourceTenantId="t";$sourceSubscriptionId="s"'

        function script:Invoke-Orchestrator([string[]]$ScriptArgs, [string]$StdIn = '') {
            Push-Location $Sandbox
            try { $StdIn | pwsh -NoProfile -File ./Start-Migration.ps1 @ScriptArgs 2>&1 | Out-String }
            finally { Pop-Location }
        }
    }

    It 'runs a phase''s default scripts in numeric order and skips optional ones' {
        $out = Invoke-Orchestrator '-Phase', '3'
        $ran = [regex]::Matches($out, 'RAN:(\S+)').Value
        $ran.Count | Should -BeGreaterThan 10
        $ran | Should -Contain 'RAN:01-BackupResourceLocks.ps1'
        $ran | Should -Contain 'RAN:16-BackupVNetPeerings.ps1'
        $ran | Should -Contain 'RAN:17-ExportArmTemplatesByResourceGroup.ps1'
        $ran | Should -Not -Contain 'RAN:18-ExportArmTemplatesByResource.ps1'
        $ran | Should -Not -Contain 'RAN:19-UploadArmTemplatesToBlob.ps1'
        ($ran | Select-Object -First 3) | Should -Be @('RAN:01-BackupResourceLocks.ps1', 'RAN:02-BackupCustomRoles.ps1', 'RAN:03-BackupRoleAssignments.ps1')
    }

    It 'runs a single script when given its number' {
        $out = Invoke-Orchestrator '-Phase', '3' '7'
        [regex]::Matches($out, 'RAN:(\S+)').Value | Should -Be @('RAN:07-BackupSshKeys.sh')
    }

    It 'skips planning scripts that need a destination until one is configured' {
        $out = Invoke-Orchestrator '-Phase', '0'
        $out | Should -Match 'RAN:01-ExportAllPermissions.ps1'
        $out | Should -Not -Match 'RAN:03-ResolveTargetIdentities.ps1'
        $out | Should -Not -Match 'RAN:04-CompareSubscriptionQuotas.ps1'
    }

    It 'refuses destructive phases without YES' {
        $out = Invoke-Orchestrator '-Phase', '4' 'nope'
        $out | Should -Not -Match 'RAN:'
        $out | Should -Match 'Cancelled'
    }

    It 'runs destructive phases when confirmed with -Force' {
        $out = Invoke-Orchestrator '-Phase', '4', '-Force'
        $out | Should -Match 'RAN:01-DisableVMBackups.ps1'
        $out | Should -Not -Match 'RAN:08-DeleteBlockingResources.ps1'
    }

    It 'treats Migrate scripts as alternatives (runs nothing by default)' {
        Invoke-Orchestrator '-Phase', '5', '-Force' | Should -Not -Match 'RAN:'
    }

    It 'passes -AllResourceGroups to the resource group validation' {
        Set-Content (Join-Path $Sandbox '05-Migrate/01-ValidateResourceGroupMove.ps1') 'param([switch]$AllResourceGroups); Write-Output "RAN:validate all=$AllResourceGroups"'
        Invoke-Orchestrator '-Phase', '5', '-Force' '1' | Should -Match 'RAN:validate all=True'
    }
}

Describe 'Static analysis' {
    It 'PSScriptAnalyzer reports no errors' {
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Set-ItResult -Skipped -Because 'PSScriptAnalyzer not installed'; return }
        $r = Invoke-ScriptAnalyzer -Path $Root -Recurse -Severity Error
        $r | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName)" } | Should -BeNullOrEmpty
    }
}
