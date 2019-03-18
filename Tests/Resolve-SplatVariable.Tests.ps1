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
        Resolve-SplatVariable -Ast $Ast -HashVars $script:test_hash_vars -ListVars $script:test_list_vars
    }
}

Describe "$module_name PS$ps_version tests" {
    Context 'Strict mode' {
        Set-StrictMode -Version latest

        BeforeEach {
            $script:test_hash_vars = @{}
            $script:test_list_vars = @{}
        }

        It "Splat list definitions" {
            $sb = {
                $array_empty = @()
                $array_single = @("a")
                $array_single_int = @(1)
                $array_single_var = @($var)
                $array_multiple = @("a", "b")
                $array_multiple_bare = "a", "b"

                $list_empty = [System.Collections.Generic.List`1[String]]@()
                $list_single = [System.Collections.Generic.List`1[String]]@("a")
                $list_single_int = [System.Collections.Generic.List`1[String]]@(1)
                $list_single_var = [System.Collections.Generic.List`1[String]]@($var)
                $list_multiple = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list_multiple_bare = [System.Collections.Generic.List`1[String]]"a", "b"

                $alist_empty = [System.Collections.ArrayList]@()
                $alist_single = [System.Collections.ArrayList]@("a")
                $alist_single_int = [System.Collections.ArrayList]@(1)
                $alist_single_var = [System.Collections.ArrayList]@($var)
                $alist_multiple = [System.Collections.ArrayList]@("a", "b")
                $alist_multiple_bare = [System.Collections.ArrayList]"a", "b"
            }

            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.array_empty | Should -Be 0
            $script:test_list_vars.array_single | Should -Be 1
            $script:test_list_vars.array_single_int | Should -Be 1
            $script:test_list_vars.array_single_var | Should -Be 1
            $script:test_list_vars.array_multiple | Should -Be 2
            $script:test_list_vars.array_multiple_bare | Should -Be 2

            $script:test_list_vars.list_empty | Should -Be 0
            $script:test_list_vars.list_single | Should -Be 1
            $script:test_list_vars.list_single_int | Should -Be 1
            $script:test_list_vars.list_single_var | Should -Be 1
            $script:test_list_vars.list_multiple | Should -Be 2
            $script:test_list_vars.list_multiple_bare | Should -Be 2

            $script:test_list_vars.alist_empty | Should -Be 0
            $script:test_list_vars.alist_single | Should -Be 1
            $script:test_list_vars.alist_single_int | Should -Be 1
            $script:test_list_vars.alist_single_var | Should -Be 1
            $script:test_list_vars.alist_multiple | Should -Be 2
            $script:test_list_vars.alist_multiple_bare | Should -Be 2
        }

        It "Splat list with +=" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("a")
                $list2 = [System.Collections.Generic.List`1[String]]@("b")
                $list3 = [System.Collections.Generic.List`1[String]]@("d", "e")
                $list4 = [System.Collections.Generic.List`1[String]]@()
                $array_list1 = [System.Collections.ArrayList]@("a")
                $array_list2 = [System.Collections.ArrayList]@("b")
                $array_list3 = [System.Collections.ArrayList]@("d", "e")
                $array_list4 = [System.Collections.ArrayList]@()

                $list1 += $list2
                $list1 += $list3
                $list1 += $list4
                $list += @()
                $list1 += "f", "g"
                $array_list1 += $array_list2
                $array_list1 += $array_list3
                $array_list1 += $array_list4
                $array_list1 += ,"f"
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 6
            $script:test_list_vars.array_list1 | Should -Be 5
        }

        It "Splat hash with +=" {
            $sb = {
                $hash1 = @{}
                $hash2 = @{Path = "path"}
                $hash1 += $hash2
                $hash1 += @{"Force" = $true}
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_hash_vars.hash1 | Should -Be ([System.Collections.Generic.List`1[String]]@("Path", "Force"))
        }

        It "Splat list .Add()" {
            $sb = {
                $list = [System.Collections.Generic.List`1[String]]@()
                $alist = [System.Collections.ArrayList]@()

                $list.Add("1")
                $list.Add($var)

                $alist.Add("1")
                $alist.Add($var)
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list | Should -Be 2
            $script:test_list_vars.alist | Should -Be 2
        }

        It "Splat hash .Add()" {
            $sb = {
                $hash = @{}
                $hash.Add("Path", "value")
                $hash.Add("Force", $var)
                $hash.Add($var, "value")  # won't be recorded as it is a var and we don't know the value
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_hash_vars.hash | Should -Be ([System.Collections.Generic.List`1[String]]@("Path", "Force"))
        }

        It "Splat list with AddRange" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list2 = [System.Collections.Generic.List`1[String]]@("c", "d")
                $list1.AddRange($list2)
                $list1.AddRange($fake_var)  # validates that we don't bomb out if we don't know the var
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 4
        }

        It "Splat list with Insert" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("a")
                $list1.Insert(0, "item")
                $list1.Insert(1, $var)
                $fake_list.Insert(0, "item")  # validates we don't bomb out if the var for list is not set
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 3
            $script:test_list_vars.ContainsKey("fake_list") | Should -Be $false
        }

        It "Splat list with InsertRange" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list2 = [System.Collections.Generic.List`1[String]]@("c", "d")
                $list1.InsertRange(0, $list2)
                $list1.AddRange(0, $fake_var)  # validates that we don't bomb out if we don't know the var
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 4
        }

        It "Splat list with Remove" {
            $sb = {
                $list = [System.Collections.Generic.List`1[String]]@("C:\path")
                $list.Remove("C:\path")
            }

            $sb.Ast.FindAll($test_block_predicate, $true)

            # We do not support .Remove with List as we don't track the actual list values and therefore cannot check
            # if it would truly be removed
            $script:test_list_vars.list | Should -Be 1
        }

        It "Splat hash with Remove" {
            $sb = {
                $hash = @{
                    Path = "path"
                    Force = $true
                }
                $hash.Remove("Path")
            }

            $sb.Ast.FindAll($test_block_predicate, $true)

            # We do not support .Remove with List as we don't track the actual list values and therefore cannot check
            # if it would truly be removed
            $script:test_hash_vars.hash | Should -Be ([System.Collections.Generic.List`1[String]]@("Force"))
        }

        It "Splat list with RemoveAt" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("C:\path", $true)
                $list2 = [System.Collections.ArrayList]@("C:\path", $true)
                $list3 = [System.Collections.Generic.List`1[String]]@("C:\path")
                $list4 = [System.Collections.ArrayList]@("C:\path")
                $list1.RemoveAt(1)
                $list2.RemoveAt(2)  # list2 does not have an entry at index 2
                $list3.RemoveAt("0")
                $list4.RemoveAt($idx)
            }

            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 1
            $script:test_list_vars.list2 | Should -Be 2  # .RemoveAt was at an index not possible so nothing was removed
            $script:test_list_vars.list3 | Should -Be 0
            $script:test_list_vars.list4 | Should -Be 1  # .RemoveAt analysis does not support vars
        }

        It "Splat list with RemoveRange" {
            $sb = {
                $list1 = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list1.RemoveRange(0, 0)
                $list1.RemoveRange(0, 1)
                $list1.RemoveRange(0, $var)  # Won't know the value so this will fail
                $list1.RemoveRange($var, 1)  # Won't know the value so this will fail

                $list2 = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list2.RemoveRange(3, 2)  # won't do anything as it is out of the range

                $list3 = [System.Collections.Generic.List`1[String]]@("a", "b")
                $list3.RemoveRange(0, 3)  # we keep on removing until we reach 0
            }
            $sb.Ast.FindAll($test_block_predicate, $true)

            $script:test_list_vars.list1 | Should -Be 1
            $script:test_list_vars.list2 | Should -Be 2
            $script:test_list_vars.list3 | Should -Be 0
        }
    }
}
