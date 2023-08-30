Using Module ".\LanguageOption.psm1"

Import-Module "${env:ProgramFiles(x86)}\Microsoft Dynamics NAV\*\RoleTailored Client\NavModelTools.ps1" -DisableNameChecking -Force -NoClobber | Out-Null

$Error.clear()

<#
.SYNOPSIS
    Starts the translation update process, using Base- and Work- language id parameters.

.DESCRIPTION
    The process is performed semi-automatically.
    You provide three parameters:
        -Path, pointing to the folder where the objects for translation are located.
        -BaseLanguageId, as a base language which will be used for making translations from.
        -WorkLanguageId, as a language which will be checked.

    The script will find all the objects recursively within the Path.
    For an every NAV object file you will be shown an existing translation and asked to enter a missing translation.
    You can write or paste translated string and confirm it.
    This translation will be added to the dictionary and will be used for the next translations.

    Finally, the "Work" Language will be imported to the object file.

    IMPORTANT: Expected encoding is UTF8: for NAV objects, translations and dictionary.

.EXAMPLE
    Stan wants to translate NAV objects from English to German.
    Prerequisites:
        - NAV objects has been exported to "Path" folder
        - NAV objects are in UTF8 encoding
        - ENU Language layer is existing in NAV objects and/or expected as base DevelopmentLanguage

    Stan runs the following command:
    > Start-TranslationProcess -Path .\Objects -BaseLanguageId ENU -WorkLanguageId DEU

    Result:
        - The script will find all the objects recursively and will help automate translation process.
        - Translations dictionary will be created in ".\.dictionary\<BaseLanguageId>_<WorkLanguageId>.csv"
        - Dictionary will be automatically reused for any further translations given the same Base and Missing language ids.

.PARAMETER Path
    Path to the folder where NAV objects are located.

.PARAMETER BaseLanguageId
    Language Id which will be used as a base for translations.

.PARAMETER WorkLanguageId
    Language Id which will be checked.
#>
function Start-TranslationProcess {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Path,

        [Parameter(mandatory = $true)]
        [LanguageOption] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [LanguageOption] $WorkLanguageId
    )

    begin {
        if ($BaseLanguageId -eq $WorkLanguageId) {
            throw "BaseLanguageId and WorkLanguageId cannot be the same."
        }
        $LanguageSetup = MakeSetup -BaseLanguageId $BaseLanguageId -WorkLanguageId $WorkLanguageId
        $Dict = GetDictionary -LanguageSetup $LanguageSetup
        $ObjectFiles = Get-ChildItem $Path -File -Recurse -Exclude '*_*'

        Write-Host "Total files for translation: $($ObjectFiles.Count)" -ForegroundColor Cyan
        Write-Host
    }

    process {
        foreach ($File in $ObjectFiles) {
            Write-Host "============================================" -ForegroundColor Cyan
            Write-Host "File: $($File.Name)" -ForegroundColor White

            if (!(FileHaveMissingTranslation -FilePath $File.FullName -LanguageId $WorkLanguageId)) {
                Write-Host "Nothing to translate"
                Write-Host
                continue
            }

            $TranslationFiles = Export-LanguageFiles -File $File -BaseLanguageId $LanguageSetup.BaseLanguageId -WorkLanguageId $LanguageSetup.WorkLanguageId
            $MissingTranslationsFileContent = Get-Content -Path $TranslationFiles.MissingTranslationsFile -Encoding utf8
            Write-Host "Missing Translations: $($MissingTranslationsFileContent.Count)"

            foreach ($Line in $MissingTranslationsFileContent) {
                Update-TranslationLine -Line $Line -LanguageSetup $LanguageSetup -TranslationFiles $TranslationFiles -Dict $Dict
            }

            Import-Translation -FilePath $File.FullName -LanguagePath $TranslationFiles.WorkLanguageFile -LanguageId $LanguageSetup.WorkLanguageId
            Remove-TrenslationFiles -TranslationFiles $TranslationFiles
            Write-Host "$($File.Name) updated" -ForegroundColor White
        }

    }
    end {
        SaveDictionary -LanguageSetup $LanguageSetup -Dict $Dict
    }
}

