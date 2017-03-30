<#
.SYNOPSIS
	This Azure Automation runbook enables or disables all Application Insights web tests from resource group.
	
	This runbooks needs AzureRunAsConnection.

.PARAMETER Action
	When set to 'Enable' all Application Insights web tests will be enabled in resource group.
	When set to 'Disable' all Application Insights web tests will be disabled in resource group.
			
.PARAMETER ResourceGroupName
	Name of the Resource Group

.OUTPUTS
	Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.
#>

Param( 
	[Parameter (Mandatory = $true)] 
	[ValidateSet("Enable","Disable")]
	[string]$Action  = "Enable", 

	[Parameter (Mandatory= $true)] 
	[string]$ResourceGroupName
)

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

Login

Write-Verbose "Searching for web tests from resource group '$ResourceGroupName'.." -Verbose

$Webtests = Find-AzureRmResource -ResourceType "microsoft.insights/webtests" -ResourceGroupNameContains $ResourceGroupName -ExpandProperties
Write-Verbose ("Found '" + $Webtests.Count + "' web tests") -Verbose

foreach ($Webtest in ($Webtests)) {
		$WebtestName = $Webtest.Name
		If ($Action -eq "Enable") 
		{
			Write-Output "Enabling web test with the name '$WebtestName'"
			$Webtest.Properties.Enabled = $true

		}
		ElseIf ($Action -eq "Disable") 
		{
			Write-Output "Disabling web test with the name: $WebtestName'"
			$Webtest.Properties.Enabled = $false
		}
		Else 
		{
			throw "Unexpected action '$Action' given. Please give 'Enable' or 'Disable' to parameter 'Action'"
		}
		
		$Webtest | Set-AzureRmResource -Force | Out-Null
}

Write-Verbose "All done!" -Verbose
