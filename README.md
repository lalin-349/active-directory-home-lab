# Active Directory Home Lab

A small Windows domain I built in VirtualBox to practice everyday helpdesk and junior sysadmin work: user accounts, group-based access, shared folders and Group Policy.

## Setup

- DC01: Windows Server 2025, domain controller and DNS for `lab.local` (192.168.10.10)
- CLIENT01: Windows 11 Enterprise, joined to the domain (192.168.10.20)
- Both are on an isolated VirtualBox internal network called `labnet`. DC01 also has a NAT adapter for internet access.

## What's in the domain

- A `LabCorp` OU with IT, HR, Sales, Computers and Groups inside it
- 7 users, with access given through groups (AGDLP), not directly to people
- 4 shared folders: Company, IT, HR, Sales
- One GPO: "Sales - Restrict Control Panel"

All of it was created with [`scripts/Populate-AD-Lab.ps1`](scripts/Populate-AD-Lab.ps1). More detail in [`docs/lab-design.md`](docs/lab-design.md).

## Tickets I worked through

1. Password reset: reset a user's password on DC01 and forced a change at next login.
2. Access denied on the HR share: a user outside HR tried `\\DC01\HR` and was blocked. Checked group membership to confirm why.
3. Checking a GPO: ran `gpupdate /force` and `gpresult /r` on CLIENT01 to see which policies applied.
4. Deleted user restored: deleted a user, confirmed the login failed, then restored the account from the AD Recycle Bin.

Screenshots for each are in [`screenshots/04-scenarios`](screenshots/04-scenarios).

## Things that went wrong

Wrong adapter names, a mismatched network name, DNS pointing the wrong way. Each one is written up in [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md).

## Repo layout

```
scripts/       Populate-AD-Lab.ps1
screenshots/   01-build, 02-structure, 03-client-join, 04-scenarios
docs/          lab-design.md, troubleshooting-log.md
```

ISOs and VM files are not included.
