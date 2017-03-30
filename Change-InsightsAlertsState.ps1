<#
.SYNOPSIS
	This Azure Automation runbook enables or disables Application Insights alerts from resource group.
	
	You can use this runbook to enable or disable alerts in 'microsoft.insights/alertrules' namespace. Script has been tested in two scenarios:
	* Enable / Disable Application Insights web tests 
	* Enable / Disable SQL Database alert rules
	
	This runbooks needs AzureRunAsConnection.
	
.PARAMETER AlertNames
	Comma separated list of alert names (microsoft.insights/alertrules) to be enabled or disabled. For example: "High DTU usage in database1, High DTU usage in database2"
	
.PARAMETER Action
	Application Insights alerts with given alert names will be enabled in resource group when set to 'Enable'.
	Application Insights alerts with given alert names will be disabled in resource group when set to 'Disable'.
			
.PARAMETER ResourceGroupName
	Name of the Resource Group

.OUTPUTS
	Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.
#>

Param( 
	[Parameter (Mandatory= $true)] 
	[string]$AlertNames,

	[Parameter (Mandatory = $true)] 
	[ValidateSet("Enable","Disable")]
	[string]$Action  = "Enable", 

	[Parameter (Mandatory= $true)] 
	[string]$ResourceGroupName
)

$ErrorActionPreference = 'stop'

function Login() {
	$connectionName = "AzureRunAsConnection"
	try
	{
		$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

		Write-Verbose "Logging in to Azure..." -Verbose

		Add-AzureRmAccount `
			-ServicePrincipal `
			-TenantId $servicePrincipalConnection.TenantId `
			-ApplicationId $servicePrincipalConnection.ApplicationId `
			-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null
	}
	catch {
		if (!$servicePrincipalConnection)
		{
			$ErrorMessage = "Connection $connectionName not found."
			throw $ErrorMessage
		} else{
			Write-Error -Message $_.Exception
			throw $_.Exception
		}
	}
}

function Set-IsEnabledProperty($Alert, [bool]$value) {
	if ([bool]($Alert.Properties.PSobject.Properties.name -match "isEnabled")) {
		$Alert.Properties.isEnabled = $value
	} else {
		# isEnabled property is deleted when you disable alertrule
		# Need to recreate property
		$Alert.Properties | Add-Member @{isEnabled=$value} -PassThru | Out-Null
	}
}

Login

Write-Verbose ("Searching for alerts '$AlertNames' from resource group '$ResourceGroupName'..") -Verbose

$Alerts = Find-AzureRmResource -ResourceType "microsoft.insights/alertrules" -ResourceGroupNameContains $ResourceGroupName -ExpandProperties | Where-Object {$AlertNames.Split(",").Trim() -contains $_.Name}

Write-Verbose ("Found '" + @($Alerts).Count + "' alert rules") -Verbose

foreach ($Alert in ($Alerts)) {
		$AlertName = $Alert.Name
		If ($Action -eq "Enable") 
		{
			Write-Output "Enabling alert with the name '$AlertName'"
			Set-IsEnabledProperty -Alert $Alert -value $true
		}
		ElseIf ($Action -eq "Disable") 
		{
			Write-Output "Disabling alert with the name: $AlertName'"
			Set-IsEnabledProperty -Alert $Alert -value $false
		}
		Else 
		{
			throw "Unexpected action '$Action' given. Please give 'Enable' or 'Disable' to parameter 'Action'"
		}
		
		$Alert | Set-AzureRmResource -Force | Out-Null
}

Write-Verbose "All done!" -Verbose
