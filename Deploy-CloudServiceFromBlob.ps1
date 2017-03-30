<#
.SYNOPSIS
	This Azure Automation Runbook does Cloud Service (Web & Worker role) deployment from the files found from Storage Account. You must first upload files to Storage Account before running this script.
	
	In addition, script will also enable remote desktop after deployment if parameter is used.
	
	1) Script will login to given storage account and find latest cspkg and cscfg files (determined by LastModified property)
	2) Script will make deployment to Cloud Service using files found from storage account
	3) Script will enable remote desktop to Cloud Service when parameter is used
	
.PARAMETER CloudServiceName
	Name of the Cloud Service to where action is executed

.PARAMETER CloudServiceSlot
	Slot of the Cloud Service to where action is executed
	
.PARAMETER StorageAccountName
	Name of the storage account where container is found
	
.PARAMETER EnableRemoteDesktop
	Remote desktop is enabled after deployment, if set to true

.PARAMETER RemoteDesktopUsername
	Username to remote desktop access. To be used when EnableRemoteDesktop is set to true

.PARAMETER RemoteDesktopPassword
	Password to remote desktop access. To be used when EnableRemoteDesktop is set to true

.PARAMETER ContainerName
	Name of the storage container where Azure Cloud Package (.cspkg) and Azure Service Configuration(.cscfg) are found

.OUTPUTS
	Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.
#>

Param( 
	[Parameter (Mandatory= $true)] 
	[string]$CloudServiceName,
	
	[Parameter (Mandatory = $true)] 
	[ValidateSet("staging","production")]
	[string]$CloudServiceSlot,
	
	[Parameter (Mandatory = $true)] 
	[string]$StorageAccountName,
	
	[Parameter (Mandatory = $true)] 
	[string]$ContainerName,
	
	[Parameter (Mandatory = $true)] 
	[bool]$EnableRemoteDesktop,
	
	[Parameter (Mandatory = $false)] 
	[string]$RemoteDesktopUsername,
	
	[Parameter (Mandatory = $false)] 
	[string]$RemoteDesktopPassword
)

$ErrorActionPreference = 'stop'

function Login() {
	$ConnectionAssetName = "AzureClassicRunAsConnection"

	$connection = Get-AutomationConnection -Name $connectionAssetName        

	Write-Verbose "Get connection asset: $ConnectionAssetName" -Verbose
	$Conn = Get-AutomationConnection -Name $ConnectionAssetName
	if ($Conn -eq $null)
	{
		throw "Could not retrieve connection asset: $ConnectionAssetName. Assure that this asset exists in the Automation account."
	}

	$CertificateAssetName = $Conn.CertificateAssetName
	Write-Verbose "Getting the certificate: $CertificateAssetName" -Verbose
	$AzureCert = Get-AutomationCertificate -Name $CertificateAssetName
	if ($AzureCert -eq $null)
	{
		throw "Could not retrieve certificate asset: $CertificateAssetName. Assure that this asset exists in the Automation account."
	}

	Write-Verbose "Authenticating to Azure with certificate." -Verbose
	Set-AzureSubscription -SubscriptionName $Conn.SubscriptionName -SubscriptionId $Conn.SubscriptionID -Certificate $AzureCert 
	Select-AzureSubscription -SubscriptionId $Conn.SubscriptionID
}

function Create-NewDeployment($CloudServiceName, $CloudServiceSlot, $AzurePackageUrl, $AzureConfigurationFile)
{
    Write-Output "Creating a new deployment to slot '$CloudServiceSlot' in '$CloudServiceName' with package from '$AzurePackageUrl' and configuration file from '$AzureConfigurationFile'..."
    New-AzureDeployment -ServiceName $CloudServiceName -Slot $CloudServiceSlot -Package $AzurePackageUrl -Configuration $AzureConfigurationFile -label "Deployed by automation account" | Out-Null
}

