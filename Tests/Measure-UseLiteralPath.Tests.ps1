# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="The tests only need to define the params, we don't actually use them")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingCmdletAliases", "", Justification="The tests are actually testing that aliases work")]
param()

$verbose = @{}
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $verbose.Add("Verbose", $true)
}

$ps_version = $PSVersionTable.PSVersion.Major
$module_name = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$repo_name = (Get-ChildItem -Path $PSScriptRoot\.. -Directory -Exclude @(".git", "Tests")).Name
Import-Module -Name $PSScriptRoot\..\$repo_name -Force

$expected_rule_message = 'Use the explicit -LiteralPath parameter name instead of -Path'
$expected_rule_name = 'PSCustomUseLiteralPath'
$expected_rule_severity = 'Warning'

Describe "$module_name PS$ps_version tests" {
    Context 'Strict mode' {
        Set-StrictMode -Version latest

        It "Produces no warning with -LiteralPath" {
            $sb = {
                Get-Item -LiteralPath "C:\path"
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlockAst $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Produces no warning if -LiteralPath is not a valid parameter" {
            $sb = {
                New-Item -Path "C:\path" -ItemType Directory
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlockAst $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Scans parameter that only has -LiteralPath as a valid parameter for specific sets" {
            $sb = {
                $path = 'C:\temp'
                Split-Path -Path $path  # violation
                Split-Path -LiteralPath $path
                Split-Path -Path $path -Resolve # violation because -Resolve is a valid param for the -LiteralPath set
                Split-Path -Path $path -Leaf  # not a violation because -Leaf is not a valid param for the -LiteralPath set
                Split-Path $path -Leaf # not a violation like above
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 2
            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Split-Path -Path $path'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Split-Path -Path $path -Resolve'
        }

        It "Finds -Path with named parameter" {
            $sb = {
                Get-Item -Path "C:\path"
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlockAst $sb.Ast)
            $actual.Length | Should -Be 1
            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item -Path "C:\path"'
        }

        It "Finds -Path with positional parameter" {
            $sb = {
                $path = ""
                Remove-Item $path
                Remove-Item $path -Force -Recurse
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 2
            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Remove-Item $path'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Remove-Item $path -Force -Recurse'
        }

        It "Using an alias as the cmdlet" {
            $sb = {
                gci $path
                gci -Path $path
                gci -LiteralPath $path
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 2
            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'gci $path'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'gci -Path $path'
        }

        It "Using an alias that does not point to a cmdlet" {
            New-Alias -Name testalias -Value whoami.exe -Scope Global
            try {
                $sb = {
                    testalias $path
                }

                $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
                $actual.Length | Should -Be 0
            } finally {
                Remove-Item -Path Alias:testalias
            }
        }

        It "Using nested alias" {
            New-Alias -Name testalias1 -Value Get-Item -Scope Global
            New-Alias -Name testalias2 -Value testalias1 -Scope Global
            try {
                $sb = {
                    testalias2 $path
                }

                $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
                $actual.Length | Should -Be 1
                $actual[0].Message | Should -Be $expected_rule_message
                $actual[0].RuleName | Should -Be $expected_rule_name
                $actual[0].Severity | Should -be $expected_rule_severity
                $actual[0].Extent.Text | Should -Be 'testalias2 $path'
            } finally {
                Remove-Item -Path Alias:testalias1
                Remove-Item -Path Alias:testalias2
            }
        }

        It "Doesn't fail when encountering a dot or amphersand source command" {
            $sb = {
                Test-Path -literalpath $path
                .$path
                &$path
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Doesn't fail when encountering an unknown command" {
            $sb = {
                Test-MissingCommand -Path 'path'
                Test-MissingCommand -LiteralPath 'path'
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Doesn't fail when finding an invalid parameter set definition" {
            $sb = {
                # -InvalidParam is not a valid param in all parameter sets
                Get-Item -InvalidParam 'path' -Path $path
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Detects splatted params of hashes" {
            $sb = {
                $literal_path = @{
                    Path = "abc"
                }
                $index_path = @{}
                $index_path['Path'] = 'abc'
                $member_path = @{}
                $member_path.Path = 'abc'

                $literal_lpath = @{
                    LiteralPath = "abc"
                }
                $index_lpath = @{}
                $index_lpath['LiteralPath'] = 'abc'
                $member_lpath = @{}
                $member_lpath.LiteralPath = 'abc'

                $empty = @{}

                Get-Item @literal_path
                Get-Item @index_path
                Get-Item @member_path
                Get-Item @literal_lpath
                Get-Item @index_lpath
                Get-Item @member_lpath
                Get-Item @empty

                Get-Item -Force @literal_path
                Get-Item -Force @index_path
                Get-Item -Force @member_path
                Get-Item -Force @literal_lpath
                Get-Item -Force @index_lpath
                Get-Item -Force @member_lpath
                Get-Item -Force @empty
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 6

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item @literal_path'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Get-Item @index_path'

            $actual[2].Message | Should -Be $expected_rule_message
            $actual[2].RuleName | Should -Be $expected_rule_name
            $actual[2].Severity | Should -be $expected_rule_severity
            $actual[2].Extent.Text | Should -Be 'Get-Item @member_path'

            $actual[3].Message | Should -Be $expected_rule_message
            $actual[3].RuleName | Should -Be $expected_rule_name
            $actual[3].Severity | Should -be $expected_rule_severity
            $actual[3].Extent.Text | Should -Be 'Get-Item -Force @literal_path'

            $actual[4].Message | Should -Be $expected_rule_message
            $actual[4].RuleName | Should -Be $expected_rule_name
            $actual[4].Severity | Should -be $expected_rule_severity
            $actual[4].Extent.Text | Should -Be 'Get-Item -Force @index_path'

            $actual[5].Message | Should -Be $expected_rule_message
            $actual[5].RuleName | Should -Be $expected_rule_name
            $actual[5].Severity | Should -be $expected_rule_severity
            $actual[5].Extent.Text | Should -Be 'Get-Item -Force @member_path'
        }

        It "Detects splatted arg with dynamically added values" {
            $sb = {
                $hash1 = @{}
                $hash1.Add("Path", "path")

                $hash2 = @{}
                $hash2.Add("LiteralPath", "path")

                $hash3 = @{
                    Path = "path"
                }
                $hash3.Remove("Path")

                Get-Item @hash1
                Get-Item @hash2
                Get-item @hash3
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 1

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item @hash1'
        }

        It "Does not handle hash keys removed by variable reference" {
            $sb = {
                $var = "Path"
                $hash = @{
                    Path = "path"
                }
                # This won't work because the AST parser does not know the value of $var so it will
                # This could be partially solved if we track all vars but for now we just need to tes that it
                # doesn't blow up
                $hash.Remove($var)

                Get-Item @hash
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 1

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item @hash'
        }

        It "Does not fail if hash was source from an unknown function" {
            $sb = {
                $hash1 = [System.Test]::CreateHashtable()
                $hash1.Add("Path") = "C:\path"

                $hash2 = [System.Test]::CreateHashtable()
                $hash2.Path = "C:\path"

                $hash3 = [System.Test]::CreateHashtable()
                $hash3["Path"] = "C:\path"
            }

            # Because we don't know that CreateHashtable creates a hash we cannot analyze the parameters and no
            # warnings will be returned
            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Detects when 2 hashtables are merged" {
            $sb = {
                $bad_hash = @{
                    Path = "C:\path"
                }

                $hash1 = @{}
                $hash1 += $bad_hash
                $hash2 = $hash1 + $bad_hash  # currently won't work, we only support = operator when the right is a literal
                $hash3 = @{}
                $hash3 += @{"Path" = "C:\path"}
                $hash4 = @{}
                $hash4 + $bad_hash  # ensure we don't blow up, hash4 was not set to this value

                Get-Item @hash1
                Get-Item @hash2
                Get-Item @hash3
                Get-Item @hash4
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 2

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item @hash1'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Get-Item @hash3'
        }

        It "Detects array splats" {
            $sb = {
                $array_empty = @()

                $array_1 = @("C:\path")
                $array_2 = @("C:\path", $true)

                $array_list = [System.Collections.ArrayList]@("C:\path")
                $list = [System.Collections.Generic.List`1[String]]@("C:\path")

                Get-Item @array_empty  # won't match parameter set
                Get-Item @array_1
                Get-Item @array_2  # won't match parameter set
                Get-Item @array_list
                Get-item @list
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 3

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-Item @array_1'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Get-Item @array_list'

            $actual[2].Message | Should -Be $expected_rule_message
            $actual[2].RuleName | Should -Be $expected_rule_name
            $actual[2].Severity | Should -be $expected_rule_severity
            $actual[2].Extent.Text | Should -Be 'Get-Item @list'
        }

        It "No failure with illegal parameter set and positional args" {
            $sb = {
                $array = @("C:\path")
                Get-Item -Force @array  # won't fire because it doesn't match any parameter set, position == 1
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Detects position added with empty splat array" {
            $sb = {
                $array1 = @()
                $array1 += "C:\path"
                $array2 = @()
                $array2 += @("C:\path", $acl)
                $array_list = [System.Collections.ArrayList]@()
                $array_list.Add("C:\path")
                $array_list.Add($acl)
                $list = [System.Collections.Generic.List`1[String]]@()
                $list.Add("C:\path")
                $list.Add($acl)
                $list2 = [System.Collections.Generic.List`1[String]]@()
                $list2.Add($var1)
                $list2.Add($var2)

                Set-Acl @array1 -AclObject $acl
                Set-Acl @array2
                Set-Acl @array_list
                Set-Acl @list
                Set-Acl @list2
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 5

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Set-Acl @array1 -AclObject $acl'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Set-Acl @array2'

            $actual[2].Message | Should -Be $expected_rule_message
            $actual[2].RuleName | Should -Be $expected_rule_name
            $actual[2].Severity | Should -be $expected_rule_severity
            $actual[2].Extent.Text | Should -Be 'Set-Acl @array_list'

            $actual[3].Message | Should -Be $expected_rule_message
            $actual[3].RuleName | Should -Be $expected_rule_name
            $actual[3].Severity | Should -be $expected_rule_severity
            $actual[3].Extent.Text | Should -Be 'Set-Acl @list'

            $actual[4].Message | Should -Be $expected_rule_message
            $actual[4].RuleName | Should -Be $expected_rule_name
            $actual[4].Severity | Should -be $expected_rule_severity
            $actual[4].Extent.Text | Should -Be 'Set-Acl @list2'
        }

        It "Works with Aliases" {
            $sb = {
                Get-Item -PSPath "C:\path'"
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast)
            $actual.Length | Should -Be 0
        }

        It "Detects cmdlet with string constant var" {
            $sb = {
                Get-ChildItem C:\Path
                Get-ChildItem 'C:\Path'
                Get-ChildItem "C:\Path"
                Get-ChildItem @"
C:\Path
"@
                Get-ChildItem @'
C:\Path
'@
                Get-ChildItem -Path "C:\Path"
            }
            $nl = [System.Environment]::NewLine

            $actual = @(Measure-UseLiteralPath -ScriptBlockAst $sb.Ast)
            $actual.Length | Should -Be 6

            $actual[0].Message | Should -Be $expected_rule_message
            $actual[0].RuleName | Should -Be $expected_rule_name
            $actual[0].Severity | Should -be $expected_rule_severity
            $actual[0].Extent.Text | Should -Be 'Get-ChildItem C:\Path'

            $actual[1].Message | Should -Be $expected_rule_message
            $actual[1].RuleName | Should -Be $expected_rule_name
            $actual[1].Severity | Should -be $expected_rule_severity
            $actual[1].Extent.Text | Should -Be 'Get-ChildItem ''C:\Path'''

            $actual[2].Message | Should -Be $expected_rule_message
            $actual[2].RuleName | Should -Be $expected_rule_name
            $actual[2].Severity | Should -be $expected_rule_severity
            $actual[2].Extent.Text | Should -Be 'Get-ChildItem "C:\Path"'

            $actual[3].Message | Should -Be $expected_rule_message
            $actual[3].RuleName | Should -Be $expected_rule_name
            $actual[3].Severity | Should -be $expected_rule_severity
            $actual[3].Extent.Text | Should -Be ('Get-ChildItem @"' + $nl + 'C:\Path' + $nl + '"@')

            $actual[4].Message | Should -Be $expected_rule_message
            $actual[4].RuleName | Should -Be $expected_rule_name
            $actual[4].Severity | Should -be $expected_rule_severity
            $actual[4].Extent.Text | Should -Be ('Get-ChildItem @''' + $nl + 'C:\Path' + $nl + '''@')

            $actual[5].Message | Should -Be $expected_rule_message
            $actual[5].RuleName | Should -Be $expected_rule_name
            $actual[5].Severity | Should -be $expected_rule_severity
            $actual[5].Extent.Text | Should -Be 'Get-ChildItem -Path "C:\Path"'
        }

        It "Does not detect cmdlets that have a pipeline input" {
            $sb = {
                Get-Item -LiteralPath "C:\path" | Remove-Item -Force
            }

            $actual = @(Measure-UseLiteralPath -ScriptBlockAst $sb.Ast)
            $actual.Length | Should -Be 0
        }

        <#
        Describe "Mocked Resolve-SplatVariable tests" {
            Mock Resolve-SplatVariable {
                $ast = $args[1]
                if ($ast -is [System.Management.Automation.Language.AssignmentStatementAst] -and $ast.ToString() -eq '$a = ""') {
                    throw "testing"
                }
            } -ModuleName $repo_name

            It "Fails to parse splat variables" {
                $sb = {
                    $a = ""
                    Get-Item -Path "path"
                }

                $actual = @(Measure-UseLiteralPath -ScriptBlock $sb.Ast -WarningAction SilentlyContinue)
                $actual.Length | Should -Be 1

                $actual[0].Message | Should -Be $expected_rule_message
                $actual[0].RuleName | Should -Be $expected_rule_name
                $actual[0].Severity | Should -be $expected_rule_severity
                $actual[0].Extent.Text | Should -Be 'Get-Item -Path "path"'
            }
        }

        Describe "Mocked Confirm-ParameterSetMatch" {
            Mock Confirm-ParameterSetMatch {
                throw "fail"
            } -ModuleName $repo_name

            It "Throw terminating error on failure" {
                $sb = {
                    Get-Item -Path "path"
                }
                { Measure-UseLiteralPath -ScriptBlockAst $sb.Ast } | Should -Throw
            }
        }
        #>
    }
}
