# Website

Notes below on using Git Secrets to prevent token commits.

## Git Secrets

https://github.com/awslabs/git-secrets

After installation, use these lines to setup:
git secrets --add "dt0c 01" (without the space :) )
git secrets --add -a --literal "dt0c01.{80}"