function Update-TranslationLine {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Line,

        [Parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup,

        [Parameter(mandatory = $true)]
        [pscustomobject] $TranslationFiles,

        [Parameter(mandatory = $true)]
        [hashtable] $Dict

    )
    $Pattern = GetPattern -Line $Line -WorkLanguageId $LanguageSetup.WorkLanguageId
    $BaseLanguageString = GetLanguageString -LanguageFile $TranslationFiles.BaseLanguageFile -Pattern $Pattern
    $WorkLanguageString = GetLanguageString -LanguageFile $TranslationFiles.WorkLanguageFile -Pattern $Pattern

    Write-Host
    Write-Host "Pattern: $Pattern" -ForegroundColor White
    Write-Host "$($LanguageSetup.BaseLanguageId) String: " -NoNewline
    Write-Host $BaseLanguageString -ForegroundColor Yellow
    $DictValue = $Dict[$BaseLanguageString]

    if ($WorkLanguageString -ne '') {
        Write-Host "$($LanguageSetup.WorkLanguageId) String: " -NoNewline
        Write-Host $WorkLanguageString -ForegroundColor Yellow
        if ([string]::IsNullOrEmpty($DictValue)) {
            $Dict.Add($BaseLanguageString, $WorkLanguageString)
        }
    } else {
        if ([string]::IsNullOrEmpty($DictValue)) {
            $WorkLanguageString = Get-NewStringValueFromUser -WorkLanguageId $LanguageSetup.WorkLanguageId -BaseLanguageString $BaseLanguageString
            $Dict.Add($BaseLanguageString, $WorkLanguageString)
        } else {
            $WorkLanguageString = $DictValue
            Write-Host "$($LanguageSetup.WorkLanguageId) string: " -NoNewline
            Write-Host $WorkLanguageString -ForegroundColor Yellow -NoNewline
            Write-Host " (copied from dictionary)" -ForegroundColor DarkGray
        }
        SetLanguageString -LanguageFile $TranslationFiles.WorkLanguageFile -Pattern $Pattern -NewValue $WorkLanguageString
        Write-Host
    }
}

function Get-NewStringValueFromUser {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $WorkLanguageId,

        [Parameter(mandatory = $true)]
        [string] $BaseLanguageString
    )
    $WorkLanguageString = ''
    $Confirmed = $false
    while (!$Confirmed) {
        $BaseLanguageString | Set-Clipboard
        $WorkLanguageString = Read-Host -Prompt "Enter $WorkLanguageId string"
        if (![string]::IsNullOrEmpty($WorkLanguageString)) {
            Write-Host "$WorkLanguageId string: " -NoNewline
            Write-Host $WorkLanguageString -ForegroundColor Yellow
            $Confirmed = GetUserConfirmation -Text "Looks correct"

        }
    }
    return $WorkLanguageString
}

function Import-Translation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $FilePath,

        [Parameter(mandatory = $true)]
        [string] $LanguagePath,

        [Parameter(mandatory = $true)]
        [LanguageOption] $LanguageId
    )
    try {
        $Params = @{
            Source       = $FilePath
            Destination  = $FilePath
            LanguagePath = $LanguagePath
            LanguageId   = $LanguageId
            Encoding     = 'UTF8'
            Force        = $true
        }
        Import-NAVApplicationObjectLanguage @Params
    } catch {
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        throw $_
    }
}

function GetLanguageString {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $LanguageFile,

        [Parameter(mandatory = $true)]
        [string] $Pattern
    )
    $Line = Get-Content -Path $LanguageFile -Encoding utf8 | Select-String -Pattern $Pattern
    if ([string]::IsNullOrEmpty($Line)) {
        return ''
    }
    return $Line.ToString().Remove(0, $Line.ToString().IndexOf(':') + 1)
}

function SetLanguageString {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $LanguageFile,

        [Parameter(mandatory = $true)]
        [string] $Pattern,

        [Parameter(mandatory = $true)]
        [string] $NewValue
    )

    $Content = Get-Content -Path $LanguageFile -Encoding utf8
    $Line = $Content | Select-String -Pattern $Pattern
    $LineString = $Line.ToString()
    $NewLine = $LineString.Substring(0, $LineString.IndexOf(':') + 1) + $NewValue
    $Content.Replace($Line, $NewLine) | Set-Content $LanguageFile -Encoding utf8
}

<#
.SYNOPSIS
    Removes empty lines from a file and overwrites it.
    Empty lines appear as a bug during export language process.
#>
function Remove-EmptyLinesFromFile {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Path
    )
    $c = Get-Content -Path $Path -Encoding utf8
    $c | Where-Object { $_ -ne '' } | Set-Content -Path $Path -Encoding utf8
}

function GetPattern {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Line,

        [Parameter(mandatory = $true)]
        [LanguageOption] $WorkLanguageId
    )

    switch ($WorkLanguageId) {
        ([LanguageOption]::ENU) { return $Line.Substring(0, $Line.IndexOf('A1033') - 1) }
        ([LanguageOption]::DEU) { return $Line.Substring(0, $Line.IndexOf('A1031') - 1) }
    }

}

