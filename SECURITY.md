# Security Policy

## Scope

This repository is a local-first development tool. It can execute agent-driven
code modification workflows against a local Flutter project, so please treat it
as sensitive development tooling.

## Supported Versions

Security fixes are provided on a best-effort basis for the latest mainline
version of the project.

## Reporting a Vulnerability

Please do not open public GitHub issues for security problems.

Instead, report vulnerabilities privately to the maintainers with:

- a clear description of the issue
- impact and attack conditions
- reproduction steps or a minimal proof of concept
- any suggested mitigation if you have one

We will review reports as quickly as possible and coordinate a fix before
public disclosure when appropriate.

## Operational Notes

- Do not expose the local server directly to the public internet.
- Review adapter behavior carefully before connecting real agent tooling.
- Be cautious when running the project against repositories containing secrets.
