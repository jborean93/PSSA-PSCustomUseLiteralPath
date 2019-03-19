# Copyright: (c) 2018, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

@{
    RootModule = 'PSSA-PSCustomUseLiteralPath.psm1'
    ModuleVersion = '0.1.1'
    GUID = '7c633146-989a-4a37-bc16-1f29a17be3db'
    Author = 'Jordan Borean'
    Copyright = 'Copyright (c) 2019 by Jordan Borean, Red Hat, licensed under MIT.'
    Description = "Contains the PSScriptAnalyzer custom rule PSCustomUseLiteralPath to detect cases when -Path is used instead of -LiteralPath.`nSee https://github.com/jborean93/PSSA-PSCustomUseLiteralPath for more info"
    PowerShellVersion = '3.0'
    FunctionsToExport = @(
        "Measure-UseLiteralPath"
    )
    PrivateData = @{
        PSData = @{
            Tags = @(
                "DevOps",
                "lint",
                "bestpractice",
                "PSScriptAnalyzer"
            )
            LicenseUri = 'https://github.com/jborean93/PSSA-PSCustomUseLiteralPath/blob/master/LICENSE'
            ProjectUri = 'https://github.com/jborean93/PSSA-PSCustomUseLiteralPath'
            ReleaseNotes = 'See https://github.com/jborean93/PSSA-PSCustomUseLiteralPath/blob/master/CHANGELOG.md'
        }
    }
}
