# Lets-Encrypt_Automate_PowerShell

This PowerShell script automates the process of generating a LetsEncrypt SSL Certificate and assigning it to a IIS Site. It can create a HTTPS binding for a Site or it can Renew a current HTTPS Binding with new Certificate

It requries that ACMESharp is installed on the Server - https://github.com/ebekker/ACMESharp

The script should be ran on the IIS Server.

It has three parameters:
domain - This is the DNS. It should be accessable from the Internet.
iisSiteName - This is the Name of the Site as seen in the IIS Management Console.
renew - If you are creating a Certificate for this Site for the First time this should be "False". If you are renewing a certificate set it to "True"

.\PATHTOSCRIPT\Lets-Encrypt_Automate_PowerShell.ps1 -domain "reportifier.com" -iisSiteName "reportifier.com" -renew "False"
