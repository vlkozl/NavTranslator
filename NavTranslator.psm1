Import-Module "${env:ProgramFiles(x86)}\Microsoft Dynamics NAV\*\RoleTailored Client\Microsoft.Dynamics.Nav.Model.Tools.psd1" -DisableNameChecking -Force -NoClobber -WarningAction SilentlyContinue | Out-Null

$Error.clear()

<#
.SYNOPSIS
    Starts the translation update process, using Base- and Work- language id parameters.

.DESCRIPTION
    The process is performed semi-automatically. You provide three parameters:
        -Path, pointing to the folder where the objects for translation are located.
        -BaseLanguageId, as a language id which will be used for making translations from.
        -WorkLanguageId, as a language id which will be checked and updated.

    Every LanguageId is an integer number representing Windows Language Code.
    See more here: https://www.venea.net/web/culture_code

    To get your available languages, run in PowerShell (at least v6.2):
    Get-Culture -ListAvailable | select LCID,Name,DisplayName,ThreeLetterWindowsLanguageName,ThreeLetterISOLanguageName,TwoLetterISOLanguageName | Out-GridView

    The script will find all the Dynamics NAV TXT format objects recursively within the Path. Every
    object will be tested for missing translations based on the settings provided. In case of missing
    translations you will be shown an existing translation and asked to enter a translation if DeepL
    is not selected to use. If you selected to use DeepL, the script will ask DeepL API for a
    translation first.

    You will be asked to confirm translation, where you can edit it or to keep the original value.

    Finally, all missing translations will be imported to the object file.
    Every file is processed separately, so you can stop the process at any time.

    Dictionary
    A simple CSV file dictionary is used to store and reuse translations. The dictionary is saved in the
    ".\.dictionary\" folder. The dictionary is created automatically when it is not found. The dictionary
    will be filled with all confirmed translations and saved to the same path. During translation process,
    the dictionary will be checked for existing translations.
    Existing dictionaries will be reused for all translations with the same language settings.

    DeepL
    DeepL is a translation web service which provides a free REST API. See more: https://www.deepl.com/pro-api
    To use it, you need to acquire an API key. When you start translating, if confirmed, API key will be
    checked automatically from ".\.deepl\apikey.xml" path. If key is not found, you will be asked to enter it.
    The API key will be stored in the encrypted file format that is only possible to read by the current user
    on the current machine. Read more here:
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-clixml?view=powershell-7.3
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-7.3

    IMPORTANT: Expected encoding for all files is UTF8. This applies to NAV objects, translations, dictionary.

    .EXAMPLE
    Stan wants to translate NAV objects from English to German. He has a NAV database with English as a base language.
    Prerequisites:
        - NAV objects has been exported to "Path" folder
        - NAV objects are in UTF8 encoding
        - ENU Language layer is existing in NAV objects and/or expected as base DevelopmentLanguageId.

    Stan runs the following command:
    > Start-TranslationProcess -Path .\Objects -BaseLanguageId 1033 -WorkLanguageId 1031

    Result:
        - The script will find all the objects recursively and will help automate translation process.
        - Files within the Path will be updated.
        - Translations dictionary will be created in ".\.dictionary\ENU_DEU.csv"
        - Dictionary will be automatically reused for any further translations given the same Base and Work language ids.
        - DeepL API key will be created under ".\.deepl\apikey.xml"

.PARAMETER Path
    Path to the folder where NAV TXT objects are located.

.PARAMETER BaseLanguageId
    Language Id which will be used as a base for translations. Windows LCID.

.PARAMETER WorkLanguageId
    Language Id which will be checked. Windows LCID.
