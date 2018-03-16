function checkForCertificateExpiration($daysExpiry, $renewCerts){
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
        ####Get Certificate for the Binding from Certificate Store. Try Web Hosting Store first and if the Cert is not there try the Personal Store
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

    if($renewCerts -eq "true"){
        ############################################
        ##Prepare Multi-threading
        ############################################

        ####Create an empty array for multi-threading
        $RunspaceCollection = @()

        ####This is the array we want to ultimately add our information to
        [Collections.Arraylist]$dataFull = @()

        ####Create the sessionstate variable entry
        $varPass = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'varPass',$Form,$Null

        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

        ####Variables passed to every Runspace. Not Used, left for reference.
        #$bindingRegex = [System.String]::Empty
        #$siteName = [System.String]::Empty

        ####Add the variable to the sessionstate. Not Used, left for reference.
        #$InitialSessionState.Variables.Add($bindingRegex)
        #$InitialSessionState.Variables.Add($siteName)

        ####Create a Runspace Pool with a minimum and maximum number of run spaces. (http://msdn.microsoft.com/en-us/library/windows/desktop/dd324626(v=vs.85).aspx)
        ####Edit how many sessions will be open - this is effectivelly how many users access the system at any time
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1,1,$InitialSessionState, $host)

        ####Open the RunspacePool
        $RunspacePool.Open()

        $ScriptBlock = {
            Param($bindingRegex, $siteName)
            ."C:\PS_Cert\certReq.ps1" -domain $bindingRegex -iisSiteName $siteName -renew "True"
        }

        ############################################
        ##Start Certificate Issuance 
        ############################################
        foreach($cert in $warningForExpiration){
            $bindingRegex = ($cert.BindingInformation -split "443:")[1]
            $siteName = $cert.SiteName

            ####You can exclude sites here
            #if($siteName -notlike "domain.com"){
                $Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($bindingRegex).AddArgument($siteName)

                $Powershell.RunspacePool = $RunspacePool

                [Collections.Arraylist]$RunspaceCollection += New-Object -TypeName PSObject -Property @{
		            Runspace = $PowerShell.BeginInvoke()
		            PowerShell = $PowerShell  
	            }
            #}        
        }

        ############################################
        ##Dispose of Threads
        ############################################

        ####Here we collect the Data and dispose of the Runspaces
        While($RunspaceCollection) {
	
	        ####Just a simple ForEach loop for each Runspace to get resolved
	        Foreach ($Runspace in $RunspaceCollection.ToArray()) {
		
		        ####Here's where we actually check if the Runspace has completed
		        If ($Runspace.Runspace.IsCompleted) {
			
			        ####Since it's completed, we get our results here
			        [void]$dataFull.Add($Runspace.PowerShell.EndInvoke($Runspace.Runspace))
			
			        ####Here's where we cleanup our Runspace
			        $Runspace.PowerShell.Dispose()
			        $RunspaceCollection.Remove($Runspace)
			
		        } #/If
	        } #/ForEach
        } #/While

    } else {

        $notificationMail = @()
        if($warningForExpiration){
            foreach($cert in $warningForExpiration){
                $bindingRegex = ($cert.BindingInformation -split "443:")[1]
                $siteName = $cert.SiteName

                ####You can exclude sites here
                ##if($siteName -notlike "domain.com"){
                    $notificationMail+=$bindingRegex
                ##} 
            }
        }
        
        if($notificationMail){
            $notificationMail | out-gridview
        }
    
    }
}

##Renew
checkForCertificateExpiration -daysExpiry 3 -renewCerts "true"

