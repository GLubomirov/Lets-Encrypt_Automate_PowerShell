function checkForCertificateExpiration($daysExpiry){
    ####Check if Script is Ran as Administrator. Otherwize IIS info is not available.
    If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){    
        write-host "This script needs to be run As Administrator" -ForegroundColor Red
        Break
    }

    ####Get Todays Date
    $todayDate = get-date

    ####Array for All Info
    $certInfo=@()

    ####Get All HTTPS Bindings
    $bindings = Get-WebBinding | where {$_.protocol -eq "https"}

    foreach($binding in $bindings){
        ####Get Certificate for the Binding from Certificate Store. Try Web Hosting Store first and if the Cert is not there try the Personal Stor
        $obj = dir "Cert:LocalMachine\WebHosting" -recurse | where {$_.Thumbprint -eq $binding.certificateHash} 

        if(!($obj)){
            $obj = dir "Cert:LocalMachine\My" -recurse | where {$_.Thumbprint -eq $binding.certificateHash}
        }


        ####Put relevant info into Array
        $certInfo += [PSCustomObject] @{
            ####Regex to get Site Name. Example "/system.applicationHost/sites/site[@name='WebAppsHTTPRedir' and @id='22']"
            SiteName = (($binding.ItemXPath -split ([RegEx]::Escape("[@name='")))[1]).split("'")[0]
            BindingInformation = $binding.bindingInformation
            Hash = $binding.certificateHash
            FriendlyName = $obj.FriendlyName
            NotAfter = $obj.NotAfter
        }
    }
    ####Array for Certificates nearing expiry
    $warningForExpiration=@()
    foreach($cert in $certInfo){
        if($cert.NotAfter){
            ####Check if Certificate Expiration mathes the rule
            if($cert.NotAfter -lt $todayDate.AddDays($daysExpiry)){
                              
                ####Add Object to Array
                $warningForExpiration+=$cert
            }
        }
    }

    ####Display Results
    #$warningForExpiration | out-gridview

    foreach($cert in $warningForExpiration){
        $bindingRegex = ($cert.BindingInformation -split "443:")[1]
        $siteName = $cert.SiteName

        ####Call Cetificate Renewal Script
        ."C:\PATHTOSCRIPT\Lets-Encrypt_Automate_PowerShell.ps1" -domain $bindingRegex -iisSiteName $siteName -renew "True"
    }
}

checkForCertificateExpiration -daysExpiry 2