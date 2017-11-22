param([string]$domain,[string]$iisSiteName, [string]$renew);

###############################################################################################
##Initialize
###############################################################################################
$ErrorActionPreference = "Stop"

####Import ACMESharp
try{
    import-module ACMESharp
} catch{
    return "Couldn't load ACMESharp."
    break
}

####Get script location
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

####Fail Variables
$failInvalid = $false
$failOnCert = $false
$finalStatus = "Success"

####The ACME ALias is set to be the same as the Domain.
$alias = $domain

####Cert Paths
$certname = $alias +"_"+"$(get-date -format yyyy-MM-dd--HH-mm)"
$pfxfile = "$dir\$certname.pfx"

$SiteFolder = Join-Path -Path 'C:\inetpub\wwwroot' -ChildPath $iissitename

$initializevault = $FALSE
$createregistration = $FALSE

#Not used. Left for reference. If ACME Vault is not initialized it should be. This is a one time operation.
if($initializevault) {
    Initialize-ACMEVault
}

####Get Acme Vault
$vault = Get-ACMEVault -VaultProfile :sys

####Change to the Vault folder
cd "C:\ProgramData\ACMESharp\sysVault"

####Check if alias already created
$aliasCheck = $vault.Identifiers | where {$_.Alias -eq $alias}

if($aliasCheck){
    $createalias = $FALSE
} else {
    $createalias = $TRUE
}

###############################################################################################
##Functions
###############################################################################################

####Check Request Status is Ready before continuing. Keeps checking until Status is Valid or Failed.
function checkReqStatus {
    $statusFull = (Update-ACMEIdentifier $alias -ChallengeType http-01).Challenges
    $statusHTTP = $statusFull | where {$_.Type -eq "http-01"}

    if($statusHTTP.status -eq "Pending"){
        ####Loop Again
        Start-Sleep -Seconds 10
        checkReqStatus
    } elseif ($statusHTTP.status -eq "Valid"){
        ####Continue with script
    } else {
        $failInvalid = $true
    }
}

####Check if Certificate is Ready before Downloading. If Certificate is not ready after 5 tries is Fails.
function checkCertStatus {
    $i++
    $certFull = update-AcmeCertificate $certname
    if($certFull.Alias){
        if((!($certFull.IssuerSerialNumber)) -and ($i -le 5)){
            Start-Sleep -Seconds 10
            checkCertStatus
        } 
    } else {
        $failOnCert = $true
    }
}

###############################################################################################
##Core
###############################################################################################

####Check if Binding already Exists
$obj = get-webconfiguration "//sites/site[@name='$iissitename']"
$binding = $obj.bindings.Collection | where {(($_.protocol -eq "HTTPS") -and ($_.bindingInformation -eq ("*:443:" + $domain)))}


####Proceed only if there is no such binding or if the renew param is true
if((!($binding)) -or ($renew -eq "True")){

    ###############################################################################################
    ##New Registration
    ###############################################################################################
    if($createregistration) {
        # Set up new 'account' tied to an email address
            New-AcmeRegistration -Contacts "$email" -AcceptTos | out-null
            start-sleep -Seconds 2
    }

    ###############################################################################################
    ##New Alias
    ###############################################################################################
    if($createalias){
        ####Associate a new site 
        try{
            New-AcmeIdentifier -Dns $domain -Alias $alias -ErrorAction Stop | out-null
        } catch {
            $finalStatus = "Error: AcmeIdentifier already exists or creation failed"
            return "Error: AcmeIdentifier already exists or creation failed"
        }
        start-sleep -Seconds 2

        ####Prove the site exists and is accessible
        try{
            Complete-ACMEChallenge $alias -ChallengeType http-01 -Handler iis -HandlerParameters @{WebSiteRef="$iissitename"} -ErrorAction Stop | out-null
        } catch {
            $finalStatus = "Error: ACMEChallenge Complete Failed"
            return "Error: ACMEChallenge Complete Failed"
        }
        start-sleep -Seconds 2

        ####Validate site
        try {
            Submit-ACMEChallenge $alias -ChallengeType http-01 -ErrorAction Stop | out-null
        } catch {
            $finalStatus = "Error: ACMEChallenge Submit Failed"
            return "Error: ACMEChallenge Submit Failed"     
        }

        ####Check until Pending changes to Valid or Invalid
        checkReqStatus   
    }

    ###############################################################################################
    ##Generate Certificate
    ###############################################################################################
    if($failInvalid -eq $false){
        ####Generate a certificate
        New-ACMECertificate ${alias} -Generate -Alias $certname | out-null
        start-sleep -Seconds 2
        ####Submit the certificate
        Submit-ACMECertificate $certname | out-null
        start-sleep -Seconds 2

        ####Check Certificate Status until Certificate is Ready
        $i = 0
        checkCertStatus

        if($failOnCert -eq $false){
            ####Export Certificate to PFX file
            Get-ACMECertificate $certname -ExportPkcs12 $pfxfile | out-null
            start-sleep -Seconds 2
            ####Import Certificate
            $certRootStore = “LocalMachine”
            $certStore = "My"
            $pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $pfx.import($pfxfile,$pfxPass,“Exportable,MachineKeySet,PersistKeySet”)
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($certStore,$certRootStore) 
            $store.Open('ReadWrite')
            $store.Add($pfx) 
            $store.Close() 
            $certThumbprint = $pfx.Thumbprint

            if($renew -eq "False"){
                ####Create Binding
                try{
                    New-WebBinding -Name $iissitename -IPAddress "*" -Port 443 -Protocol "https" -HostHeader $domain -SslFlags 1 -ErrorAction Stop 
                } catch{
                    return "Error: New Web Binding Failed"
                }
            }
            ####Set Certificate
            $obj = get-webconfiguration "//sites/site[@name='$iissitename']"
            $binding = $obj.bindings.Collection | where {(($_.protocol -eq "HTTPS") -and ($_.bindingInformation -eq ("*:443:" + $domain)))}
            $method = $binding.Methods["AddSslCertificate"]
            $methodInstance = $method.CreateInstance()
            $methodInstance.Input.SetAttributeValue("certificateHash", $certThumbprint)
            $methodInstance.Input.SetAttributeValue("certificateStoreName", $certStore)
            $methodInstance.Execute()
        } else {
            return "Error: Generation of Certificate failed"        
        }

    } else {
        return "Error: ACMEChallenge invalid."
    }

} else {
    return "Error: Binding already exists. Renew Off."
}
return $finalStatus

