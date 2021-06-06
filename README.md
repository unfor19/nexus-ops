# nexus-ops

![nexus-ops-cover.png](https://d33vo9sj4p3nyc.cloudfront.net/nexus-ops/nexus-ops-cover.png)

Provision [Nexus Repository Manager](https://hub.docker.com/r/sonatype/nexus3/) (NXRM) Docker container.

All scripts are written in [Bash](https://www.gnu.org/software/bash/), and the [Nexus REST API](https://help.sonatype.com/repomanager3/rest-and-integration-api) calls are made with [curl](https://curl.se/). Check the [provision/entrypoint.sh](https://github.com/unfor19/nexus-ops/blob/master/provision/entrypoint.sh) to learn more about the provisioning process.

## Goals

- Hands-on experience with Nexus Repository Manager
- Provision a ready-to-go Nexus Repository Manager container
- Use Nexus Repository Manager as part of a CI/CD workflow

## Requirements

- Hardware
  - [CPU](https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-CPU): Minimum 4, Recommended 8+
  - [Memory](https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-GeneralMemoryGuidelines): Minimum 8GB, Recommended 16GB+
- [Docker](https://docs.docker.com/get-docker/) (Windows users should use [WSL2 backend](https://docs.docker.com/docker-for-windows/wsl/))
- Set Nexus's Repository as a trusted Docker repository ([insecure registry](https://docs.docker.com/registry/insecure/)) - Either edit `$HOME/.docker/config.json` or the **Docker Engine**, and then restart the Docker Daemon.
   ```json
   "insecure-registries": [
      "localhost:8081"
   ],
   ```
   ![nexus-ops-insecure-registries.png](https://d33vo9sj4p3nyc.cloudfront.net/nexus-ops/nexus-ops-insecure-registries.png)

## Quick Start

The provisioning script [provision/entrypoint.sh](https://github.com/unfor19/nexus-ops/blob/master/provision/entrypoint.sh) performs the following tasks

1. Changes the [initial random password](https://help.sonatype.com/repomanager3/system-configuration/access-control/users) that is in `/nexus-data/admin.password` to `admin`
2. Enables [anonymous access](https://help.sonatype.com/repomanager3/system-configuration/user-authentication/anonymous-access) - allows anonymous users to access `localhost:8081` with `READ` permissions
3. Adds [Docker Bearer Token Realm](https://help.sonatype.com/repomanager3/formats/docker-registry/docker-authentication#DockerAuthentication-AuthenticatedAccesstoDockerRepositories) - allows anonymous pulls from local Nexus registry `localhost:8081`
4. Creates two Docker repository of type [proxy](https://help.sonatype.com/repomanager3/formats/docker-registry/proxy-repository-for-docker)
   1. `docker-hub` - DockerHub
   2. `docker-ecrpublic` - AWS ECR Public
5. Creates a Docker repository of type [group](https://help.sonatype.com/repomanager3/formats/docker-registry/grouping-docker-repositories)
   1. `docker-group` - The above Docker repositories are members of this Docker group

### Docker Run

```bash
# ulimit - https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-Docker
# 8081 - Nexus
# 8082 - docker-group
docker run -d \
   --ulimit nofile=65536:65536 \
   -p 8081:8081 \
   -p 8082:8082 \
   --name nexus "unfor19/nexus-ops"
```

---

## How It Works

Nexus's Repository will serve as a "cache server", here's the logic -

1. Each `docker pull` goes through `localhost:8082/repository/docker-group` and gets the and then redirected to the relevant `docker-proxy`.
   - DockerHub - `http://localhost:8081/repository/docker-hub/v2/`
   - AWS ECR Public - `http://localhost:8081/repository/docker-ecrpublic/v2/`
2. If the Docker image **exists**, Docker Client pulls it from NXRM
   - It is recommended to re-tag the image from `localhost:8082/nginx` to `nginx`, so the references in your Dockerfile can remain `nginx`.
3. If the Docker image **doesn't exist**, NXRM pulls it from DockerHub and save it in Nexus's Repository, following that, the Docker Client pulls the image from NXRM.

---

## Run Nexus Locally (UI)

This is the exact same process that was done in the `Quick Start` section, only now we're going to do it manually in the UI. The purpose of this section is to help Nexus newbies (like me) to get familiar with the UI.

<details>

<summary>Expand/Collapse</summary>

For the sake of simplicity, I **won't be using** Docker volumes for [Persistent Data](https://github.com/sonatype/docker-nexus3#user-content-persistent-data). The `nexus-data` is generated at the top layer of Nexus's container, so if the container is removed (not stopped) all the data in `nexus-data` is lost, including the Docker images.

1. Run Nexus locally
    ```bash
    NEXUS_VERSION="3.30.1" && \
   # ulimit - https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-Docker
    # 8081 - Nexus
    # 8082 - docker-group
    docker run -d \
      --ulimit nofile=65536:65536 \
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

---

### Setup Docker Repository With Nexus

1. Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create DockerHub repository

   - Recipe Type: **docker (proxy)**
   - Name: `docker-hub`
   - Remote storage URL (DockerHub): `https://registry-1.docker.io`
   - Docker Index: **Use Docker Hub**

1. (Optional) Server Administration (Cogwheel) > [Repositories](http://localhost:8081/#admin/repository/repositories) > Create [AWS ECR Public](https://gallery.ecr.aws/) repository
   - Recipe Type: **docker (proxy)**
   - Name: `docker-ecr`
   - Remote storage URL (ECR): `https://public.ecr.aws`
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

</details>

---

### Test Locally

1. Pull relevant Docker images via `localhost:8082`
   ```bash
   docker pull localhost:8082/unfor19/alpine-ci:latest && \
   docker pull localhost:8082/ubuntu:20.04
   ```
2. Tag relevant images with `docker.io` or omit the prefix (like I did), that will mitigate the need to rename images to `localhost:8082`
   ```bash
   docker tag localhost:8082/unfor19/alpine-ci:latest unfor19/alpine-ci:latest && \
   docker tag localhost:8082/ubuntu:20.04 ubuntu:20.04
   ```
3. `docker build` - build the application, the Docker Daemon already pulled the required images to build the app.
   ```bash
   git clone https://github.com/unfor19/nexus-ops.git
   cd nexus-ops
   docker build -f Dockerfile.example -t unfor19/nexus-ops:example .
   ```
4. `test image`
   ```bash
   docker run --rm unfor19/nexus-ops:example
   # Miacis, the primitive ancestor of cats, was a small, tree-living creature of the late Eocene period, some 45 to 50 million years ago.

   # ^^ A random cat fact for each build
   ```

---

### Workflow (CI/CD)

I've added the [GitHub Action](https://github.com/features/actions) - [docker-release.yml](https://github.com/unfor19/nexus-ops/blob/master/.github/workflows/docker-latest.yml). If you check it out, you'll see the following [code snippet](https://github.com/unfor19/nexus-ops/blob/master/.github/workflows/docker-latest.yml#L15-L18)

```yaml
jobs:
  docker:
    name: docker
    runs-on: linux-self-hosted # <-- A label that I chose
```

As implied from the label **self-hosted**, I intend to run this workflow on my local machine. Adding your local machine as a self-hosted runner is quite simple.

1. GitHub Repository > Settings > Actions > Runners
2. Add Runner > Operating System: **Linux** (or any OS), Architecture: **X64**
3. Follow the steps in **Download**
4. Follow the steps in **Configure** > Follow the prompts and add a custom label when prompted
   ```bash
   Enter any additional labels (ex. label-1,label-2): linux-self-hosted
   ```
   A successful configuration should look like this
   ```
   ~/actions-runner $ ./config.sh --url https://github.com/unfor19/nexus-ops --token YOUR_TOKEN
   ...
   √ Settings Saved.
   
   ~/actions-runner $ ./run.sh

   √ Connected to GitHub

   2021-06-01 21:18:04Z: Listening for Jobs   
   ```

Go on and initiate a workflow; add some file, commit and push
```
touch some-file                   && \
git add some-file                 && \
git commit -m "added some file"   && \
git push
```

---

## Pull From Different Repositories

So far the examples showed how to use DockerHub, though the process is the same for AWS ECR, or any other container registry.

- Pull from DockerHub - [nginx:1.19-alpine](https://hub.docker.com/_/nginx?tab=tags&page=1&ordering=last_updated&name=1.19-alpine)

   ```bash 
   docker pull localhost:8082/nginx:1.19-alpine
   ```

- Pull from ECR - [nginx/nginx:1.19-alpine](https://gallery.ecr.aws/nginx/nginx)
  ```bash
  docker pull localhost:8082/nginx/nginx:1.19-alpine
  ```

---

## Same Tag Precedence

But what happens if both repositories hold images with the same tags? `owner/repository:tag`

We'll use `bitnami/kubectl:latest` which is named the same both in [DockerHub](https://hub.docker.com/r/bitnami/kubectl/tags?page=1&ordering=last_updated&name=latest) and [AWS ECR Public](https://gallery.ecr.aws/bitnami/kubectl)
```bash
docker pull localhost:8082/bitnami/kubectl:latest
```

Navigate to [http://localhost:8081/service/rest/repository/browse/**docker-hub**/v2/bitnami/kubectl/tags/](http://localhost:8081/service/rest/repository/browse/docker-hub/v2/bitnami/kubectl/tags/), as the link implies, the image was pulled from **DockerHub**.

To change this behavior, go to the [docker-group](http://localhost:8081/#admin/repository/repositories:docker-group)'s settings and change the order of **Members**

![nexus-ops-order-of-members.png](https://d33vo9sj4p3nyc.cloudfront.net/nexus-ops/nexus-ops-order-of-members.png)

After changing the order of Members -
1. [Invalidate cache](http://localhost:8081/#admin/repository/repositories:docker-group)

   ![nexus-ops-invalidate-cache.png](https://d33vo9sj4p3nyc.cloudfront.net/nexus-ops/nexus-ops-invalidate-cache.png)
2. Remove the existing image from local Docker Daemon cache
   ```bash
   docker rmi localhost:8082/bitnami/kubectl
   ```
1. Pull image again, this time it will be from ECR
   ```bash
   docker pull localhost:8082/bitnami/kubectl
   ```
1. Check results at [http://localhost:8081/service/rest/repository/browse/**docker-ecr**/v2/bitnami/kubectl/tags/](http://localhost:8081/service/rest/repository/browse/docker-ecr/v2/bitnami/kubectl/tags/)

---

## Known Caveats

- It is required to pull all relevant images **before** the build step. Retagging the images tricks the Docker Daemon to use existing images (`--pull missing`). This helps to avoid hitting DockerHub for each `pull`, though it means you need to prepare a list of images that should be pulled.

---

## References

- Cover image - [Hackerboy Emoticon](http://123emoji.com/hacker-boy-sticker-5682/)
- Cover image - [Nexus Logo](https://help.sonatype.com/docs/files/331022/34537964/3/1564671303641/NexusRepo_Icon.png)
- Cover image - Docker Logo - https://draw.io

## Authors

Created and maintained by [Meir Gabay](https://github.com/unfor19)

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/unfor19/nexus-ops/blob/master/LICENSE) file for details
