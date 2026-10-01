# shellcheck shell=bash
# shellcheck disable=SC2034  # read by guard-lib.sh and the hooks that source it
# Pattern sets and path exemptions for .githooks/pre-commit and .githooks/pre-push, sourced by .githooks/guard-lib.sh.
# Each pattern is a POSIX ERE, matched case-insensitively against each added line. .gitleaks.toml carries the same
# patterns; tests/test-pattern-sync.sh checks that the two stay in step.
#
# Replace the IDENTITY_PATTERNS placeholders with your organisation's markers, or keep them and put your markers in
# the optional, gitignored .githooks/identity-patterns.local instead, one ERE per line. The second way screens a
# public fork for names it must not publish without publishing the list. Secret-shaped literals of your own, such as
# account IDs, go in .githooks/always-patterns.local the same way.

# Secret-shaped values: they bite on every path.
ALWAYS_PATTERNS=(
    # A 12-digit number within 24 characters of the word "account", on either side, and an ARN carrying one
    'account[^0-9]{0,24}[0-9]{12}([^0-9]|$)'
    '(^|[^0-9])[0-9]{12}[^0-9]{1,24}account'
    'arn:aws[a-z-]*:[^:]*:[^:]*:[0-9]{12}:'

    # ECR registry hostnames
    '[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com'

    # Bedrock application inference profile IDs
    'application-inference-profile/[a-z0-9]{10,16}'

    # SSH private key markers
    '-----BEGIN.*PRIVATE KEY-----'

    # Tokens / PATs
    'YOUR_NUGET_PAT'
)

# Organisation and personal identity markers: placeholders to replace with your own.
IDENTITY_PATTERNS=(
    # SSO portal
    'yourorg\.awsapps\.com'

    # Active Directory
    'DC=your-domain'

    # Organisation
    'yourorg'
    'your-company\.com'
    'your-stage\.com'
    'your-dev-server'
    'your-prod-server'
    'your-company'
    'internal-project-1'
    'internal-project-2'
    'internal-project-3'
    'internal-project-4'
    'internal-project-5'

    # Personal
    'YourGitHubUser'
    '@your-company\.com'
    '@your-email\.co\.uk'
    'your\.name'
    '/Users/yourusername/'
)

# Paths exempt from the IDENTITY_PATTERNS placeholders: files whose history names a placeholder to document it (older
# versions of the pattern-sync test grepped for them, and the whisper doc used one in its examples), so a
# full-history push needs the exemption. identity-patterns.local still bites there.
IDENTITY_EXEMPT_RE='^docs/whisper-prompt-technique\.md$|^tests/test-pattern-sync\.sh$'

# Paths exempt from identity-patterns.local. This ERE never matches, since nothing follows the end of a path: no path
# is exempt.
LOCAL_IDENTITY_EXEMPT_RE='^$.'

# Patterns of identity-patterns.local this repository disregards on every path, for a marker that is its own public
# identity. Each entry is the exact text of one line of that list; an entry that matches no line drops nothing, so a
# changed pattern bites again. always-patterns.local and the tracked patterns cannot be opted out of. None here.
LOCAL_IDENTITY_IGNORE=()

# Paths the built-ins pass skips. This ERE never matches either, so gitleaks' built-in rules scan every path. To clear
# a built-in false positive, replace it with an anchored alternation of the paths to exempt, in a reviewed commit.
BUILTINS_EXEMPT_RE='^$.'

# Paths exempt from ALWAYS_PATTERNS, for files that must carry secret-shaped dummy values. None: this ERE never
# matches. always-patterns.local and the identity patterns would still apply to such a path.
ALWAYS_EXEMPT_RE='^$.'
