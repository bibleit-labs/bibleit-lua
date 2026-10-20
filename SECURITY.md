# Security

Do not include credentials, tokens or private account details in public issues.
Use GitHub private vulnerability reporting on this repository for security
reports when available; otherwise contact the maintainers privately through
the repository's published contact channels.

The SDK uses explicit credentials and verified HTTPS, blocks redirects and does
not retry requests. Applications own credential storage, callback-state checks
and SSH host-key verification. Custom transport/executor implementations are
trusted application code and must preserve these requirements.