function Get-AzurePackageUrlAndConfigurationFile($StorageAccountName, $ContainerName) 
{
	$StorageKey = (Get-AzureStorageKey -StorageAccountName $StorageAccountName).Primary
	$Context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey
	$TemporaryFolder = $env:TEMP

	Write-Verbose "Searching Azure Cloud Package and configuration file from storage account '$StorageAccountName' and container '$ContainerName'" -Verbose

	$Blobs = Get-AzureStorageBlob -Container $ContainerName -Context $Context | Sort-Object 'LastModified'
	
	$LatestAzurePackage = $Blobs | Where-Object {$_.Name -Match ".cspkg"} | Select-Object -Last 1
	$LatestAzureConfigurationFile = $Blobs | Where-Object {$_.Name -Match ".cscfg"} | Select-Object -Last 1

	if($LatestAzurePackage -eq $null) {
		throw 'No Azure package (cspkg) found'
	}
	
	if($LatestAzureConfigurationFile -eq $null) {
		throw 'No Azure configuration file (cscfg) found'
	}
	
	$AzureConfigurationFileLocation = Join-Path $TemporaryFolder $LatestAzureConfigurationFile.Name
	Write-Verbose "Writing Azure configuration file to temporary location $AzureConfigurationFileLocation" -Verbose
	$LatestAzureConfigurationFile | Get-AzureStorageBlobContent -Destination $TemporaryFolder -Context $Context -Force >$null 2>&1

	return $LatestAzurePackage.ICloudBlob.uri.AbsoluteUri, $AzureConfigurationFileLocation
}

function Wait-ForComplete($CloudServiceName, $CloudServiceSlot) 
{
	Write-Verbose "Waiting deployment to complete.." -Verbose
    $completeDeployment = Get-AzureDeployment -ServiceName $CloudServiceName -Slot $CloudServiceSlot

    $completeDeploymentID = $completeDeployment.DeploymentId
    Write-Output "Deployment complete. Deployment ID: $completeDeploymentID"
}

function Enable-RemoteDesktop($CloudServiceName, $CloudServiceSlot, $RemoteDesktopUsername, $RemoteDesktopPassword) 
{
	if(Get-AzureServiceRemoteDesktopExtension -ServiceName $CloudServiceName -slot $CloudServiceSlot)
	{
		Write-Warning "Remote desktop already enabled for Cloud Service '$CloudServiceName' in '$CloudServiceSlot' slot"
		return
	}
	
	Write-Verbose "Enabling remote desktop to Cloud Service '$CloudServiceName' in '$CloudServiceSlot' slot.." -Verbose

	$securePassword = ConvertTo-SecureString -String $RemoteDesktopPassword -AsPlainText -Force | ConvertFrom-SecureString
	$credential = New-Object System.Management.Automation.PSCredential $RemoteDesktopUsername, ($securePassword | ConvertTo-SecureString)

	Set-AzureServiceRemoteDesktopExtension -ServiceName $CloudServiceName -Credential $credential -slot $CloudServiceSlot
	Write-Output "Remote desktop enabled for Cloud Service '$CloudServiceName' in '$CloudServiceSlot' slot"
}

Login

$AzurePackageUrl, $AzureConfigurationFile  = Get-AzurePackageUrlAndConfigurationFile -StorageAccountName $StorageAccountName -ContainerName $ContainerName

Write-Verbose "Searching deployments from slot '$CloudServiceSlot' in '$CloudServiceName'" -Verbose
$deployment = Get-AzureDeployment -ServiceName $CloudServiceName -Slot $CloudServiceSlot -ErrorVariable a -ErrorAction SilentlyContinue

if (($a[0] -ne $null) -or ($deployment.Name -eq $null)) 
{ 
	Create-NewDeployment -CloudServiceName $CloudServiceName -CloudServiceSlot $CloudServiceSlot -AzurePackageUrl $AzurePackageUrl -AzureConfigurationFile $AzureConfigurationFile
	Wait-ForComplete $CloudServiceName -CloudServiceSlot $CloudServiceSlot
	Remove-Item $AzureConfigurationFile -Force
	if ($EnableRemoteDesktop -eq $true) {
		Enable-RemoteDesktop -CloudServiceName $CloudServiceName -CloudServiceSlot $CloudServiceSlot -RemoteDesktopUsername $RemoteDesktopUsername -RemoteDesktopPassword $RemoteDesktopPassword | Out-Null
	}
}
else 
{
	Write-Warning "A deployment already exists in $CloudServiceName for slot $CloudServiceSlot."
}

Write-Verbose "All done!" -Verbose