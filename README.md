Useful Azure Automation Runbooks to maintain Azure services

* Start & Shutdown Azure Cloud Services
* Backup SQL Database to blob storage (to support offsite backups)
* Enable & disable Application Insights web tests
* Enable & disable Application Insights alert rules

If running in Azure automation account
* Update Powershell modules to latest version before running scripts

See more information from https://github.com/azureautomation/runbooks/blob/master/Utility/ARM/Update-ModulesInAutomationToLatestVersion.ps1
See more information about Azure Automation: https://docs.microsoft.com/en-us/azure/automation/

If running locally
* Remove login part from the script
* Run Login-AzureRmAccount to login you Azure subscription if script is using AzureRunAsConnection 
* Run Add-AzureAccount to login you Azure subscription if script is using AzureClassicRunAsConnection

You need Azure Powershell cmdlets when running scripts locally. See more information from https://docs.microsoft.com/en-us/powershell/azureps-cmdlets-docs/