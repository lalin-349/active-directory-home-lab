# Active Directory Home Lab

A small Windows domain I built in VirtualBox to practice the everyday work of a helpdesk or junior sysadmin: user accounts, group-based access, shared folders and Group Policy.

## Setup

| Machine | OS | Role | IP |
|---|---|---|---|
| DC01 | Windows Server 2025 | Domain controller + DNS for `lab.local` | 192.168.10.10 |
| CLIENT01 | Windows 11 Enterprise | Domain-joined workstation | 192.168.10.20 |

Both machines sit on an isolated VirtualBox internal network called `labnet`. DC01 also has a NAT adapter so it can reach the internet for updates and DNS forwarding.

## What's in the domain

- A `LabCorp` OU with IT, HR, Sales, Computers and Groups inside it
- 7 users, with access handed out through groups (AGDLP), not directly to people
- 4 shared folders: Company, IT, HR, Sales
- One GPO: "Sales - Restrict Control Panel"

All of it was created with [`scripts/Populate-AD-Lab.ps1`](scripts/Populate-AD-Lab.ps1). More detail in [`docs/lab-design.md`](docs/lab-design.md).

## Tickets I worked through

1. **Password reset.** Reset a user's password on DC01 and forced a change at next login.
2. **Access denied on the HR share.** A user outside HR tried `\\DC01\HR` and was blocked. Checked the group membership to confirm why.
3. **Checking a GPO.** Ran `gpupdate /force` and `gpresult /r` on CLIENT01 to see which policies applied.
4. **Deleted user restored.** Deleted a user, confirmed the login failed, then brought the account back from the AD Recycle Bin.

Screenshots for each are in [`screenshots/04-scenarios`](screenshots/04-scenarios).

## Things that went wrong

The most useful part of the build. Wrong adapter names, a mismatched network name, DNS pointing the wrong way. Each one is written up in [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md).

## Repo layout

```
scripts/       Populate-AD-Lab.ps1
screenshots/   01-build, 02-structure, 03-client-join, 04-scenarios
docs/          lab-design.md, troubleshooting-log.md
```

ISOs and VM files are not included.