#>
function Start-TranslationProcess {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Path,

        [Parameter(mandatory = $true)]
        [ushort] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [ushort] $WorkLanguageId
    )

    begin {
        if ($BaseLanguageId -eq $WorkLanguageId) {
            throw "BaseLanguageId and WorkLanguageId cannot be the same"
        }

        $UseDeepL = Get-UserConfirmation -Text "Use DeepL translations"
        if ($UseDeepL) {
            Initialize-DeeplCredentials
        } else {
            Write-Host "DeepL translation service will not be used" -ForegroundColor DarkGray
        }

        $LanguageSetup = Initialize-LanguageSetup -BaseLanguageId $BaseLanguageId -WorkLanguageId $WorkLanguageId
        $LanguageSetup | Add-Member -MemberType NoteProperty -Name UseDeepL -Value $UseDeepL
        $Dict = Get-Dictionary -LanguageSetup $LanguageSetup
        $ObjectFiles = Get-ChildItem $Path -File -Recurse -Exclude '*_*' -Filter '*.txt'

        Write-Host "Total files found: " -NoNewline -ForegroundColor Cyan
        Write-Host $($ObjectFiles.Count) -ForegroundColor Yellow
        if (!(Get-UserConfirmation -Text "Ready to start")) {
            break
        }
        Write-Host
    }

    process {
        $Index = 0
        $FilesUpdated = 0
        $TotalFiles = $ObjectFiles.Count
        $ActivityText = "Translating Files"
        foreach ($File in $ObjectFiles) {
            $Index += 1
            $Progress = [Math]::Round(($Index / $TotalFiles) * 100)
            Write-Progress -Activity $ActivityText -Status "$($File.Name) ($Index of $TotalFiles)" -PercentComplete $Progress

            if (Test-FileHaveMissingTranslation -FilePath $File.FullName -LanguageId $WorkLanguageId) {
            Write-Host "============================================" -ForegroundColor Cyan
            Write-Host "File: $($File.Name)" -ForegroundColor White
            }
            else {
                continue
            }

            $TranslationFiles = Export-LanguageFiles -File $File -BaseLanguageId $LanguageSetup.BaseLanguageId -WorkLanguageId $LanguageSetup.WorkLanguageId
            $MissingTranslationsFileContent = Get-Content -Path $TranslationFiles.MissingTranslationsFile -Encoding utf8
            Write-Host "Missing translations: $($MissingTranslationsFileContent.Count)"

            foreach ($Line in $MissingTranslationsFileContent) {
                Update-TranslationLine -Line $Line -LanguageSetup $LanguageSetup -TranslationFiles $TranslationFiles -Dict $Dict
            }

            $FilesUpdated += 1
            Import-TranslationToFile -FilePath $File.FullName -LanguagePath $TranslationFiles.WorkLanguageFile -LanguageId $LanguageSetup.WorkLanguageId
            Remove-TranslationFiles -TranslationFiles $TranslationFiles
            Write-Host
            Write-Host "$($File.Name) updated" -ForegroundColor White
        }
    }
    end {
        Write-Progress -Activity $ActivityText -Status "Ready" -Completed
        Write-Host "Total files updated: $FilesUpdated" -ForegroundColor Cyan
        Save-Dictionary -LanguageSetup $LanguageSetup -Dict $Dict
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
        [System.Collections.Specialized.OrderedDictionary] $Dict
    )
    $Pattern = Get-SubstringByPattern -Line $Line -WorkLanguageId $LanguageSetup.WorkLanguageId
    $BaseLanguageString = Read-LanguageString -LanguageFile $TranslationFiles.BaseLanguageFile -Pattern $Pattern
    $WorkLanguageString = Read-LanguageString -LanguageFile $TranslationFiles.WorkLanguageFile -Pattern $Pattern

    # Skip translating when base language string is empty
    if ([string]::IsNullOrEmpty($BaseLanguageString)) {
        return
    }

    Write-Host
    Write-Host "Pattern: $Pattern" -ForegroundColor DarkGray
    Show-StringWithComment -LanguageName $LanguageSetup.BaseLanguageName -String $BaseLanguageString -Comment ''

    $DictValue = $Dict[$BaseLanguageString]

    # Dictionary value found
    if (!([string]::IsNullOrEmpty($DictValue))) {
        $WorkLanguageString = $DictValue
        Show-StringWithComment -LanguageName $LanguageSetup.WorkLanguageName -String $WorkLanguageString -Comment 'copied from dictionary'
    }
    # Dictionary value not found
    else {
        # DevelopmentLanguageId is suggested
        if (!([string]::IsNullOrEmpty($WorkLanguageString))) {
            Show-StringWithComment -LanguageName $LanguageSetup.WorkLanguageName -String $WorkLanguageString -Comment 'suggested as DevelopmentLanguageId'
            Write-Host "Use this translation?"
            $WorkLanguageString = Get-ExtendedStringConfirmation -OriginalString $BaseLanguageString -NewString $WorkLanguageString -LanguageName $LanguageSetup.WorkLanguageName
            if ([string]::IsNullOrEmpty($DictValue)) {
                $Dict.Add($BaseLanguageString, $WorkLanguageString)
            }
        }
        else {
            # Ask DeepL
            if ($LanguageSetup.UseDeepL) {
                $WorkLanguageString = Get-DeeplTranslation -String $BaseLanguageString -LanguageSetup $LanguageSetup
            }

            # Ask User when DeepL failed
            if ([string]::IsNullOrEmpty($WorkLanguageString)) {
                # Ask User when DeepL failed
                $BaseLanguageString | Set-Clipboard
                $WorkLanguageString = Get-UserTranslation -LanguageName $LanguageSetup.WorkLanguageName
            }
            $Dict.Add($BaseLanguageString, $WorkLanguageString)
        }
    }
    Save-LanguageString -LanguageFile $TranslationFiles.WorkLanguageFile -Pattern $Pattern -NewValue $WorkLanguageString
}

