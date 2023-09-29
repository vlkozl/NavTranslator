# Change Log

### v1.2 (29.09.2023)
 - Dictionary has now higher priority than DevelopmentLanguageId
 - Dictionary is now alfabetically sorted using [System.Collections.Specialized.OrderedDictionary]
 - Added [B]reak option to ExtendedStringConfirmation
 - Added progress indicator; files without changes are not reported to the console
 - Fixed bug when saving DeepL credentials; .deepl folder created if not exists
 - Fixed bug when saving dictionary; .dictionary folder created if not exists
 - Added .gitignore with /.deepl and /.dictionary folders
 - Other minor changes

### v1.1 (06.09.2023)
 - Adding Manifest to give more information about the module
 - Importing depenency module Microsoft.Dynamics.Nav.Model.Tools directly
 - Change LanguageId from String to Integer (as of Windows LCID) for better clarity and extensibility
 - Removing LanguageOption.psm1 file as no need to store language options any more
 - DeepL API usage implementation
 - DeepL API key storage implementation
 - Updated Help and README
 - Rename functions to use approved verbs
 - Code refactoring and optimizations

### v1.0 (30.08.2023)
 - Core module created with GitHub repository
