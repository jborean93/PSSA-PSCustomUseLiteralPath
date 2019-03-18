# PSSA-PSCustomUseLiteralPath

[![Build status](https://ci.appveyor.com/api/projects/status/s87rt38ceg1p3ihg?svg=true)](https://ci.appveyor.com/project/jborean93/pssa-pscustomuseliteralpath)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSSA-PSCustomUseLiteralPath.svg)](https://www.powershellgallery.com/packages/PSSA-PSCustomUseLiteralPath)

A custom [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
rule that analyses cmdlet invocations to make sure `-LiteralPath` is used
instead of `-Path`. This can be easily distributed through the PowerShell
Gallery or any other nuget feed.


## Info

**Severity Level: Warning**

### Description

In the majority of cases, the existing of both the `-Path` and `-LiteralPath`
parameters for a cmdlet means that `-Path` interprets wildcard characters like
`*`, `[`, `]`, etc whereas `-LiteralPath` interprets the path literally. This
can cause issues when you are dealing with a path like `C:\Company [Service]`,
`Get-Item -Path` will fail to get the path whereas `Get-Item -LiteralPath`
will work.

This rule will try to analyze every cmdlet invocation to see whether `-Path`
was used as a parameter but `-LiteralPath` can also be used. It will also try
and find instances of positional or splatted variables causing the `-Path`
parameter to be used. This analysis isn't perfect but should pick up the
majority of cases.

### How

Use `-LiteralPath` instead of `-Path` unless you really do need wildcard
expansion.

### Known Limitations

* Using splatted variables can become complicated if the splatted var is dynamically defined
* Managing a splatted variable dynamically or with variables won't be honoured
Defining a hash but then removing the key with a variable with `$hash.Remove($var)` won't be registered, the splat will still by analysed with the original key, e.g.

``` PowerShell
$hash = @{
    Path = "C:\path"
}
$hash.Remove("Path")

# Will not warn because .Remove() arg1 is a string which can be read by the analyzer. It knows Path is no longer a
# splatted variable
Get-item @hash 

$hash = @{
    Path = "C:\path"
}
$key = "Path"
$hash.Remove($key)

# Will warn because .Remove() arg1 is a variable which we don't know the value for. The analyzer does not know that
# Path is no longer a parameter being used
Get-Item @hash

$hash = @{}
$hash.Path = "C:\path"

# Will warn because the analyzer can see Path was added to the splatted var
Get-Item @hash

$hash = @{}
$hash.$key = "C:\path"

# Will not warn because the analyzer does not know the value for $key and doesn't know Path is a used parameter
Get-item @hash
```

* Nested dictionaries won't be analysed for splatted parameters
* The analyser won't detect a splatted params if the right side of the equals operator is not a hash literal, e.g. `$hash1 = $hash2 + $hash3` but the `+=` operators works
* Variables are not scope aware
* Splat variables initialised by `New-Object` are not tracked

### Example

#### Wrong

``` PowerShell
Get-Item -Path 'C:\Company [Service]'
```

#### Correct

``` PowerShell
Get-Item -LiteralPath 'C:\Company [Service]'
```


## Requirements

These cmdlets have the following requirements

* [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)


## Installing

The easiest way to install this module is through
[PowerShellGet](https://docs.microsoft.com/en-us/powershell/gallery/overview).
This is installed by default with PowerShell 5 but can be added on PowerShell
3 or 4 by installing the MSI [here](https://www.microsoft.com/en-us/download/details.aspx?id=51451).

Once installed, you can install this module by running;

``` PowerShell
# Install for all users
Install-Module -Name PSSA-PSCustomUseLiteralPath

# Install for only the current user
Install-Module -Name PSSA-PSCustomUseLiteralPath -Scope CurrentUser
```

If you wish to remove the module, just run
`Uninstall-Module -Name PSSA-PSCustomUseLiteralPath`.

If you cannot use PowerShellGet, you can still install the module manually,
here are some basic steps on how to do this;

1. Download the latext zip from GitHub [here](https://github.com/jborean93/PSSA-PSCustomUseLiteralPath/releases/latest)
2. Extract the zip
3. Copy the folder `PSSA-PSCustomUseLiteralPath` inside the zip to a path that is set in `$env:PSModulePath`. By default this could be `C:\Program Files\WindowsPowerShell\Modules` or `C:\Users\<user>\Documents\WindowsPowerShell\Modules`
4. Reopen PowerShell and unblock the downloaded files with `$path = (Get-Module -Name PSSA-PSCustomUseLiteralPath -ListAvailable).ModuleBase; Unblock-File -Path $path\*.psd1;`
5. Reopen PowerShell one more time and you can start using the cmdlets

_Note: You are not limited to installing the module to those example paths, you can add a new entry to the environment variable `PSModulePath` if you want to use another path._

Once installed you can use the module with PSScriptAnalyzer like;

``` PowerShell
# You can also just manually specify the path to the installed .psm1 file yourself
$module = Import-Module -Name PSSA-PSCustomUseLiteralPath -PassThru
$rule_path = Join-Path -Path $module.ModuleBase -ChildPath $module.RootModule

Invoke-ScriptAnalyzer -Path C:\temp\ps_script.ps1 -CustomRulePath $rule_path
```


## Contributing

Contributing is quite easy, fork this repo and submit a pull request with the
changes. To test out your changes locally you can just run `.\build.ps1` in
PowerShell. This script will ensure all dependencies are installed before
running the test suite.

_Note: this requires PowerShellGet or WMF 5 to be installed_