function Export-LanguageFiles {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [LanguageOption] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [LanguageOption] $WorkLanguageId
    )
    $MissingTranslationsFile = GetMissingTranslationsFile -File $File -LanguageId $WorkLanguageId
    $BaseLanguageFile = GetLanguageFile -File $File -LanguageId $BaseLanguageId
    $WorkLanguageFile = GetLanguageFile -File $File -LanguageId $WorkLanguageId

    return (New-Object psobject -ArgumentList @{ BaseLanguageFile = $BaseLanguageFile; WorkLanguageFile = $WorkLanguageFile; MissingTranslationsFile = $MissingTranslationsFile })
}

function Remove-TrenslationFiles {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [PSCustomObject] $TranslationFiles
    )
    Remove-Item -Path $TranslationFiles.MissingTranslationsFile -Force
    Remove-Item -Path $TranslationFiles.BaseLanguageFile -Force
    Remove-Item -Path $TranslationFiles.WorkLanguageFile -Force
}

function GetLanguageFile {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [LanguageOption] $LanguageId
    )
    $LanguageFile = MakeFileName -File $File -LanguageId $LanguageId
    Export-NAVApplicationObjectLanguage -Source $File.FullName -Destination $LanguageFile -LanguageId $LanguageId -Encoding UTF8 -Force
    Remove-EmptyLinesFromFile -Path $LanguageFile
    return $LanguageFile
}

function GetMissingTranslationsFile {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [LanguageOption] $LanguageId
    )
    $MissingFileName = MakeFileName -File $File -LanguageId $LanguageId -Missing
    Test-NAVApplicationObjectLanguage -Source $File.FullName -LanguageId $LanguageId -PassThru -WarningAction SilentlyContinue | Sort-Object ObjectType, Id | ForEach-Object {
        Add-Content -Value $($_.TranslateLines) -Path $MissingFileName -Force
    }
    return $MissingFileName
}

function FileHaveMissingTranslation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $FilePath,

        [Parameter(mandatory = $true)]
        [LanguageOption] $LanguageId
    )
    $TestResult = Test-NAVApplicationObjectLanguage -Source $FilePath -LanguageId $LanguageId -PassThru -WarningAction SilentlyContinue
    return $TestResult.TranslateLines.Count -gt 0
}

function MakeFileName {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [LanguageOption] $LanguageId,

        [Parameter(mandatory = $false)]
        [switch] $Missing
    )
    if ($Missing) { $MissingText = '_MISSING' }
    return (Join-Path -Path $File.DirectoryName -ChildPath ($File.BaseName + '_' + $LanguageId + $MissingText + '.TXT'))
}

function GetUserConfirmation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Text
    )
    Write-Host "$Text, (y/n)?" -NoNewline
    $Readkey = [console]::ReadKey()
    return $Readkey.Key -in "Y", "YES", "Enter"
}

function MakeSetup {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [LanguageOption] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [LanguageOption] $WorkLanguageId
    )
    $Property = @{
        BaseLanguageId = $BaseLanguageId
        WorkLanguageId = $WorkLanguageId
        DictionaryPath = "$PSScriptRoot\.dictionary\{0}_{1}.csv" -f $BaseLanguageId, $WorkLanguageId
        DictionaryName = "{0}_{1}.csv" -f $BaseLanguageId, $WorkLanguageId
    }
    return New-Object pscustomobject -Property $Property
}

function GetDictionary {
    param (
        [Parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup
    )

    $Dict = @{}
    if (Test-Path -Path $LanguageSetup.DictionaryPath -PathType Leaf) {
        Import-Csv -Path $LanguageSetup.DictionaryPath | ForEach-Object { $Dict.Add($_.Key, $_.Value) }
        Write-Host "$($LanguageSetup.DictionaryName) loaded with $($Dict.Count) lines" -ForegroundColor Cyan
    } else {
        Write-Host "New dictionary initialized" -ForegroundColor Cyan
    }
    $LanguageSetup | Add-Member -MemberType NoteProperty -Name DictionaryLines -Value $Dict.Count -Force
    return $Dict
}

function SaveDictionary {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup,

        [Parameter(mandatory = $true)]
        [hashtable] $Dict
    )

    if ($LanguageSetup.DictionaryLines -ne $Dict.Count) {
        $Dict.GetEnumerator() | Select-Object Key, Value | Export-Csv -Path $LanguageSetup.DictionaryPath -Encoding utf8 -Force
        Write-Host "Dictionary has been updated by $($Dict.Count - $LanguageSetup.DictionaryLines) new lines" -ForegroundColor Cyan
    } else {
        Write-Host "Dictionary has not been changed." -ForegroundColor DarkGray
    }
}
