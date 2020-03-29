## PaloAlto Networks Panorama REST API Integration
[CmdLetBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('AddIP','AddDomain')]
    [string]$Action,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Address,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$AddressGroup,
    [Parameter(Mandatory=$false)]
    [string]$Location = "shared",
    [Parameter(Mandatory=$false)]
    [string]$ApiKEY,
    [Parameter(Mandatory=$false)]
    [string]$PANHost,
    [Parameter(Mandatory=$false)]
    [string]$ConfigFilePath = 'C:\Program Files\LogRhythm\Smart Response Plugins\PAN Panorama REST SRP\config.xml',
    [Parameter(Mandatory=$false)]
    [string]$PANVersion = '9.0'
)

$ApiKEY = "LUFRPT1aZlh5V3lTWEFYTVo1K2V6VmxMcjhpcEh0emc9aHo1RncwdUtNVzFmRlRtRGdlN3JQSXZ0SEpTRTZha1FZbzd0YU1FQWNpdnJLWWhzeHR6cmI5SWtxRm5DOVBBMktpVU9rWDBLRE84VGloQ1VwYkxHalE9PQ=="
$PANAPIBaseURI = "https://$PANHost/restapi/$PANVersion"
$tag = 'LRSRP'

trap [Exception] 
{
#	write-error $("Exception: " + $_)
#	exit 1
#}
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
        if (Test-Path $ConfigFile) {
            Write-Host ("Configuration file found: " + $ConfigFile)
            $Credentials = Import-Clixml -Path $ConfigFile
            $PANHost =  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($Credentials.PANHost))))
            $APIKey =  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($Credentials.APIKey))))
        }
       else{
           Write-Host ("Configuration file not found. Please use Setup action to creat: " + $ConfigFile)
           exit 1
       }
    }
    catch {
        Write-Error ("The credentials within the configuration file are corrupt. Please recreate the file: " + $ConfigFile)
        exit 1
    }
    $PANAPIBaseURI = "https://$PANHost/restapi/$PANVersion"
}

Function Check-Group{
    if($Location -eq 'shared'){
        $GroupURI = "$PANAPIBaseURI/Objects/AddressGroups?name=$AddressGroup&location=$Location&output-format=json&key=$APIKey"
    }else{
         $GroupURI = "$PANAPIBaseURI/Objects/AddressGroups?name=$AddressGroup&location=device-group&device-group=$Location&output-format=json&key=$APIKey"
    }       

    try{
         $result = Invoke-RestMethod -Method Get -Uri $GroupURI -ContentType 'application/json'
        write-Host $result.result.entry
        if ($result.StatusCode -eq '200'){
            Write-Host "Group found $AddressGroup"
        }else{
             Write-Host "Group result $($result.StatusCode)"
        }
    }
    catch{
        write-host $message
		write-host "Group API Call Unsuccessful"
        exit 1
    }

}

Function Add-Host{
    if($Location -eq 'shared'){
        $AddressURI = "$PANAPIBaseURI/Objects/Addresses?location=$Location&output-format=json&key=$APIKey&name=SRP-$Address"
    }else{
         $AddressURI = "$PANAPIBaseURI/Objects/Addresses?location=device-group&device-group=$Location&output-format=json&key=$APIKey&name=SRP-$Address"
    }
    if($Action -eq 'AddIP'){
        $AddressJSON = '{
           "entry" : [
                    {
                       "ip-netmask" : "'+ $Address +'",
                       "@name" : "SRP-' + $Address + '",
                       "@location" : "' + $Location + '",
                       "tag": {
                            "member": [
                                "LogRhythm"
                             ]
                         }
                   }
            ]
       }'
    }elseif ($Action -eq 'AddDomain'){
        $AddressJSON = '{
           "entry" : [
                    {
                       "fqdn" : "'+ $Address +'",
                       "@name" : "SRP-' + $Address + '",
                       "@location" : "' + $Location + '",
                       "tag": {
                            "member": [
                                "LogRhythm"
                             ]
                         }
                   }
            ]
       }'
    }
    $result = Invoke-RestMethod -Method Post -Uri $AddressURI -ContentType 'application/json' -Body $AddressJSON
    Write-Host $result
    try{
       # $result = Invoke-RestMethod -Method Post -Uri $AddressURI -ContentType 'application/json' -Body $AddressJSON
       # Write-Host $result
    }
    catch{
        write-host $message
		write-host "Address API Call Unsuccessful."
		throw "ExecutionFailure"
        exit 1
    }
}

Function Add-ToAddressGroup{
    if($Location -eq 'shared'){
        $GroupURI = "$PANAPIBaseURI/Objects/AddressGroups?name=$AddressGroup&location=$Location&output-format=json&key=$APIKey"
    }else{
         $GroupURI = "$PANAPIBaseURI/Objects/AddressGroups?name=$AddressGroup&location=device-group&device-group=$Location&output-format=json&key=$APIKey"
    }
    $result = Invoke-WebRequest -Uri $GroupURI -Method Get -ContentType 'application/json'
    
    $entry = ($result.Content | ConvertFrom-Json).result.entry
    $entry[0].static.member += "SRP-$Address"
    $Gob = [pscustomobject]@{
        "entry" = $entry
    }
    $GroupJSON = ($Gob | ConvertTo-Json -Depth 6)
    $GroupJSON
    $result = ""
    $result = Invoke-RestMethod -Uri $GroupURI -Method Put -Body $GroupJSON -ContentType 'application/json'
    $result
}


Function Commit-Config{
    $CommitURI = "https://$PANHost/api/?type=commit&cmd=<commit></commit>&key=$APIKey"
    $DeviceCommitURI = 'https://'+$PANHost+'/api/?type=commit&action=all&cmd=<commit-all><shared-policy><device-group><entry%20name="'+$LOcation+'"/></device-group></shared-policy></commit-all>&key='+$APIKey
}

Disable-SSLError
#Get-Config
Check-Group
Add-Host
Add-ToAddressGroup