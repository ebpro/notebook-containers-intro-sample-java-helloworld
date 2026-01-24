# Self-hosted Runner Setup (Ubuntu example)

This document describes a minimal, secure setup for a self-hosted GitHub Actions runner intended to build Docker images.

Prerequisites
- Ubuntu 22.04 LTS (or similar Linux)
- Sufficient RAM: 8–32GB (use >=16GB for Graal builds)
- Disk: 50GB+ available

Steps
1. Create runner on GitHub
   - Repository Settings → Actions → Runners → New self-hosted runner
   - Choose labels (e.g. `self-hosted`, `Linux`, `X64`, `docker`)
   - Copy registration token and instructions.

2. Install Docker and Buildx

```bash
sudo apt update
sudo apt install -y docker.io git curl
sudo usermod -aG docker $USER
newgrp docker
# enable buildx
docker buildx create --use
```

3. Install and configure the Actions runner

```bash
# run as a dedicated user (recommended)
sudo adduser --disabled-password --gecos "" gha-runner
sudo su - gha-runner
mkdir actions-runner && cd actions-runner
# download runner archive (replace version as appropriate)
curl -O -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.308.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.308.0.tar.gz
# register the runner (replace URL and TOKEN)
./config.sh --url https://github.com/OWNER/REPO --token YOUR_TOKEN --labels self-hosted,Linux,X64,docker
# install as a service
sudo ./svc.sh install
sudo ./svc.sh start
```

4. Security recommendations
- Run the runner under a dedicated user with minimal privileges.
- Limit runner usage to trusted repositories or runner groups.
- Do not expose repository secrets to runs triggered by forked PRs.
- Enable automatic OS patching and monitor logs (`/var/log/syslog`, `docker logs`).
- Consider ephemeral runners for heavy/unsafe workloads (e.g., spawn runners on demand).

5. Maintenance
- Periodically prune Docker images and volumes to free disk:
  `docker system prune -a --volumes --force`
- Rotate registration tokens if a runner is compromised.

Notes
- For Kubernetes: consider using `actions-runner-controller` to manage ephemeral runners.
- For multi-arch builds: enable `binfmt` and use buildx with cache exporters.
