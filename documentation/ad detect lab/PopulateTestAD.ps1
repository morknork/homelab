#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Builds a tailored Active Directory environment for the MEK detection lab.

.DESCRIPTION
    Idempotent, re-runnable provisioning for mek.morknork.com. Creates an OU
    structure, security groups, user accounts, and service accounts suited to
    generating telemetry and running attack simulations (Sysmon/Wazuh + Atomic
    Red Team). Safe to re-run: existing objects are detected and skipped, and
    group membership is reconciled on every run.

    The domain DN is read at runtime via Get-ADDomain, so this script is not
    tied to a hardcoded domain and will not suffer the classic "DC=example,DC=com"
    failure if copied between labs.

    DELIBERATE LAB-ISMS (insecure by design; acceptable ONLY in an isolated lab):
      * All accounts share one known password so you can log in as any of them
        to generate telemetry. Never do this outside an isolated lab.
      * Passwords never expire and are not forced to change at logon, so accounts
        stay usable across rebuilds and scripted logons.
      * OUs are NOT protected from accidental deletion, so the whole lab can be
        torn down quickly. In production this would be $true.
      * No account is placed in a built-in privileged group (e.g. Domain Admins).
        A separate, non-privileged "Lab Admins" group is provided instead. An
        account-tiering example (a separate admin account for one user) is
        included to model good practice and give you privileged-vs-normal
        activity to detect.
      * A kerberoastable service-account scenario is available but OFF by default
        (see $EnableKerberoastTarget). The lab is not weakened unless you opt in.

.NOTES
    Run on MEKDC01 as a domain administrator.
#>

Set-StrictMode -Version Latest

# ============================================================================
#  Settings you may want to change
# ============================================================================

# Shared lab password for all accounts (LAB ONLY). Must meet the domain policy.
$LabPassword = 'Tr@in1ng-L@b-2026!'

# Top-level container OU that all lab objects live under, so the lab is easy to
# find, target with GPOs, and delete in one go.
$RootOuName = 'MEK'

# Opt-in kerberoasting detection scenario. When $true, an SPN is added to the
# svc-sql account, making it kerberoastable (a classic Event 4769 detection
# exercise). Left OFF so the lab isn't weakened unless you choose it.
$EnableKerberoastTarget = $false

# ============================================================================
#  Setup
# ============================================================================

Import-Module ActiveDirectory -ErrorAction Stop

$Domain  = Get-ADDomain -ErrorAction Stop
$BaseDN  = $Domain.DistinguishedName
$DnsRoot = $Domain.DNSRoot
Write-Host "Target domain: $BaseDN  ($DnsRoot)" -ForegroundColor Cyan

$SecurePassword = ConvertTo-SecureString $LabPassword -AsPlainText -Force
$Summary = [ordered]@{ Created = 0; Skipped = 0; Failed = 0 }

function Write-Result {
    param([string]$Type, [string]$Target, [string]$Status, [string]$Detail)
    switch ($Status) {
        'Created' { Write-Host "  [+] $Type created: $Target"      -ForegroundColor Green;    $script:Summary.Created++ }
        'Skipped' { Write-Host "  [=] $Type exists:  $Target"      -ForegroundColor DarkGray; $script:Summary.Skipped++ }
        'Failed'  { Write-Host "  [!] $Type FAILED:  $Target -> $Detail" -ForegroundColor Red; $script:Summary.Failed++ }
    }
}

# ============================================================================
#  Organizational Units
# ============================================================================
# Defined as DNs relative to the domain root. They are sorted by depth before
# creation so a parent OU always exists before its children, regardless of the
# order they appear in this array.

