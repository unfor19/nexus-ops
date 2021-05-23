# nexus-ops

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (Windows users should use [WSL2 backend](https://docs.docker.com/docker-for-windows/wsl/))

## Usage

Nexus's Repository will serve as a "cache server", here's the logic -

1. Each `docker pull` goes through Nexus's Repository `localhost:8081`.
2. If the image exists, then pull it from there and re-tag it.
3. If the image doesn't exist, pull it from DockerHub and save it in Nexus's Repository, so the next pull won't hit DockerHub.

### Set Nexus's Repository As A Trusted Docker Repository

Either edit `$HOME/.docker/config.json` or the **Docker Engine**, and then restart the Docker Daemon.

```json
  "insecure-registries": [
    "localhost:8081"
  ],
```

![](nexus-ops-insecure-registries.png)

### Run Nexus Locally

For the sake of simplicity, I **won't be using** a Docker volumes for [Persistent Data](https://github.com/sonatype/docker-nexus3#user-content-persistent-data)

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

1. Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create DockerHub repository

   - Recipe Type: **docker (proxy)**
   - Name: `docker-hub`
   - Remote storage URL (DockerHub): `https://registry-1.docker.io`
   - Docker Index: **Use Docker Hub**

1. (Optional) Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create [AWS ECR Public](https://gallery.ecr.aws/) repository
   - Recipe Type: **docker (proxy)**
   - Name: `docker-ecr`
   - Remote storage URL (DockerHub): `https://public.ecr.aws`
     - [Docker login to AWS ECR](https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html):
       ```
       aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
       ```
   - Docker Index: **Use proxy registry**   

2. Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create repository

   - Recipe Type: **docker (group)**
   - Name: `docker-group`
   - HTTP: `8082` - Images are pulled from `http://localhost:8082`
   - Allow Anonymous docker pull: **check**
   - Member repositories > Members > Add `docker-hub`
   - Member repositories > Members > Add `docker-ecr`

3. [Realms](http://localhost:8081/#admin/security/realms) > **Add Docker Bearer Token Realm** - [Enables Anonymous Pulls](https://help.sonatype.com/repomanager3/system-configuration/user-authentication#UserAuthentication-security-realms)


### Workflow

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
   ```bash
   docker build -f Dockerfile.example -t unfor19/nexus-ops:example .
   ```
5. `docker push` - publish application to DockerHub
   ```bash
   docker push unfor19/nexus-ops:example
   ```

### Pull From Different Repositories

So far the examples showed how to use DockerHub, though the process is the same for AWS ECR, or any other container registry.

- Pull from DockerHub

   ```bash 
   docker pull localhost:8082/nginx:1.19-alpine
   ```

- Pull from ECR
  ```bash
  docker pull localhost:8082/nginx/nginx:1.19-alpine
  ```

### Same Tag Precedence

But what happens if both repositories hold images with the same tags? `owner/repository:tag`

We'll use `bitnami/kubectl:latest` which is named the same both in [DockerHub](https://hub.docker.com/r/bitnami/kubectl/tags?page=1&ordering=last_updated&name=latest) and [AWS ECR Public](https://gallery.ecr.aws/bitnami/kubectl)
```bash
docker pull localhost:8082/bitnami/kubectl:latest
```

Navigate to [http://localhost:8081/service/rest/repository/browse/**docker-hub**/v2/bitnami/kubectl/tags/](http://localhost:8081/service/rest/repository/browse/docker-hub/v2/bitnami/kubectl/tags/), as the link implies, the image was pulled from **DockerHub**.

To change this behavior, go to the [docker-group](http://localhost:8081/#admin/repository/repositories:docker-group)'s settings and change the order of **Members**

![nexus-ops-order-of-members](image_link)

After changing the order of Members -
1. [Invalidate cache](http://localhost:8081/#admin/repository/repositories:docker-group)

   ![nexus-ops-invalidate-cache.png](image_link)
2. Remove the existing image from local Docker Daemon cache
   ```bash
   docker rmi localhost:8082/bitnami/kubectl
   ```
1. Pull image again, this time it will be from ECR
   ```bash
   docker pull localhost:8082/bitnami/kubectl
   ```
1. Check results at [http://localhost:8081/service/rest/repository/browse/**docker-ecr**/v2/bitnami/kubectl/tags/](http://localhost:8081/service/rest/repository/browse/docker-ecr/v2/bitnami/kubectl/tags/)

## Known Caveats

- It is required to pull all relevant images **before** the build step. Retagging the images tricks the Docker Daemon to use existing images (`--pull missing`). This helps avoiding hitting DockerHub for each `pull`, though it means you need to prepare a list of images that should be pulled.

## Authors

Created and maintained by [Meir Gabay](https://github.com/unfor19)

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/unfor19/nexus-ops/blob/master/LICENSE) file for details
