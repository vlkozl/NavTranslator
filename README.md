# NavTranslator for Microsoft Dynamics NAV object files

## 📖 Description
The PowerShell module works as addition to **Dynamics NAV Development Shell** commands and helps translating Dynamics NAV objects in a convenient and automated manner. It works from PowerShell console and provides an efficient interface interaction for a user. Featuring own csv-file dictionary and online translation with DeepL, translation to Dynamics NAV objects has never been easier.

## 🔎 How it works 
The process is performed semi-automatically. You provide three parameters:
  - `Path` pointing to the folder where the objects for translation are located.
  - `BaseLanguageId` as a language id which will be used for making translations from.
  - `WorkLanguageId` as a language id which will be checked and updated.

Where every *LanguageId is the integer number representing Windows Language Code.

Read more here: [https://www.venea.net/web/culture_code](https://www.venea.net/web/culture_code).  
To get list of Windows languages run in PowerShell:

```[PowerShell]
Get-Culture -ListAvailable | Select-Object LCID, Name, DisplayName, ThreeLetterWindowsLanguageName, ThreeLetterISOLanguageName, TwoLetterISOLanguageName | Out-GridView
```

The script finds all the **Dynamics NAV** TXT format objects recursively within the given Path. Every object will be tested for missing translations based on the settings provided. In case of missing translations you will be shown an existing translation and asked to enter a translation manually if **DeepL** is not selected to use. If you selected to use **DeepL**, the script will ask **DeepL** API for translation first.

You will be asked to confirm every new translation. You can edit it or keep the original value.

Finally, all missing translations will be imported to the object file.
Every file is processed separately, so you can stop the process at any time.

### 📗 Dictionary
A simple CSV file dictionary is used to store, reuse and add new translations in the `.\.dictionary\` folder. The dictionary is created automatically when it is not found and will be filled with all confirmed translations and saved. During the process, the dictionary will be checked for an every translation. Existing dictionaries will be reused for all the next translations with the same language settings.

### 🈸 DeepL
DeepL is a translation web service which provides a free REST API ([https://www.deepl.com/pro-api](https://www.deepl.com/pro-api)). To use it, you need to acquire an API key. When you start translating, if confirmed, API key will be checked automatically from `.\.deepl\apikey.xml` path. If key is not found, you will be asked to enter it. The API key will be stored in the encrypted file format that is only possible to read by the current user on the current machine.  

Read more here:
* [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-clixml?view=powershell-7.3](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-clixml?view=powershell-7.3)
* [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-7.3](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-7.3)

## 💬 Usage

### 🔑 Preconditions

1. At least PowerShell 6.2 is installed.
2. Dynamics NAV is installed with Development Shell option.
3. Dynamics NAV objects are exported.
4. (Optional) Make sure Dynamics NAV objects contain the Base language names or captions as they would be the base for translation. If they do not exists, they will be added automatically assuming that ENU is a base DevelopmentLanguageId ([read more info here](https://learn.microsoft.com/en-us/powershell/module/microsoft.dynamics.nav.model.tools/export-navapplicationobjectlanguage?view=dynamicsnav-ps-2018#-developmentlanguageid)).

### 🛠 Setup & Run

1. Clone this repository (if you have Git) or download ZIP and unpack.
2. Open PowerShell and CD into the cloned folder.
3. Depending on your Dynamics NAV version, check path to `Microsoft.Dynamics.Nav.Model.Tools` is correct in `NavTranslator.psm1` (configured for Dynamics NAV 2018 version by default).
4. Run `Import-Module .\NavTranslator.psm1 -DisableNameChecking -Force`
5. Run `Start-TranslationProcess` with your parameters

----
###  ⚠ Important Notes
- ❗ Expected encoding is UTF8: for NAV objects, translations and dictionary.
- ❗ Dynamics NAV objects within the -Path will be updated without prior user confirmation. Consider to make backup first.
----
### 💡 Example

Stan is a Dynamics NAV developer who wants to translate NAV objects from English to German on his machine. He has a Dynamics NAV database with English (ENU) as a base language and a DeepL account.

- NAV objects have been exported to "Path" folder
- NAV objects are in UTF8 encoding
- ENU Language layer is existing in NAV objects and/or expected as base DevelopmentLanguageId.

Stan opens PowerShell and runs the following commands:

```[PowerShell]
> cd C:\Temp\NavTranslator\

> Import-Module NavTranslator.psm1 -DisableNameChecking -Force

> Start-TranslationProcess -Path .\Objects -BaseLanguageId 1033 -WorkLanguageId 1031
```

Results:
- The script has found all the objects and helped Stan with translation.
- Files within the Path were updated.
- DeepL API key was created `.\.deepl\ApiKey.xml`.
- Dictionary was created `.\.dictionary\ENU_DEU.csv`.
- Dictionary was automatically reused for the same translations and saved.

## 🍀 Contribution and feedback

Suggestions and ideas are highly welcomed and appreciated.
Feel free to open a new discussion, Issue, or Pull Request.

You can also ☕ [buy be a coffee](https://www.buymeacoffee.com/vkozlov) to say ❤ thanks. 

***
### 📢 Legal Notice
* Licensed under the [MIT](https://github.com/vlkozl/NavTranslator/blob/main/LICENSE) license.
* Microsoft Dynamics NAV (or Dynamics NAV) is a registered trademark by Microsoft Corporation or Microsoft group of companies.
* DeepL is a registered trademark of DeepL SE, Maarweg 165, 50825 Cologne, Germany
