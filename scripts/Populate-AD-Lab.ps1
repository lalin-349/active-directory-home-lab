<#
.SYNOPSIS
    Populates an Active Directory lab: OUs, groups (AGDLP), users, file shares, and a sample GPO.

.NOTES
    Run on the Domain Controller (Windows Server 2022) AFTER AD DS promotion,
    in an elevated PowerShell window (Run as Administrator).
    Safe to re-run: every step checks whether the object already exists.
#>

Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module SmbShare

# ------------------------------------------------------------------
# 0. Variables
# ------------------------------------------------------------------
$domainDN  = (Get-ADDomain).DistinguishedName      # e.g. DC=lab,DC=local
$dnsRoot   = (Get-ADDomain).DNSRoot                # e.g. lab.local
$netbios   = (Get-ADDomain).NetBIOSName            # e.g. LAB
$rootOUName = "LabCorp"
$rootOU    = "OU=$rootOUName,$domainDN"
$departments = @("IT", "HR", "Sales")

# Initial password for all lab users (they must change it at first logon)
$initialPassword = Read-Host "Enter the initial password for new lab users" -AsSecureString

# ------------------------------------------------------------------
# 1. Organizational Units
# ------------------------------------------------------------------
Write-Host "`n[1/5] Creating OUs..." -ForegroundColor Cyan

if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$rootOU'")) {
    New-ADOrganizationalUnit -Name $rootOUName -Path $domainDN -ProtectedFromAccidentalDeletion $true
}

foreach ($sub in ($departments + @("Computers", "Groups"))) {
    $dn = "OU=$sub,$rootOU"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'")) {
        New-ADOrganizationalUnit -Name $sub -Path $rootOU -ProtectedFromAccidentalDeletion $true
        Write-Host "  Created OU: $sub"
    }
}

# ------------------------------------------------------------------
# 2. Groups (AGDLP: Accounts -> Global groups -> Domain Local groups -> Permissions)
# ------------------------------------------------------------------
Write-Host "`n[2/5] Creating groups..." -ForegroundColor Cyan
$groupsOU = "OU=Groups,$rootOU"

foreach ($dept in $departments) {
    # Global group holds the people
    $gg = "GG-$dept"
    if (-not (Get-ADGroup -Filter "Name -eq '$gg'")) {
        New-ADGroup -Name $gg -GroupScope Global -GroupCategory Security -Path $groupsOU `
            -Description "$dept department members"
        Write-Host "  Created group: $gg"
    }

    # Domain Local group holds the permission on the share
    $dl = "DL-Share-$dept-Modify"
    if (-not (Get-ADGroup -Filter "Name -eq '$dl'")) {
        New-ADGroup -Name $dl -GroupScope DomainLocal -GroupCategory Security -Path $groupsOU `
            -Description "Modify access to the $dept share"
        Write-Host "  Created group: $dl"
    }

    # Nest the global group inside the domain local group
    Add-ADGroupMember -Identity $dl -Members $gg -ErrorAction SilentlyContinue
}

# Everyone-in-the-company group for the shared "Company" folder
if (-not (Get-ADGroup -Filter "Name -eq 'GG-AllStaff'")) {
    New-ADGroup -Name "GG-AllStaff" -GroupScope Global -GroupCategory Security -Path $groupsOU
}
if (-not (Get-ADGroup -Filter "Name -eq 'DL-Share-Company-Modify'")) {
    New-ADGroup -Name "DL-Share-Company-Modify" -GroupScope DomainLocal -GroupCategory Security -Path $groupsOU
}
Add-ADGroupMember -Identity "DL-Share-Company-Modify" -Members "GG-AllStaff" -ErrorAction SilentlyContinue

# ------------------------------------------------------------------
# 3. Users
# ------------------------------------------------------------------
Write-Host "`n[3/5] Creating users..." -ForegroundColor Cyan

$users = @(
    @{ First = "Alice";  Last = "Nguyen";  Dept = "IT"    },
    @{ First = "Bob";    Last = "Martin";  Dept = "IT"    },
    @{ First = "Carla";  Last = "Santos";  Dept = "HR"    },
    @{ First = "David";  Last = "Okafor";  Dept = "HR"    },
    @{ First = "Elena";  Last = "Petrov";  Dept = "Sales" },
    @{ First = "Frank";  Last = "Weber";   Dept = "Sales" },
    @{ First = "Grace";  Last = "Kim";     Dept = "Sales" }
)

foreach ($u in $users) {
    $sam = ("{0}.{1}" -f $u.First, $u.Last).ToLower()
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'")) {
        New-ADUser `
            -Name "$($u.First) $($u.Last)" `
            -GivenName $u.First `
            -Surname $u.Last `
            -SamAccountName $sam `
            -UserPrincipalName "$sam@$dnsRoot" `
            -Department $u.Dept `
            -Path "OU=$($u.Dept),$rootOU" `
            -AccountPassword $initialPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true
        Write-Host "  Created user: $sam ($($u.Dept))"
    }
    Add-ADGroupMember -Identity "GG-$($u.Dept)" -Members $sam -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "GG-AllStaff"   -Members $sam -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# 4. File shares (share permissions + NTFS permissions)
# ------------------------------------------------------------------
Write-Host "`n[4/5] Creating file shares..." -ForegroundColor Cyan

$shareRoot = "C:\Shares"
New-Item -Path $shareRoot -ItemType Directory -Force | Out-Null

$shares = @{
    "Company" = "DL-Share-Company-Modify"
    "IT"      = "DL-Share-IT-Modify"
    "HR"      = "DL-Share-HR-Modify"
    "Sales"   = "DL-Share-Sales-Modify"
}

foreach ($name in $shares.Keys) {
    $path = Join-Path $shareRoot $name
    $dl   = $shares[$name]
    New-Item -Path $path -ItemType Directory -Force | Out-Null

    # Share-level permission: open to Authenticated Users, NTFS does the real restricting
    if (-not (Get-SmbShare -Name $name -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $name -Path $path -FullAccess "Authenticated Users" | Out-Null
        Write-Host "  Shared: \\$env:COMPUTERNAME\$name"
    }

    # NTFS permissions: remove inheritance, then grant only what is needed
    icacls $path /inheritance:r | Out-Null
    icacls $path /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "${netbios}\${dl}:(OI)(CI)M" | Out-Null
}

# ------------------------------------------------------------------
# 5. Sample Group Policy
# ------------------------------------------------------------------
Write-Host "`n[5/5] Creating sample GPO..." -ForegroundColor Cyan

# Stricter domain password policy
Set-ADDefaultDomainPasswordPolicy -Identity $dnsRoot `
    -MinPasswordLength 10 -ComplexityEnabled $true `
    -LockoutThreshold 5 -LockoutDuration "00:15:00" -LockoutObservationWindow "00:15:00"

# GPO that blocks Control Panel for the Sales OU
$gpoName = "Sales - Restrict Control Panel"
if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName | Out-Null
    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -ValueName "NoControlPanel" -Type DWord -Value 1 | Out-Null
    New-GPLink -Name $gpoName -Target "OU=Sales,$rootOU" | Out-Null
    Write-Host "  Created and linked GPO: $gpoName"
}

Write-Host "`nDone. Verify with:  Get-ADUser -Filter * -SearchBase '$rootOU' | Select Name, SamAccountName" -ForegroundColor Green
Write-Host "Reminder: drive-mapping GPO (Group Policy Preferences) is configured in the GUI - see the guide." -ForegroundColor Yellow
