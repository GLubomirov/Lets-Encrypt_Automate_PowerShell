# Lets-Encrypt_Automate_PowerShell

This PowerShell script automates the process of generating a LetsEncrypt SSL Certificate and assigning it to an IIS Site. It will either create an HTTPS binding for a Site or it can Renew a current HTTPS Binding with a new Certificate.

It requries that ACMESharp is installed on the Server - https://github.com/ebekker/ACMESharp

Thanks to Rick Strahl for the initial idea - https://weblog.west-wind.com/posts/2016/feb/22/using-lets-encrypt-with-iis-on-windows#TheEasyWay:LetsEncrypt-Win-Simple 

The script should be ran on the IIS Server with Administrative Priviliges.

You should initialize the ACME Vault and setup an ACME Registration before running the script if you havent already. 

This is done through two simple commands:

Initialize-ACMEVault

New-AcmeRegistration -Contacts "$email" -AcceptTos | out-null

The script is stripped of any host ouput since it is designed to be called automatically.

# Parameters

The Script has three parameters:

domain - This is the DNS. It should be accessable from the Internet.

iisSiteName - This is the Name of the Site as seen in the IIS Management Console.

renew - If you are creating a Certificate for this Site for the First time this should be "False". If you are renewing a certificate set it to "True"

.\PATHTOSCRIPT\Lets-Encrypt_Automate_PowerShell.ps1 -domain "reportifier.com" -iisSiteName "reportifier.com" -renew "False"

More Info: http://georgelubomirov.blogspot.bg/2017/11/automatic-issuance-and-renewal-of-ssl.html

There is also a suplementary script checking IIS Site Bindings with soon to expire certificates and calling the main script. It works best as a Task Scheduled Job.

The Script is called without parameters (again to faciliate easier calling from Task Scheduler). You have to change two things directly into the script.

The Path to the Main script, which is called for the bindings which will expire.

The number of days since the day of running the script in which the certificates will expire.

Both parameters are in the last 5 lines of the script.

With this you wouldn't have to worry about manually renewing certificates anymore.