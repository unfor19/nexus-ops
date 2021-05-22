# nexus-ops

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (Windows users should use [WSL2 backend](https://docs.docker.com/docker-for-windows/wsl/))

## Usage

Nexus's Repository will serve as a "cache server", here's the logic -

1. Each `docker pull` goes through Nexus's Repository `localhost:8081`.
2. If the image exists, then pull it from there and re-tag it.
3. If the image doesn't exist, pull it from DockerHub and save it in Nexus's Repository, so the next pull won't hit DockerHub.

### Set Nexus's Repository As A Trusted Docker Repository. 

Either edit `$HOME/.docker/config.json` or the **Docker Engine**, and then restart the Docker Daemon.

```json
  "insecure-registries": [
    "localhost:8081"
  ],
```

![](nexus-ops-insecure-registries.png)

### Run Nexus Locally

For the sake of simplicity, I won't be using a Docker volumes.

1. Run Nexus locally
    ```bash
    NEXUS_VERSION="3.30.1" && \

    # 8081 - Nexus
    # 8082 - docker-group
    docker run -d \
        -p 8081:8081 \
        -p 8082:8082 \
        --name nexus "sonatype/nexus3:${NEXUS_VERSION}"
    ```
2. Get the initial admin password - exec into the Docker container `nexus` and execute
   ```bash
   cat /nexus-data/admin.password; echo # the extra echo makes it easier to copy paste
   
   # Example:
   # e9d3c296-c89a-41b3-bc44-1484c59c9f05
   ```
3. Login for the first time - http://localhost:8081
   - Username: `admin`
   - Password: `from-previous-step`
   - Set the new password to `admin` and `Enable anonymous access`

### Setup Docker Repository With Nexus

Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create repository

Recipe Type: **docker (proxy)**
Name: `docker-hub`
Remote storage URL: `https://registry-1.docker.io`
Docker Index: **Use Docker Hub**

Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create repository

Recipe Type: **docker (group)**
Name: `docker-group`
HTTP: `8082`
Allow Anonymous docker pull: **check**
Member repositories > Members > Add `docker-hub`

[Realms](http://localhost:8081/#admin/security/realms) > Add Docker Bearer Token Realm


The CI/CD pipeline should be as follows

1. Pull relevant Docker images via `localhost:8082`
   ```bash
   docker pull localhost:8082/unfor19/alpine-ci:latest && \
   docker pull localhost:8082/ubuntu:20.04
   ```
2. Tag relevant images with `docker.io`, that will mitigate the need to rename images to `localhost:8082`
   ```bash
   docker tag localhost:8082/unfor19/alpine-ci:latest unfor19/alpine-ci:latest && \
   docker tag localhost:8082/ubuntu:20.04 ubuntu:20.04
   ```
3. `docker build` - build the application, the Docker Daemon already pulled the required images to build the app.
   ```
   docker build -f Dockerfile.example -t unfor19/nexus-ops:example .
   ```
5. `docker push` - publish application to DockerHub
   ```
   docker push unfor19/nexus-ops:example
   ```

## Known Caveats

- It is required to pull all relevant images **before** the build step. Retagging the images tricks the Docker Daemon to use existing images (`--pull missing`). This helps avoiding hitting DockerHub for each `pull`, though it means you need to prepare a list of images that should be pulled.

## Authors

Created and maintained by [Meir Gabay](https://github.com/unfor19)

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/unfor19/nexus-ops/blob/master/LICENSE) file for details
