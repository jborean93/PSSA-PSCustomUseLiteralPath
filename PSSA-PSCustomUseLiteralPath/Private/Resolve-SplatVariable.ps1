# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)
Function Resolve-SplatVariable {
    <#
    .SYNOPSIS
    Attempts to track splat compatible variables that are defined in an AST.

    .DESCRIPTION
    Will analyse the AST passed in and set any hash/dict, array/list variables that are found. It will also try to
    keep track of any keys or entries added to these variables in the relevant hash param passed in.

    .PARAMETER Ast
    The AST to inspect and track. Only AssignmentStatementAst and InvokeMemberExpressionAst are analysed, the get are
    skipped.

    .PARAMETER HashVars
    A hashtable where the key is the variable name and the value is a list of keys that have been set in the variable.

    .PARAMETER ListVars
    A hashtable where the key is the variable name and the value is the current number of entries for the list/array it
    references.

    .EXAMPLE
    $hash_vars = @{}
    $list_vars = @{}
    Resolve-SplatVariable -Ast $sb_ast -HashVars $hash_vars -ListVars $list_vars

    .NOTES
    This is not perfect but just a best effort attempt to track splat compatible vars used for later analysis.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.Ast]
        $Ast,

        [Parameter(Mandatory = $true)]
        [Hashtable]
        $HashVars,

        [Parameter(Mandatory = $true)]
        [Hashtable]
        $ListVars
    )

    if ($Ast -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Ast.Right -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $implemented_interfaces = $Ast.Right.Expression.StaticType.ImplementedInterfaces | ForEach-Object { $_.FullName }

        if ("System.Collections.IDictionary" -in $implemented_interfaces -and $Ast.Operator -eq "Equals") {
            # Is a splat capable variable as a Hashtable/Dictionary, record the var and keys being set
            $keys = [System.Collections.Generic.List`1[String]]@()
            foreach ($entry in $Ast.Right.Expression.KeyValuePairs) {
                $keys.Add($entry.Item1.Value)
            }
            $HashVars.($Ast.Left.VariablePath.UserPath) = $keys
        } elseif ("System.Collections.IList" -in $implemented_interfaces -and $Ast.Operator -eq "Equals") {
            # Is a splat capable variable as a List/Array, record the var and number of entries
            $var_name = $Ast.Left.VariablePath.UserPath

            if ($Ast.Right.Expression -is [System.Management.Automation.Language.ArrayExpressionAst]) {
                # Standard array definition = @()
                if ($Ast.Right.Expression.SubExpression.Statements.Count -eq 0) {
                    $count = 0
                } else {
                    $value_exp = $Ast.Right.Expression.SubExpression.Statements[0].PipelineElements[0].Expression
                    if ($value_exp -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                        $count = $value_exp.Elements.Count
                    } else {
                        $count = 1
                    }
                }
                $ListVars.$var_name = $count
            } elseif ($Ast.Right.Expression -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                # array = "a", "b"
                $ListVars.$var_name = $Ast.Right.Expression.Elements.Count
            } elseif ($Ast.Right.Expression -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                # ArrayList/List from Array = [System.Collections.ArrayList]@()
                if ($Ast.Right.Expression.Child.SubExpression.Statements.Count -eq 0) {
                    $count = 0
                }  else {
                    $value_exp = $Ast.Right.Expression.Child.SubExpression.Statements[0].PipelineElements[0].Expression
                    if ($value_exp -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                        $count = $value_exp.Elements.Count
                    } else {
                        $count = 1
                    }
                }

                $ListVars.$var_name = $count
            }
        }  elseif ($Ast.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                $Ast.Left.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
            # $hashtable.Path = ''
            $var_name = $Ast.Left.Expression.VariablePath.UserPath
            if ($HashVars.ContainsKey($var_name)) {
                $properties = $HashVars.$var_name
            } else {
                $properties = [System.Collections.Generic.List`1[String]]@()
            }
            $properties.Add($Ast.Left.Member.Value)
            $HashVars.$var_name = $properties
        } elseif ($Ast.Left -is [System.Management.Automation.Language.IndexExpressionAst]) {
            # $hashtable["Path"] = ''
            $var_name = $Ast.Left.Target.VariablePath.UserPath
            if ($HashVars.ContainsKey($var_name)) {
                $properties = $HashVars.$var_name
            } else {
                $properties = [System.Collections.Generic.List`1[String]]@()
            }
            $properties.Add($Ast.Left.Index.Value)
            $HashVars.$var_name = $properties
        } elseif ($Ast.Operator -eq "PlusEquals") {
            $var_name = $Ast.Left.VariablePath.UserPath
            if ($HashVars.ContainsKey($var_name)) {
                # $hash += @{}
                $target_hash = $HashVars.$var_name

                if ($Ast.Right.Expression -is [System.Management.Automation.Language.HashtableAst]) {
                    $keys = [System.Collections.Generic.List`1[String]]@()
                    foreach ($entry in $Ast.Right.Expression.KeyValuePairs) {
                        $keys.Add($entry.Item1.Value)
                    }
                    $target_hash.AddRange($keys)
                } else {
                    $source_hash = $Ast.Right.Expression.VariablePath.UserPath
                    if ($HashVars.ContainsKey($source_hash)) {
                        $target_hash.AddRange($HashVars.$source_hash)
                    }
                }
            } elseif ($ListVars.ContainsKey($var_name)) {
                # $array += ""
                $count = $ListVars.$var_name

                if ($Ast.Right.Expression -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                    $count += $Ast.Right.Expression.Elements.Count
                } elseif ($Ast.Right.Expression.StaticType.IsArray) {
                    # Adding an array of x elements
                    $count += $Ast.Right.Expression.SubExpression.Statements[0].PipelineElements[0].Expression.Elements.Count
                } else {
                    # Adding single element
                    $count += 1
                }
                $ListVars.$var_name = $count
            }
        }
    } elseif ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $Ast.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
        # Keeps track of all values that are added and removed in the each hash and list
        $method = $Ast.Member.Value
        $var_name = $Ast.Expression.VariablePath.UserPath

        if (-not ($HashVars.ContainsKey($var_name) -or $ListVars.ContainsKey($var_name))) {
            # A method on a variable that is not one of our known hash/list vars
            return
        }

        if ($method -eq "Add") {
            if ($HashVars.ContainsKey($var_name) -and $Ast.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $HashVars.$var_name.Add($Ast.Arguments[0].Value)
            } elseif ($ListVars.ContainsKey($var_name)) {
                $ListVars.$var_name += 1
            }
        } elseif ($method -eq "AddRange") {
            if ($ListVars.ContainsKey($var_name) -and $Ast.Arguments[0] -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $added_range_var = $Ast.Arguments[0].VariablePath.UserPath
                if ($ListVars.ContainsKey($added_range_var)) {
                    $ListVars.$var_name += $ListVars.$added_range_var
                }
            }
        } elseif ($method -eq "Insert") {
            if ($Listvars.ContainsKey($var_name)) {
                $ListVars.$var_name += 1
            }
        } elseif ($method -eq "InsertRange") {
            if ($ListVars.ContainsKey($var_name) -and $Ast.Arguments[1] -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $added_range_var = $Ast.Arguments[1].VariablePath.UserPath
                if ($ListVars.ContainsKey($added_range_var)) {
                    $ListVars.$var_name += $ListVars.$added_range_var
                }
            }
        } elseif ($method -eq "Remove") {
            # Cannot do remove from List as we don't know if it contains the value we want to remove
            if ($HashVars.ContainsKey($var_name) -and $Ast.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $HashVars.$var_name.Remove($Ast.Arguments[0].Value) > $null
            }
        } elseif ($method -eq "RemoveAt") {
            if ($ListVars.ContainsKey($var_name) -and $Ast.Arguments[0] -is [System.Management.Automation.Language.ConstantExpressionAst]) {
                $idx = [int]$Ast.Arguments[0].Value
                if ($idx -lt $ListVars.$var_name) {
                    $ListVars.$var_name -= 1
                }
            }
        } elseif ($method -eq "RemoveRange") {
            if ($ListVars.ContainsKey($var_name) -and $Ast.Arguments[0] -is [System.Management.Automation.Language.ConstantExpressionAst] -and
                    $Ast.Arguments[1] -is [System.Management.Automation.Language.ConstantExpressionAst]) {
                $idx = [int]$Ast.Arguments[0].Value
                $count = [int]$Ast.Arguments[1].Value

                if ($idx -lt $ListVars.$var_name) {
                    $new_count = $ListVars.$var_name - $count
                    $ListVars.$var_name = [Math]::Max(0, $new_count)
                }
            }
        }
    }
}
