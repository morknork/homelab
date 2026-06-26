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

 ## Workstation

 ## AD User/Group Setup
 