function New-LabOU {
    param([Parameter(Mandatory)][string]$RelativeDN)
    $fullDN     = "$RelativeDN,$BaseDN"
    $name       = (($RelativeDN -split ',')[0]) -replace '^OU=', ''
    $parentRel  = $RelativeDN -split ',', 2
    $parentPath = if ($parentRel.Count -gt 1) { "$($parentRel[1]),$BaseDN" } else { $BaseDN }
    try {
        if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullDN'" -ErrorAction SilentlyContinue) {
            Write-Result 'OU' $fullDN 'Skipped'
        } else {
            New-ADOrganizationalUnit -Name $name -Path $parentPath `
                -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
            Write-Result 'OU' $fullDN 'Created'
        }
    } catch { Write-Result 'OU' $fullDN 'Failed' $_.Exception.Message }
}

$OUs = @(
    "OU=$RootOuName",
    "OU=Servers,OU=$RootOuName",
    "OU=Workstations,OU=$RootOuName",
    "OU=Groups,OU=$RootOuName",
    "OU=Service Accounts,OU=$RootOuName",
    "OU=Admin Accounts,OU=$RootOuName",
    "OU=Departments,OU=$RootOuName",
    "OU=IT,OU=Departments,OU=$RootOuName",
    "OU=HR,OU=Departments,OU=$RootOuName",
    "OU=Finance,OU=Departments,OU=$RootOuName",
    "OU=Executive,OU=Departments,OU=$RootOuName"
)

Write-Host "`nCreating OUs..." -ForegroundColor Cyan
$OUs | Sort-Object { ($_ -split ',').Count } | ForEach-Object { New-LabOU $_ }

# ============================================================================
#  Security Groups
# ============================================================================

function New-LabGroup {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [string]$Description = ''
    )
    try {
        if (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue) {
            Write-Result 'Group' $Name 'Skipped'
        } else {
            New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security `
                -Path $Path -Description $Description -ErrorAction Stop
            Write-Result 'Group' $Name 'Created'
        }
    } catch { Write-Result 'Group' $Name 'Failed' $_.Exception.Message }
}

$GroupsOU = "OU=Groups,OU=$RootOuName,$BaseDN"
$Groups = @(
    @{ Name = 'IT Support';       Desc = 'IT department staff' },
    @{ Name = 'HR Team';          Desc = 'Human Resources staff' },
    @{ Name = 'Finance Team';     Desc = 'Finance department staff' },
    @{ Name = 'Executives';       Desc = 'Executive / leadership' },
    @{ Name = 'File Share Users'; Desc = 'General access to shared resources' },
    @{ Name = 'Lab Admins';       Desc = 'NON-privileged delegated admin group for the lab (NOT Domain Admins)' }
)

Write-Host "`nCreating groups..." -ForegroundColor Cyan
foreach ($g in $Groups) { New-LabGroup -Name $g.Name -Path $GroupsOU -Description $g.Desc }

# ============================================================================
#  Users and Service Accounts
# ============================================================================

function New-LabUser {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Sam,
        [Parameter(Mandatory)][string]$OuRelative,
        [string[]]$MemberOf = @(),
        [string]$Title = '',
        [string]$Department = ''
    )
    $fullOU  = "$OuRelative,$BaseDN"
    $parts   = $DisplayName -split ' ', 2
    $given   = $parts[0]
    $surname = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $upn     = "$Sam@$DnsRoot"

    try {
        if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
            Write-Result 'User' $Sam 'Skipped'
        } else {
            $params = @{
                Name                  = $DisplayName
                DisplayName           = $DisplayName
                GivenName             = $given
                SamAccountName        = $Sam
                UserPrincipalName     = $upn
                Path                  = $fullOU
                AccountPassword       = $SecurePassword
                Enabled               = $true
                PasswordNeverExpires  = $true
                ChangePasswordAtLogon = $false
                ErrorAction           = 'Stop'
            }
            if ($surname)    { $params.Surname    = $surname }
            if ($Title)      { $params.Title      = $Title }
            if ($Department) { $params.Department = $Department }
            New-ADUser @params
            Write-Result 'User' $Sam 'Created'
        }

        # Reconcile group membership on every run. Add-ADGroupMember errors if the
        # member is already present, so each add is guarded.
        foreach ($grp in $MemberOf) {
            try {
                $already = Get-ADGroupMember -Identity $grp -ErrorAction Stop |
                           Where-Object { $_.SamAccountName -eq $Sam }
                if (-not $already) {
                    Add-ADGroupMember -Identity $grp -Members $Sam -ErrorAction Stop
                    Write-Host "      + $Sam -> $grp" -ForegroundColor Green
                }
            } catch {
                Write-Host "      [!] could not add $Sam -> $grp : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } catch { Write-Result 'User' $Sam 'Failed' $_.Exception.Message }
}

Write-Host "`nCreating users..." -ForegroundColor Cyan

# Department staff
New-LabUser -DisplayName 'Alice Brown'  -Sam 'abrown'  -OuRelative "OU=IT,OU=Departments,OU=$RootOuName"        -MemberOf 'IT Support','File Share Users'   -Title 'Systems Administrator' -Department 'IT'
New-LabUser -DisplayName 'Bob White'    -Sam 'bwhite'  -OuRelative "OU=IT,OU=Departments,OU=$RootOuName"        -MemberOf 'IT Support','File Share Users'   -Title 'Helpdesk Technician'   -Department 'IT'
New-LabUser -DisplayName 'Carol Green'  -Sam 'cgreen'  -OuRelative "OU=HR,OU=Departments,OU=$RootOuName"        -MemberOf 'HR Team','File Share Users'      -Title 'HR Coordinator'        -Department 'HR'
New-LabUser -DisplayName 'Emma Wilson'  -Sam 'ewilson' -OuRelative "OU=HR,OU=Departments,OU=$RootOuName"        -MemberOf 'HR Team'                         -Title 'HR Manager'            -Department 'HR'
New-LabUser -DisplayName 'David Black'  -Sam 'dblack'  -OuRelative "OU=Finance,OU=Departments,OU=$RootOuName"   -MemberOf 'Finance Team','File Share Users' -Title 'Accountant'            -Department 'Finance'
New-LabUser -DisplayName 'Frank Harris' -Sam 'fharris' -OuRelative "OU=Finance,OU=Departments,OU=$RootOuName"   -MemberOf 'Finance Team'                    -Title 'Finance Analyst'       -Department 'Finance'
New-LabUser -DisplayName 'Grace Lee'    -Sam 'glee'    -OuRelative "OU=Executive,OU=Departments,OU=$RootOuName" -MemberOf 'Executives','File Share Users'   -Title 'Chief Operating Officer' -Department 'Executive'

# Account-tiering example: Bob's daily account is 'bwhite' above; his admin work
# is done from a SEPARATE account in the Admin Accounts OU. This models good
# practice (tier separation) and gives you privileged-account activity to detect,
# without ever touching the built-in Domain Admins group.
New-LabUser -DisplayName 'Bob White (Admin)' -Sam 'a-bwhite' -OuRelative "OU=Admin Accounts,OU=$RootOuName" -MemberOf 'Lab Admins' -Title 'IT Admin (privileged)' -Department 'IT'

# Service accounts (least privilege by default).
New-LabUser -DisplayName 'svc-backup' -Sam 'svc-backup' -OuRelative "OU=Service Accounts,OU=$RootOuName" -Title 'Backup Service'
New-LabUser -DisplayName 'svc-sql'    -Sam 'svc-sql'    -OuRelative "OU=Service Accounts,OU=$RootOuName" -Title 'SQL Service'

# ============================================================================
#  Optional: kerberoasting detection target
# ============================================================================
# An SPN on a user account makes it kerberoastable: any domain user can request
# a service ticket for it and crack it offline. Detect via Event 4769 (RC4 from
# an unusual source). Enabled only when $EnableKerberoastTarget is $true.

if ($EnableKerberoastTarget) {
    Write-Host "`nEnabling kerberoasting target on svc-sql..." -ForegroundColor Yellow
    try {
        Set-ADUser -Identity 'svc-sql' `
            -ServicePrincipalNames @{ Add = "MSSQLSvc/mekdc01.$DnsRoot`:1433" } -ErrorAction Stop
        Write-Host "  [+] SPN added to svc-sql (kerberoastable)" -ForegroundColor Yellow
    } catch {
        Write-Host "  [!] Could not set SPN on svc-sql: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
#  Summary
# ============================================================================

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Created: $($Summary.Created)   Skipped: $($Summary.Skipped)   Failed: $($Summary.Failed)"
if ($Summary.Failed -gt 0) { Write-Warning "Some objects failed. Review the [!] lines above." }
Write-Host "`nShared lab password: $LabPassword" -ForegroundColor Yellow
Write-Host "This environment is insecure by design and for an isolated lab only." -ForegroundColor Yellow