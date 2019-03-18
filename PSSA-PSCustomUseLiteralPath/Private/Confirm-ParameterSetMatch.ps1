# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

Function Confirm-ParameterSetMatch {
    <#
    .SYNOPSIS
    Validates whether the list of parameters used will match the parameter set of a cmdlet.

    .DESCRIPTION
    Will return whether the parameters used when calling a cmdlet would be accepted by the parameter set specified.
    This will attempt to validate against both named and positional arguments.

    .PARAMETER ParameterSet
    The parameter set to validate against.

    .PARAMETER UsedParameters
    A list of parameter names, or an entry "positional parameter" that denotes the position of an unnamed parameter.

    .EXAMPLE
    $command = Get-Command -Name Get-Item

    # With named parameters
    Confirm-ParameterSetMatch -ParameterSet $command.ParameterSets[0] `
        -UsedParameters @("Path", "Force")

    # With a positional parameter for -Path
    Confirm-ParameterSetMatch -ParameterSet $command.ParameterSets[0] `
        -UsedParameters @("positional parameter", "Force")

    .OUTPUTS
    [System.Boolean]
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    Param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Management.Automation.CommandParameterSetInfo]
        $ParameterSet,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [String[]]
        $UsedParameters
    )

    if ($null -eq $ParameterSet) {
        return $false
    }

    $valid_names = $ParameterSet.Parameters.Name + $ParameterSet.Parameters.Aliases
    $valid_positions = @($ParameterSet.Parameters | Where-Object {
        $null -ne $_.Position -and $_.Position -ne [System.Int32]::MinValue
    } | ForEach-Object { $_.Position })
    $mandatory_params = @{}
    $ParameterSet.Parameters | Where-Object { $_.IsMandatory } | ForEach-Object {
        $mandatory_params.($_.Name) = if ($_.Position -eq [System.Int32]::MinValue) { $null } else { $_.Position }
    }

    for ($i = 0; $i -lt $UsedParameters.Count; $i++) {
        $used_param = $UsedParameters[$i]

        if ($used_param -eq "position parameter") {
            if ($i -notin $valid_positions) {
                return $false
            } elseif ($mandatory_params.ContainsValue($i)) {
                $param_name = $null
                foreach ($kvp in $mandatory_params.GetEnumerator()) {
                    if ($kvp.Value -eq $i) {
                        $param_name = $kvp.Key
                        break
                    }
                }
                $mandatory_params.Remove($param_name)
            }
        } elseif ($used_param -notin $valid_names) {
            return $false
        } elseif ($mandatory_params.ContainsKey($used_param)) {
            $mandatory_params.Remove($used_param) > $null
        }
    }

    return $mandatory_params.Keys.Count -eq 0
}
