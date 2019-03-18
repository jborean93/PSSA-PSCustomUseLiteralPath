# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

Function Measure-UseLiteralPath {
    <#
    .SYNOPSIS
    The -LiteralPath parameter should always be used instead of -Path.

    .DESCRIPTION
    Using -Path means the PowerShell cmdlet will interpret glob like characters ([, ]) and potentially perform the
    action on multiple objects. In most cases we only want to perform this using the literal path and should be using
    the -LiteralPath parameter to do so.

    .EXAMPLE
    Measure-UseLiteralPath -ScriptBlockAst $ScriptBlockAst

    .INPUTS
    [System.Management.Automation.Language.ScriptBlockAst]

    .OUTPUTS
    [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]

    .NOTES
    This is an Ansible built rule and not part of the standard PSScriptAnalyzer project.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord])]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    # Keep details of a splat compatible variable so we can try and analyse if the splat var uses the -Path parameter
    # hash_vars == @{ variable_name = list of variable keys }
    # list_vars == @{ variable_name = number of entries in list }
    $hash_vars = @{}
    $list_vars = @{}

    [ScriptBlock]$predicate = {
        Param ([System.Management.Automation.Language.Ast]$Ast)

        if ($Ast -isnot [System.Management.Automation.Language.CommandAst]) {
            # While the current AST is not a cmdlet, we want to try and keep track of each variable for splat usages
            try {
                Resolve-SplatVariable -Ast $Ast -HashVars $hash_vars -ListVars $list_vars
            } catch {
                $nl = [System.Environment]::NewLine
                $msg = "Failed to analyze AST for splat compatible variables$nl$nl"
                $msg += $_ | Out-String
                $msg += $nl + $_.ScriptStackTrace
                Write-Warning -Message $msg
            }
            return
        } elseif ($Ast.InvocationOperator -ne "Unknown") {
            # Was invocated with '.' or '&', we will ignore these
            return
        }

        # Get the cmdlet info, resolve the alias if it is one
        $command = Get-Command -Name $Ast.GetCommandName() -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            # Not a known/imported cmdlet, cannot check for violations
            return
        }
        if ($command.CommandType -eq "Alias") {
            $command = $command.ResolvedCommand
        }

        # Ignore the cmdlet if it does not contains both -Path and -LiteralPath
        if (-not ($command.Parameters.ContainsKey("Path") -and $command.Parameters.ContainsKey("LiteralPath"))) {
            return
        }

        # Expand any splatted vars and keep a list of each parameter used
        $used_parameters = [System.Collections.Generic.List`1[Object]]@()
        $param_value = $false
        foreach ($element in $Ast.CommandElements) {
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                $var_name = $element.VariablePath.UserPath
                if ($hash_vars.ContainsKey($var_name)) {
                    $parameters = $hash_vars.$var_name
                    foreach ($parameter in $parameters) {
                        $used_parameters.Add($parameter)
                    }
                } elseif ($list_vars.ContainsKey($var_name)) {
                    $count = $list_vars.$var_name
                    for ($i = 0; $i -lt $count; $i++) {
                        $used_parameters.Add("position parameter")
                    }
                }
            } elseif ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $used_parameters.Add($element.ParameterName)
                $param_value = $true
            } elseif ($element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                if ($param_value) {
                    $param_value = $false
                } else {
                    $used_parameters.Add("position parameter")
                }
            }
        }

        # Check if -LiteralPath is being used directly as a named parameter
        $lpath_aliases = [String[]](@("LiteralPath") + @($command.Parameters.GetEnumerator() | Where-Object {
            $_.Key -eq "LiteralPath" } | ForEach-Object { $_.Value.Aliases }))
        if (@([System.Linq.Enumerable]::Intersect($used_parameters, $lpath_aliases)).Length -gt 0) {
            return
        }

        # Loop through the parameter sets until we find a match
        $parameter_sets = $command.ParameterSets | Sort-Object -Property IsDefault -Descending
        $matched_set = $null
        foreach ($ps in $parameter_sets) {
            if (Confirm-ParameterSetMatch -ParameterSet $ps -UsedParameters $used_parameters) {
                $matched_set = $ps
                break
            }
        }

        if ($null -eq $matched_set) {
            # No parameter sets matched, either we don't have enough info or there is a bug, either way we don't want
            # to flag a false positive
            return
        } elseif ("LiteralPath" -in $matched_set.Parameters.Name) {
            # A -LiteralPath parameter set was matched, no violation
            return
        }

        # Because we matched with a parameter set that used -Path, we need to validate whether we could have used
        # -LiteralPath instead. We do this by getting the parameters actually used by name, converting -Path to
        # -LiteralPath and then comparing that against the valid -LiteralPath parameter sets.
        # Get a list of matched parameters
        $converted_parameters = [System.Collections.Generic.List`1[String]]@()
        for ($i = 0; $i -lt $used_parameters.Count; $i++) {
            $parameter = $used_parameters[$i]

            if ($parameter -eq "position parameter") {
                # If the code used a positional parameter, get the actual param name from the matched set
                $positioned_parameter = $matched_set.Parameters | Where-Object { $_.Position -eq $i }
                $parameter = $positioned_parameter.Name
            }

            if ($parameter -eq "Path") {
                # Because we want to match against -LiteralPath, we need to convert -Path to -LiteralPath
                $parameter = "LiteralPath"
            }
            $converted_parameters.Add($parameter)
        }

        $l_parameter_sets = $command.ParameterSets | Where-Object { "LiteralPath" -in $_.Parameters.Name }
        foreach ($ps in $l_parameter_sets) {
            if (Confirm-ParameterSetMatch -ParameterSet $ps -UsedParameters $converted_parameters) {
                # A parameter set that used -LiteralPath could have been used
                return $true
            }
        }
    }

    try {
        [System.Management.Automation.Language.Ast[]]$violations = $ScriptBlockAst.FindAll($predicate, $true)
        If ($violations.Count -ne 0) {
            foreach ($violation in $violations) {
                [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                    Extent = $violation.Extent
                    Message = "Use the explicit -LiteralPath parameter name instead of -Path"
                    RuleName = "PSCustomUseLiteralPath"
                    Severity = "Warning"
                }
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