function Show-StringWithComment {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $LanguageName,

        [Parameter(mandatory = $true)]
        [string] $String,

        [Parameter(mandatory = $false)]
        [string] $Comment,

        [Parameter(mandatory = $false)]
        [switch] $NewLine
    )
    if ($NewLine) {
        Write-Host
    }
    Write-Host "$LanguageName : " -NoNewline
    Write-Host $String -ForegroundColor Yellow
    if (![string]::IsNullOrEmpty($Comment)) {
        Write-Host "($Comment)" -ForegroundColor DarkGray
    }
}

function Import-TranslationToFile {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $FilePath,

        [Parameter(mandatory = $true)]
        [string] $LanguagePath,

        [Parameter(mandatory = $true)]
        [ushort] $LanguageId
    )
    $Params = @{
        Source       = $FilePath
        Destination  = $FilePath
        LanguagePath = $LanguagePath
        LanguageId   = $LanguageId
        Encoding     = 'UTF8'
        Force        = $true
    }
    try {
        Import-NAVApplicationObjectLanguage @Params
    } catch {
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        throw $_
    }
}

function Read-LanguageString {
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

function Save-LanguageString {
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

function Get-SubstringByPattern {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Line,

        [Parameter(mandatory = $true)]
        [ushort] $WorkLanguageId
    )
    return $Line.Substring(0, $Line.IndexOf($WorkLanguageId.ToString()) - 2)
}

function Export-LanguageFiles {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [ushort] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [ushort] $WorkLanguageId
    )
    $MissingTranslationsFile = Export-MissingTranslationsFile -File $File -LanguageId $WorkLanguageId
    $BaseLanguageFile = Export-LanguageFileWithFix -File $File -LanguageId $BaseLanguageId
    $WorkLanguageFile = Export-LanguageFileWithFix -File $File -LanguageId $WorkLanguageId

    return (New-Object pscustomobject -ArgumentList @{ BaseLanguageFile = $BaseLanguageFile; WorkLanguageFile = $WorkLanguageFile; MissingTranslationsFile = $MissingTranslationsFile })
}

function Export-LanguageFileWithFix {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [ushort] $LanguageId
    )
    $LanguageFile = New-FilePath -File $File -LanguageId $LanguageId
    Export-NAVApplicationObjectLanguage -Source $File.FullName -Destination $LanguageFile -LanguageId $LanguageId -Encoding UTF8 -Force
    Remove-EmptyLinesFromFile -Path $LanguageFile
    return $LanguageFile
}

<#
.SYNOPSIS
    Removes empty lines from a file and overwrites it.
    Empty lines appear as a bug of Export-NAVApplicationObjectLanguage cmdled.
#>
function Remove-EmptyLinesFromFile {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $Path
    )
    $FileContent = Get-Content -Path $Path -Encoding utf8
    $FileContent | Where-Object { $_ -ne '' } | Set-Content -Path $Path -Encoding utf8
}

function Remove-TranslationFiles {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [PSCustomObject] $TranslationFiles
    )
    Remove-Item -Path $TranslationFiles.MissingTranslationsFile -Force
    Remove-Item -Path $TranslationFiles.BaseLanguageFile -Force
    Remove-Item -Path $TranslationFiles.WorkLanguageFile -Force
}

function Export-MissingTranslationsFile {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [ushort] $LanguageId
    )
    $MissingFileName = New-FilePath -File $File -LanguageId $LanguageId -Missing
    Test-NAVApplicationObjectLanguage -Source $File.FullName -LanguageId $LanguageId -PassThru -WarningAction SilentlyContinue | ForEach-Object {
        Add-Content -Value $($_.TranslateLines) -Path $MissingFileName -Force
    }
    return $MissingFileName
}

function Test-FileHaveMissingTranslation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $FilePath,

        [Parameter(mandatory = $true)]
        [ushort] $LanguageId
    )
    $TestResult = Test-NAVApplicationObjectLanguage -Source $FilePath -LanguageId $LanguageId -PassThru -WarningAction SilentlyContinue
    return $TestResult.TranslateLines.Count -gt 0
}

