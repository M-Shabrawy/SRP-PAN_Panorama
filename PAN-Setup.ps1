## Setup sript for PAN Panorama SRP
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PANHost,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$PANUser,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$PANPass,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$APIKey,
    [Parameter(Mandatory=$false)]
    [string]$ConfigFilePath = 'C:\Program Files\LogRhythm\Smart Response Plugins\PAN Panorama REST SRP'
)

$ConfigFile = $ConfigFilePath + "config.xml"
trap [Exception] 
{
	write-error $("Exception: " + $_)
	exit 1
}

Function Disable-SSLError{
	add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3,[Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
}

#-----------Check Configuration file path------------
Function Check-ConfigPath
{
    if(!(Test-Path $ConfigFilePath)) {
        Write-Host ('Folder not found: "$CredentialsFile" Creating')
        try {
            New-Item -Path $ConfigFilePath -ItemType Directory -Force
        }
        catch {
            Write-Error ('Failed to create folder $ConfigFilePath')
            exit 1
        }
    }
}

Function Get-Key
{
    if($APIKey -eq ""){
        $PANAPIKeyURL = "https://$PANHost/api/?type=keygen&user=$PANUser&password=$PANPass"
   try{
        [xml]$xmlresult = = Invoke-WebRequest -Method Get -Uri $PANAPIKeyURL
    }
    catch {
        if($message -eq "The remote server returned an error: (401) Unauthorized."){
            write-host "Invalid Credentials."
			write-error "Error: Invalid or Incorrect Credentials provided."
			throw "ExecutionFailure"
            exit
        }
		else{
			write-host $message
			write-error "API Call Unsuccessful."
			throw "ExecutionFailure"
            exit
		}
    }
    $APIKey = $xmlresult.response.result.key
    }
}


Function Create-Hashtable
{
	$HashTable = [PSCustomObject]@{  
        "SEPHost" = $PANHost | ConvertTo-SecureString
        "APIKey" = $APIKey | ConvertTo-SecureString
	}
}


Function Create-ConfigFile
{
    try {
        if (!(Test-Path $ConfigFile)) {
            Write-Host ("Configuration file not found: " + $ConfigFile + "Creating a new one")
            New-Item -Path $ConfigFile -ItemType File -Force
        }
        else {
            $HashTable | Export-Clixml -Path $ConfigFile
        }
    }
    catch {
    Write-Error ("Failed to create configuration file: " + $ConfigFile)
    exit
    }
}

Disable-SSLError
Check-ConfigPath
Get-Key
Create-ConfigFile