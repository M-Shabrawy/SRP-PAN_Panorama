## PaloAlto Networks Panorama REST API Integration
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('AddIP','AddDomain')]
    [string]$Action,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Host,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Group,
    [Parameter(Mandatory=$false)]
    [string]$Location = "shared",
    [Parameter(Mandatory=$false)]
    [string]$ApiKEY,
    [Parameter(Mandatory=$false)]
    [string]$PANHost,
    [Parameter(Mandatory=$false)]
    [string]$ConfigFilePath = 'C:\Program Files\LogRhythm\Smart Response Plugins\PAN Panorama REST SRP\config.xml',
    [Parameter(Mandatory=$false)]
    [string]$PANVersion = 'v9.1'
)

$Global:ApiKEY = "LUFRPT01T29EdXJIRXJhMzMyWnFmUWhKMTFkb3Q0b0U9bWVFU1gzbVYva09CV2dFUngveEF0QVk0cXB2SmhEN2tUVkhQdWVGbGI3RlhMRXVDeHYrcHpnTTAzZnZrMEdTdw=="
$Global:PANHost = '127.0.0.1'
$Global:PANAPIBaseURI = "https://$Global:PANHost/restapi-doc/restapi/$Global:PANVersion/"
$tag = 'LRSRP'

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

Function Get-Config{
   try {
        if (Test-Path $Global:ConfigFile) {
            Write-Host ("Configuration file found: " + $Global:ConfigFile)
            $Credentials = Import-Clixml -Path $Global:ConfigFile
            $Global:PANHost =  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($Credentials.PANHost))))
            $Global:APIKey =  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($Credentials.APIKey))))
        }
       else{
           Write-Host ("Configuration file not found. Please use Setup action to creat: " + $ConfigFile)
           exit 1
       }
    }
    catch {
        Write-Error ("The credentials within the configuration file are corrupt. Please recreate the file: " + $Global:ConfigFile)
        exit 1
    }
    $Global:PANAPIBaseURI = "https://$Global:PANHost/restapi-doc/restapi/$Global:PANVersion/"
}

Function Check-Group{
    if($Global:Location -eq 'shared'){
        $GroupURI = "$Global:PANAPIBaseURI/Objects/AddressGroups?name=$Global:Group&localtion=$Global:Location&key=$Global:APIKey"
    }else{
         $GroupURI = "$Global:PANAPIBaseURI/Objects/AddressGroups?name=$Global:Group&localtion=device-group&device-group=$Global:Location&key=$Global:APIKey"
    }
    
    try{
        $result = Invoke-RestMethod -Method Get -Uri $GroupURI -Headers -ContentType 'application/json'
        if (($result | CovertFROM-JSON).result.entry.static.memeber -eq $Global:Group){
            Write-Host "Group found $Global:Group"
        }
    }
    catch{
        write-host $message
		write-error "API Call Unsuccessful."
		throw "ExecutionFailure"
        exit 1
    }

}

Function Add-Host{
    if($Global:Location -eq 'shared'){
        $AddressURI = "$Global:PANAPIBaseURI/Objects/Addresses?name=$Global:Group&localtion=$Global:Location&key=$Global:APIKey&name=$Global:Host"
    }else{
         $AddressURI = "$Global:PANAPIBaseURI/Objects/Addresses?name=$Global:Group&localtion=device-group&device-group=$Global:Location&key=$Global:APIKey&name=$Global:Host"
    }
    if($Action -eq 'AddIP'){
        $AddressJSON = 
        '{
           "entry" : {
               "ip-netmask" : $($Global:Host)
               }
           }
       }'
    }elseif ($Action -eq 'AddDomain'){
        $AddressJSON = 
        '{
           "entry" : {
               "fqdn" : $($Global:Host)
               }
           }
       }'
    }
    
    try{
        $result = Invoke-RestMethod -Method Post -Uri $AddressURI -Headers -ContentType 'application/json' -Body $AddressJSON
        Write-Host $result
    }
    catch{
        write-host $message
		write-error "API Call Unsuccessful."
		throw "ExecutionFailure"
        exit 1
    }
}

Disable-SSLError
Get-Config
Check-Group
Add-Host