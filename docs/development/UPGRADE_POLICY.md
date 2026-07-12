# Upgrade Policy

- Critical exploited vulnerabilities, revoked credentials and breaking deprecations are triaged the same day.
- Compatible security patches are grouped into the next weekly update batch.
- Minor SDK/tool changes are evaluated monthly.
- Major Flutter, Node, database or platform migrations use an isolated upgrade branch and staging proof.

Every proposal must identify the official release evidence, expected benefit, affected platforms, security/privacy/license/cost impact, rollback, and representative ERP checks. Lockfile-only mechanical updates and behavioral migrations remain separate commits. A newer version is not adopted when it provides no measurable reliability, security, speed or maintenance benefit.

Production promotion follows the normal release gate; automated dependency discovery may open proposals but must never deploy them.
