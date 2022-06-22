<#
.EXAMPLE
Runs script and performs disable/delete
ComputerObjectCleanup.ps1 -server server@domain.com -credential username@domain.com 
.EXAMPLE
Runs script internally without specifying -server
ComputerObjectCleanup.ps1 -credential username@domain.com
.EXAMPLE
Shows what the script will do to ADObjects
ComputerObjectCleanup.ps1 -Server server@domain.com -credential username@domain.com -whatif
.EXAMPLE
Prints report but does not take any action on ADObjects
ComputerObjectCleanup.ps1 -Server server@domain.com -credential usernam@domain.com -report $true
#>
[CmdletBinding(SupportsShouldProcess)]
param
(
   [Parameter()]
   [datetime]
   $DisableCutoffDate = [datetime]::Today.AddDays(-30),

   [Parameter()]
   [datetime]
   $DeleteCutoffDate = [datetime]::Today.AddDays(-120),

   [Parameter()]
   [bool]
   $report,

   [Parameter()]
   [string]
   $server,

   # store credentials
   [Parameter()]
   [ValidateNotNull()]
   [System.Management.Automation.PSCredential]
   [System.Management.Automation.Credential()]
   $credential = [System.Management.Automation.PSCredential]::Empty
)

# pull domains from forest 
function Get-Domains{
   (Get-ADForest -Server $server -Credential $credential -ErrorAction Stop).Domains
}

# pulls all properties from each ADObject with a lastlogondate less than the disablecutoffdate & not $null
# uses try/catch for error handling and will stop script if there is an issue connecting to an AD server. 
try {
   if($report -eq $true){
      $($(Get-Domains | foreach {
         get-adcomputer -Server $_ -filter 'LastLogonDate -ne "$null" -and LastLogonDate -lt $disablecutoffdate' -Properties DNSHostName, OperatingSystem, Enabled, Description, LastLogonDate, SAMAccountName -Credential $credential
      }) | foreach{
         if ($_.LastLogonDate -lt $DeleteCutoffDate){
            $_.Action = 'Delete'
            $_
         }else{
            $_.Action = 'Disable'
            $_
         }
      }) | Sort-Object LastLogonDate | Format-Table Action, DNSHostName, LastLogonDate, OperatingSystem, Description
   }else{
      Get-Domains | foreach {
         $adobjects = get-adcomputer -Server $_ -filter 'LastLogonDate -ne "$null" -and LastLogonDate -lt $disablecutoffdate' -Properties DNSHostName, OperatingSystem, Enabled, Description, LastLogonDate, SAMAccountName -Credential $credential | Sort-Object LastLogonDate
         foreach($computer in $adobjects){
            if($computer.LastLogonDate -lt $DeleteCutoffDate){
               if($PSCmdlet.ShouldProcess($computer.DNSHostName, "Delete")){
                  Get-ADComputer -Server $_ -Identity $computer.SamAccountName -Credential $credential | Remove-ADObject -confirm:$false -Recursive
               }
            Write-host "Deleted computer $($computer.name)"
            }elseif($computer.LastLogonDate -lt $DisableCutoffDate){
               if($PSCmdlet.ShouldProcess($computer.DNSHostName, "Disable")){
                  Disable-ADAccount -Server $_ -Identity $computer.SamAccountName -Credential $credential -confirm:$false
               }
            Write-host "Disabled computer $($computer.name)"
            }
         }
      }
   }
}
catch {
   $Error[0].Exception.GetType().FullName
   Write-Error -ErrorRecord $_
}