function New-FilePath {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(mandatory = $true)]
        [ushort] $LanguageId,

        [Parameter(mandatory = $false)]
        [switch] $Missing
    )
    if ($Missing) { $MissingText = '_MISSING' }
    return (Join-Path -Path $File.DirectoryName -ChildPath ($File.BaseName + '_' + $LanguageId.ToString() + $MissingText + '.TXT'))
}

function Initialize-LanguageSetup {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [ushort] $BaseLanguageId,

        [Parameter(mandatory = $true)]
        [ushort] $WorkLanguageId
    )
    $AllCultures = Get-Culture -ListAvailable
    $BaseLanguage = $AllCultures | Where-Object LCID -EQ $BaseLanguageId
    $WorkLanguage = $AllCultures | Where-Object LCID -EQ $WorkLanguageId

    if ([string]::IsNullOrEmpty($BaseLanguage)) {
        throw "BaseLanguageId $BaseLanguageId is not found in the list of available cultures.`nUse Get-Culture -ListAvailable to see the list of available cultures"
    }
    if ([string]::IsNullOrEmpty($WorkLanguage)) {
        throw "WorkLanguageId $WorkLanguageId is not found in the list of available cultures.`nUse Get-Culture -ListAvailable to see the list of available cultures"
    }

    Write-Host "Language settings identified" -ForegroundColor Cyan
    Write-Host "BaseLanguage: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($BaseLanguage.ThreeLetterWindowsLanguageName) - $($BaseLanguage.DisplayName)" -ForegroundColor Yellow
    Write-Host "WorkLanguage: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($WorkLanguage.ThreeLetterWindowsLanguageName) - $($WorkLanguage.DisplayName)" -ForegroundColor Yellow

    $BaseLanguageName = $BaseLanguage.ThreeLetterWindowsLanguageName.ToUpper()
    $WorkLanguageName = $WorkLanguage.ThreeLetterWindowsLanguageName.ToUpper()

    $Property = [ordered]@{
        BaseLanguageId      = $BaseLanguageId
        WorkLanguageId      = $WorkLanguageId

        BaseLanguageName    = $BaseLanguageName
        WorkLanguageName    = $WorkLanguageName
        WorkLanguageISOCode = $WorkLanguage.TwoLetterISOLanguageName

        DictionatyPath      = "$PSScriptRoot\.dictionary\{0}_{1}.csv" -f $BaseLanguageName, $WorkLanguageName
        DictionaryName      = "{0}_{1}.csv" -f $BaseLanguageName, $WorkLanguageName
    }
    return New-Object pscustomobject -Property $Property
}

function Get-Dictionary {
    param (
        [Parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup
    )

    $Dict = [ordered]@{}
    if (Test-Path -Path $LanguageSetup.DictionatyPath -PathType Leaf) {
        Import-Csv -Path $LanguageSetup.DictionatyPath | ForEach-Object { $Dict.Add($_.Key, $_.Value) }
        Write-Host "Dictionary " -NoNewline -ForegroundColor Cyan
        Write-Host $($LanguageSetup.DictionaryName) -NoNewline -ForegroundColor Yellow
        Write-Host " with " -NoNewline -ForegroundColor Cyan
        Write-Host $($Dict.Count) -ForegroundColor Yellow -NoNewline
        Write-Host " lines found" -ForegroundColor Cyan
    } else {
        Write-Host "New dictionary initialized" -ForegroundColor Cyan
    }
    $LanguageSetup | Add-Member -MemberType NoteProperty -Name DictionaryLines -Value $Dict.Count -Force
    return $Dict
}

function Save-Dictionary {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup,

        [Parameter(mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary] $Dict
    )

    if ($LanguageSetup.DictionaryLines -ne $Dict.Count) {
        $Dict.GetEnumerator() | Select-Object Key, Value | Sort-Object -Property 'Key' | Export-Csv -Path $LanguageSetup.DictionatyPath -Encoding utf8 -Force
        Write-Host "Dictionary has been updated by $($Dict.Count - $LanguageSetup.DictionaryLines) new lines" -ForegroundColor Cyan
    } else {
        Write-Host "Dictionary has not been changed" -ForegroundColor DarkGray
    }
}

function Get-UserTranslation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $LanguageName
    )
    $Result = ''
    $Confirmed = $false
    while (!$Confirmed) {
        if (([System.Console]::GetCursorPosition()).Item1 -ne 0) {
            Write-Host
        }
        $Result = Read-Host -Prompt "Enter $LanguageName string"
        if (![string]::IsNullOrEmpty($Result)) {
            Show-StringWithComment -LanguageName $LanguageName -String $Result -Comment ''
            $Confirmed = Get-UserConfirmation
        }
    }
    return $Result
}

