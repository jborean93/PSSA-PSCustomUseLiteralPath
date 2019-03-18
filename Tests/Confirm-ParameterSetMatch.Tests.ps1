# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="The tests only need to define the params, we don't actually use them")]
param()

$verbose = @{}
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $verbose.Add("Verbose", $true)
}

$ps_version = $PSVersionTable.PSVersion.Major
$module_name = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$repo_name = (Get-ChildItem -Path $PSScriptRoot\.. -Directory -Exclude @("Tests")).Name
Import-Module -Name $PSScriptRoot\..\$repo_name -Force
. $PSScriptRoot\..\$repo_name\Private\$module_name.ps1

# Used for testing the Set-SplatVariable by passing in a ScriptBlock
[ScriptBlock]$test_block_predicate = {
    Param ([System.Management.Automation.Language.Ast]$Ast)
    if ($Ast -isnot [System.Management.Automation.Language.CommandAst]) {
        Set-SplatVariable -Ast $Ast -HashVars $script:test_hash_vars -ListVars $script:test_list_vars
    }
}

Describe "$module_name PS$ps_version tests" {
    Context 'Strict mode' {
        Set-StrictMode -Version latest

        It "Handles null values to ParameterSet" {
            $actual = Confirm-ParameterSetMatch -ParameterSet $null -UsedParameters @()
            $actual | Should -Be $false
        }
    }
}
