#Get Snapshot
$snapshots = Get-VM | Get-VMSnapshot
# Check for existing Snapshots
if ($snapshots.count -gt 0){
    # Create the List of Snapshots
    $info = $snapshots | Format-Table VMName, Name -auto | Out-String
    # Mail Configuration
    # ==================
    # Configuration
    $emailFrom = "hyperv@eckler.ca"
    $emailTo = "fputhod@eckler.ca"
    $emailSubject = "VM Snapshot Reminder"
    $emailMessage = "You have some snapshots: `n `n" + $info + "`n Greetings your Hyper-V Server"
    $smtpServer = "venus.eckler.ca"
    #$smtpUserName = "username" # This could be also in e-mail address format
    #$smtpPassword = "password"
    #$smtpDomain = ""
    # SMTP Object
    $smtp = New-Object System.Net.Mail.SmtpClient($smtpServer)
    $mailCredentials = New-Object System.Net.NetworkCredential
    $mailCredentials.Domain = $smtpDomain
    $mailCredentials.UserName = $smtpUserName
    $mailCredentials.Password = $smtpPassword
    $smtp.Credentials = $mailCredentials
    # Send E-Mail
    $smtp.Send($emailFrom, $emailTo, $emailSubject, $emailMessage)
}