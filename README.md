# Jenkins with Docker-in-Docker (DinD)

This project runs Jenkins in Docker and allows Jenkins pipelines to build and run Docker containers using a separate Docker-in-Docker (DinD) service.

## Project Structure

```text
.
├── .env.example
├── Dockerfile
├── compose.yaml
├── nginx/
│   └── jenkins.conf.template
├── setup-nginx.sh
└── README.md
```

## Prerequisites

Make sure you have installed:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine
- [Docker Compose](https://docs.docker.com/compose/install/) v2 or later
- A terminal or command prompt

Verify your installation:

```bash
docker --version
docker compose version
```

## Configuration

### Jenkins Dockerfile

The `Dockerfile` uses the official Jenkins image:

```dockerfile
FROM jenkins/jenkins:2.580.1-jdk21
```

It installs the Docker CLI and the following Jenkins plugins:

- `docker-workflow`
- `json-path-api`

The Docker CLI allows Jenkins pipelines to communicate with the DinD service.

### Docker Compose services

The `compose.yaml` file defines two services:

| Service | Description |
|---|---|
| `jenkins` | Jenkins controller with Docker CLI |
| `docker` | Docker-in-Docker daemon for running containers |

It also creates two named volumes:

| Volume | Purpose |
|---|---|
| `jenkins-data` | Stores Jenkins configuration, jobs, plugins, and build data |
| `jenkins-docker-certs` | Stores TLS certificates for secure communication with the Docker daemon |

### Domain configuration

The domain and Let's Encrypt email address are read from `.env`:

| Variable | Description |
|---|---|
| `JENKINS_DOMAIN` | Public domain name pointing to this server, e.g. `jenkins.example.com` |
| `LETSENCRYPT_EMAIL` | Email address for Let's Encrypt expiry and account notices |

`setup-nginx.sh` renders `nginx/jenkins.conf.template` with these values into `/etc/nginx/conf.d/jenkins.conf`.

Both services connect to the same bridge network named `jenkins`.

## Getting Started

### 1. Clone or download the project

Make sure `Dockerfile`, `compose.yaml`, and `README.md` are in the same directory.

### 2. Configure the domain

Create `.env` from the example and set your domain and email:

```bash
cp .env.example .env
```

Make sure the domain's DNS record points to this server and that ports `80` and `443` are reachable.

### 3. Build and start the containers

Run:

```bash
docker compose up -d --build
```

This command builds the custom Jenkins image and starts both services.

### 4. Install nginx and certbot (Ubuntu)

Run the setup script on the host:

```bash
./setup-nginx.sh
```

It installs nginx from the official nginx.org repository and certbot, requests a Let's Encrypt certificate for `JENKINS_DOMAIN`, and configures nginx as an HTTPS reverse proxy to Jenkins on `127.0.0.1:8080`.

Certificates are renewed by certbot's systemd timer, and nginx is reloaded after each renewal. The script is safe to re-run; it skips the certificate request when one already exists.

### 5. Check container status

```bash
docker compose ps
```

View the Jenkins logs:

```bash
docker compose logs -f jenkins
```

View the Docker daemon logs:

```bash
docker compose logs -f docker
```

Press `Ctrl+C` to stop following the logs. This does not stop the containers.

### 6. Retrieve the initial administrator password

Run:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Copy the password displayed in your terminal.

### 7. Open Jenkins

Visit `https://<JENKINS_DOMAIN>` (or http://localhost:8080 from the server itself).

Enter the initial administrator password and follow the setup wizard.

Install the recommended plugins or select the plugins you need, then create your administrator account.

When asked for the Jenkins URL (or later under **Manage Jenkins → System → Jenkins URL**), enter `https://<JENKINS_DOMAIN>/`.

## Verify Docker Access from Jenkins

After completing the Jenkins setup, create a Pipeline job and use the following pipeline script:

```groovy
pipeline {
    agent any

    stages {
        stage('Check Docker') {
            steps {
                sh 'docker version'
                sh 'docker info'
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "FROM alpine:3.22" > Dockerfile
                    echo 'CMD ["echo", "Hello from Docker"]' >> Dockerfile
                    docker build -t jenkins-docker-test .
                '''
            }
        }

        stage('Run Docker Container') {
            steps {
                sh 'docker run --rm jenkins-docker-test'
            }
        }
    }
}
```

Run the pipeline. If the Docker client can connect to the daemon, build the image, and run the test container, Docker integration is working.

## Common Commands

Start the services:

```bash
docker compose up -d
```

Rebuild the Jenkins image and start the services:

```bash
docker compose up -d --build
```

Stop the services:

```bash
docker compose down
```

Restart the services:

```bash
docker compose restart
```

View running containers:

```bash
docker compose ps
```

Follow Jenkins logs:

```bash
docker compose logs -f jenkins
```

Open a shell in the Jenkins container:

```bash
docker exec -it jenkins bash
```

Check Docker connectivity from Jenkins:

```bash
docker exec jenkins docker version
```

## Updating the Configuration

After changing the `Dockerfile`, rebuild and recreate the Jenkins container:

```bash
docker compose up -d --build
```

Your Jenkins configuration is retained in the `jenkins-data` named volume.

After changing `JENKINS_DOMAIN` in `.env` or editing `nginx/jenkins.conf.template`, re-run the setup script:

```bash
./setup-nginx.sh
```

If you change the Docker daemon or TLS configuration, ensure the Jenkins environment variables and certificate mounts remain consistent.

## Security Notes

- The DinD service requires privileged mode for this configuration. It grants substantial access to the host kernel.
- Restrict access to the Jenkins web interface and administrator credentials.
- The Docker daemon uses TLS on port `2376`.
- Avoid exposing the Docker daemon to untrusted networks. If you do not need to control the DinD daemon from your host, remove the host port mapping for `2376`.
- Do not store passwords, access tokens, or other secrets directly in your pipeline scripts.
- Use this configuration on a trusted development or CI machine. Review the security requirements before using it in production.

## Data Persistence

The named volumes preserve Jenkins data and Docker TLS client certificates across container restarts.

To stop and remove the containers without deleting persistent data:

```bash
docker compose down
```

**Warning:** The following command also deletes the named volumes and their stored data:

```bash
docker compose down -v
```

Only use it when you intentionally want to remove the stored Jenkins configuration and related volume data.

## Troubleshooting

### Jenkins is not starting

Check the logs:

```bash
docker compose logs jenkins
```

### Docker commands fail inside Jenkins

Check that both services are running:

```bash
docker compose ps
```

Check Docker daemon logs:

```bash
docker compose logs docker
```

Verify that the Jenkins service has these environment variables:

```text
DOCKER_HOST=tcp://docker:2376
DOCKER_CERT_PATH=/certs/client
DOCKER_TLS_VERIFY=1
```

Also confirm that the Docker client certificate volume is mounted read-only at `/certs/client`.

### Jenkins cannot be accessed

Confirm that port `8080` is published and not being used by another application:

```bash
docker compose ps
```

Then open http://localhost:8080 again.

## References

- [Jenkins Docker installation guide](https://www.jenkins.io/doc/book/installing/docker/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Docker-in-Docker image](https://hub.docker.com/_/docker)
- [Docker CLI documentation](https://docs.docker.com/reference/cli/docker/)
