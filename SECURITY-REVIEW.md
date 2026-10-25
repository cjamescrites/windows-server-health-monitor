# Security Review

## Scope

This first version is intended for read-only diagnostics. It queries service status, fixed-disk capacity, and error-level entries in the Windows Application event log. It does not restart services, change permissions, write configuration, install updates, modify firewall rules, or transmit collected data.

## Why it is read-only

- Service checks use `Get-Service`; no service-control operation is called.
- Disk checks use `Get-CimInstance` to read `Win32_LogicalDisk` properties.
- Event checks use `Get-WinEvent` with a time-bounded filter and a maximum of 20 events.
- Output is displayed locally; the script does not upload reports or send telemetry.

Read-only does not mean risk-free: event messages can contain sensitive operational details, and querying logs still creates access and privacy considerations. Review output before sharing it.

## Permissions

Use the least-privileged account that can query the intended services, disks, and Application log. Local policy may restrict access to event details. Do not automatically run as Administrator or SYSTEM just because the script checks a server. If a permission error occurs, request the narrowest approved permission or use an authorized account.

## Data handling

- The report can include computer names, service names, application names, event IDs, timestamps, and event messages.
- Treat output as potentially sensitive operational information.
- Do not commit real production logs, hostnames, IP addresses, account names, tokens, or customer data to a public repository.
- Use synthetic examples in documentation and tests.

## If deployment is added later

1. **Never hard-code credentials.** Do not put AWS access keys, passwords, private keys, or tokens in scripts, workflow YAML, or repository files.
2. **Prefer short-lived identity.** For GitHub Actions deploying to AWS, evaluate GitHub OIDC federation with an AWS IAM role rather than long-lived access keys.
3. **Use least privilege.** Scope the role to only the required environment and deployment actions. Separate test and production permissions.
4. **Protect deployment paths.** Require pull-request review, branch protection, required status checks, and environment approvals for production.
5. **Protect secrets.** If a secret is unavoidable, store it in GitHub Actions secrets or an approved secret manager, limit who can change/read it, rotate it, and never print it to logs. OIDC is preferable when supported.
6. **Review third-party actions.** Pin actions to trusted versions or immutable commit SHAs according to organizational policy. Keep dependencies updated.
7. **Make rollback and recovery explicit.** Test deployment and rollback procedures in a non-production environment before production use.
8. **Audit changes.** Keep deployment logs and document who approved a release and what version was deployed.

## Residual risks and limitations

- Event messages may expose sensitive information.
- A service running does not prove the application is healthy.
- A disk free-space threshold is a simple warning signal, not a capacity forecast.
- Event-log retrieval can be affected by retention, permissions, and host configuration.
- The current GitHub Actions workflow validates code; it does not deploy to AWS or connect to a Windows server.
