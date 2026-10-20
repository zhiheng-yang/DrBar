# Security

DrBar runs in the App Sandbox. It makes one kind of network request, downloading ccfddl's data
(`https://ccfddl.com/conference/allconf.yml` and `https://ccfddl.com/conference/allacc.yml`), stores
its data in its own container, and controls Mail only to send an email the user has just confirmed.

## Reporting a vulnerability

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/zhiheng-yang/DrBar/security/advisories/new),
not in a public issue. You will get an answer within a week. Fixes go into the latest release.