function Initialize-DeeplCredentials {
    [CmdletBinding()]
    param()

    if (Test-Path -Path "$PSScriptRoot\.deepl\ApiKey.xml" -PathType Leaf) {
        Write-Host "DeepL API key found" -ForegroundColor DarkGray
    } else {
        Write-Host "DeepL API key not found" -ForegroundColor Yellow
        $DeeplCred = Get-Credential -Message "Enter DeepL API key (without DeepL-Auth-Key prefix)" -UserName 'DeepL'
        $DeeplCred | Export-Clixml -Path "$PSScriptRoot\.deepl\ApiKey.xml" -Force
        Write-Host "DeepL API key saved" -ForegroundColor DarkGray
    }
}

function Get-DeeplTranslation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $String,

        [parameter(mandatory = $true)]
        [pscustomobject] $LanguageSetup
    )

    $Result = Invoke-DeepLApiCall -String $String -LanguageISOCode $LanguageSetup.WorkLanguageISOCode
    if ([string]::IsNullOrEmpty($Result)) {
        return ''
    }
    Show-StringWithComment -LanguageName $LanguageSetup.WorkLanguageName -String $Result -Comment ''
    $Result = Get-ExtendedStringConfirmation -OriginalString $String -NewString $Result -LanguageName $LanguageSetup.WorkLanguageName
    return $Result
}

function Invoke-DeepLApiCall {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $String,

        [parameter(mandatory = $true)]
        [string] $LanguageISOCode
    )
    begin {
        # Using default way of storing PowerShell credentials. Please override if this does not fits you.
        $ApiKey = (Import-Clixml -Path "$PSScriptRoot\.deepl\ApiKey.xml").GetNetworkCredential().Password
        $header = @{ "Authorization" = ('DeepL-Auth-Key ' + $ApiKey) }
        $body = "text=$String&target_lang=$LanguageISOCode"
        $RequestParams = @{
            Method      = 'Post'
            Uri         = "https://api-free.deepl.com/v2/translate"
            SslProtocol = 'Tls12'
            Headers     = $header
            Body        = $body
        }
    }
    process {
        Write-Host "Requesting DeepL translation " -ForegroundColor DarkGray -NoNewline
        try {
            $Result = (Invoke-RestMethod @RequestParams).translations.text
            Write-Host
            return $Result
        } catch {
            Write-Host "failed" -ForegroundColor DarkRed
            return ''
        }
    }
}

function Get-ExtendedStringConfirmation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $OriginalString,

        [Parameter(mandatory = $true)]
        [string] $NewString,

        [Parameter(mandatory = $true)]
        [string] $LanguageName
    )
    while (!$Confirmed) {
        Write-Host "Select: [A]ccept / [K]eep original / [E]dit / [C]apitalize / [B]reak? " -NoNewline
        $Readkey = [console]::ReadKey()

        switch ($Readkey.Key) {
            "A" {
                $Result = $NewString
                $Confirmed = $true
                break
            }
            "Enter" {
                $Result = $NewString
                $Confirmed = $true
                break
            }
            "K" {
                $Result = $OriginalString
                Show-StringWithComment -LanguageName $LanguageName -String $Result -Comment '' -NewLine
                $Confirmed = $true
                break
            }
            "C" {
                $Result = Get-CapitalizeFirstLetters -String $NewString
                Show-StringWithComment -LanguageName $LanguageName -String $Result -Comment '' -NewLine
                $Confirmed = Get-UserConfirmation
                break
            }
            "E" {
                Write-Host
                $NewString | Set-Clipboard
                $Result = Read-Host -Prompt "Enter $LanguageName string"
                Show-StringWithComment -LanguageName $LanguageName -String $Result -Comment ''
                $Confirmed = Get-UserConfirmation
                break
            }
            "B" {
                throw ""
            }
            default {
                $Result = ''
            }
        }
    }
    Write-Host
    return $Result
}

function Get-CapitalizeFirstLetters {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string] $String
    )
    $CapitalizedString = (Get-Culture).TextInfo.ToTitleCase($String)
    return $CapitalizedString
}

function Get-UserConfirmation {
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $false)]
        [string] $Text = "Looks good"
    )
    $ResponseAccepted = $false
    Write-Host "$Text, [Y]es / [N]o? " -NoNewline
    while (!$ResponseAccepted) {
        $Readkey = [console]::ReadKey()
        Write-Host
        $ResponseAccepted = $Readkey.Key -in "Y", "YES", "N", "NO", "Enter"
    }
    return $Readkey.Key -in "Y", "YES", "Enter"
}

Export-ModuleMember -Function Start-TranslationProcess
