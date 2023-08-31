# NavTranslator for Microsoft Dynamics NAV object files

## Description

The process is performed semi-automatically. You provide three parameters:
  - `Path` pointing to the folder where the objects for translation are located.
  - `BaseLanguageId` as a base language which will be used for making translations from.
  - `WorkLanguageId` as a language which will be checked and updated.

The function will find all the objects recursively within the Path. For an every NAV object file you will be shown an existing "base" string value and asked to enter a translation for it, if needed. You can type or paste translated value and confirm it. Your translation will be added to the dictionary and will be reused to translate the same "base" strings when found. Finally, your translations will be imported to Dynamics NAV object file. Each Dynamics NAV file is processed individually.

### Preconditions

1. Dynamics NAV is installed with Development Shell option (**NavModelTools.ps1** is used)
2. Dynamics NAV objects are extracted and converted to UTF8 (recommended to make a backup first)
5. Make sure your objects contain Base language captions. They would be the base for translation. If they are not exists, they will be added automatically assuming that ENU is a base DevelopmentLanguage ([read more info here](https://learn.microsoft.com/en-us/powershell/module/microsoft.dynamics.nav.model.tools/export-navapplicationobjectlanguage?view=dynamicsnav-ps-2018#-developmentlanguageid)).

### Setup and Usage

1. Clone this repository
2. Open PowerShell and CD into the cloned folder
3. Make sure **LanguageOption.psm1** contains the languages you may need for translation process (both base and work)
4. Make sure path to **NavModelTools.ps1** is correct in **NavTranslator.psm1** (configured for Dynamics NAV 2018 version by default)
5. Run `Import-Module .\NavTranslator.psm1 -DisableNameChecking -Force`
6. Run `Start-TranslationProcess` with your parameters

### Dictionary

* After you finish translating, a new dictionary will be created within the `.\.dictionary\<BaseLanguageId>_<WorkLanguageId>.csv` path.
* If you translate some another objects using the same language settings, the same dictionary will be used once again and updated by your new inputs.
* Translation for known strings will be done automatically based on dictionary file contents.

### **Important Notes**

- **Expected encoding is UTF8: for NAV objects, translations and dictionary.**
- **Objects within the -Path will be updated without prior user confirmation. Consider to make backup first.**

## Contribution and feedback

Suggestions and ideas are highly welcomed and appreciated. Just open a new Pull Request or an Issue.

You can [buy be a coffee](https://www.buymeacoffee.com/vkozlov) as well.

***
#### Legal Notice: Microsoft Dynamics NAV (or Dynamics NAV) is a registered trademark by Microsoft Corporation or Microsoft group of companies.
