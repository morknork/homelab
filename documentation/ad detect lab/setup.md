## DC Setup & Promotion
New-NetIPAddress -AddressFamily IPv4 -DefaultGateway 192.168.0.2 -InterfaceAlias Ethernet0 -IPAddress 192.168.0.10 -PrefixLength 24 

## Best practice point DC to another primary DC to avoid replication errors
Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses 127.0.0.1

Install-ADDSForest -DomainName "mek.morknork.com" -InstallDNS 

Set-DnsServerForwarder -IPAddress "10.0.0.25" -Passthru

Thought there was some trouble with internet connectivitiy due to the globe in systray showing no internet and nslookup returning website.com.morknork.com
 - nslookup was appending morknork.com
Resolve-DnsName website.com returned an actual IP
Browser connects to internet okay

Realised the DC name was random after promoting to DC and running AD populate script. Tore down forest and renamed to MEKDC01

## Workstation

Access denied when trying to domain join the WS. Time had drifted between the DC and WS. Used w32m /resync to align the times. Time difference caused Kerberos to deny the ticket 

## AD User/Group Setup

Script created with a functional test environment

## Notes
- Added SSH signing key to github and git config, default verified commits now
    https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification#ssh-commit-signature-verification

