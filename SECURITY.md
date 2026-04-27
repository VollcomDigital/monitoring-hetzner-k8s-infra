# Security Policy

## Supported versions

Security fixes are applied to the default branch (`main`). Tags or release branches are only supported when explicitly documented in this repository.

## Reporting a vulnerability

Please **do not** open public issues, discussions, or pull requests for undisclosed security vulnerabilities.

**Preferred:** Use **private vulnerability reporting** for this GitHub repository when it is enabled: open the **Security** tab and choose **Report a vulnerability**. That keeps details non-public until a fix is ready.

If private reporting is not available, contact the **Vollcom Digital** maintainers through a **private** channel (for example, security or engineering contact your organization uses for this GitHub org). Include:

- A short description of the issue and its impact  
- Steps to reproduce (or proof-of-concept), if safe to share  
- Affected components (e.g. Terraform modules, Helm charts, manifests)  
- Whether you believe the issue is already exploited in the wild  

We aim to acknowledge receipt within a few business days and will coordinate disclosure and fixes with you.

## Scope

In scope: security defects in the **code and configuration shipped in this repository** (Terraform, Kubernetes manifests, Helm values, scripts) when used as documented.

Out of scope: operational mistakes (exposed API tokens in public repos, unsecured clusters), vulnerabilities in third-party software or cloud providers, or issues only reproducible with heavily customized forks unless they stem from this repo’s defaults.

## Disclosure

We ask that you **do not** publish details until we have released a fix or agreed on a disclosure timeline. Credit in release notes or advisories can be discussed when reporting.
