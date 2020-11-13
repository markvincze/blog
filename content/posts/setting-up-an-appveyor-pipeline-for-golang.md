+++
title = "Setting up an AppVeyor pipeline for Golang"
description = "This post gives and Introduction to setting up a continuous delivery pipeline for a Golang-based project in AppVeyor."
date = "2016-07-16T15:47:28.0000000"
tags = ["golang", "appveyor"]
+++

Recently at my day job I have been working on a [Golang-based application](https://github.com/Travix-International/Travix.Core.Adk), for which I wanted to set up an automated CD pipeline for building and releasing. Our application is a command line tool, so the release part is basically copying and uploading the binaries to a specified location.

Since I have been using AppVeyor for my .NET Core projects ([Stubbery](https://github.com/markvincze/Stubbery) and [RestApiHelpers](https://github.com/markvincze/rest-api-helpers)), and it's working really nicely, it seemed to be the obvious choice for Golang as well.

I did a quick Google search, and was surprised, because I didn't find any guides about setting this up. On the other hand, I found the `appveyor.yml` file of another [open-source Golang-project](https://github.com/oschwald/maxminddb-golang/blob/master/appveyor.yml), which looked rather simple, so I decided to try to set up my pipeline based on that. It turned out to be even simpler than what I expected.

## Setting up the build

In this section I'll describe a sample AppVeyor configuration, which is enough to build a Golang application.
(I'll only focus on the parts relevant to Golang.)

We have two different options to configure AppVeyor projects: one is two use a management website to set the different properties of the project, and the other is to put an `appveyor.yml` file at the root of our repository, which describes the same settings, and is automatically processed by AppVeyor.

I chose the latter approach, because it keeps the configuration close to the source code, this way it's easy to track its history, and it can be part of pull requests. Furthermore, the `yml` file contains only the settings which are relevant for our project, so it's often quite small and easy to understand.

### The AppVeyor configuration

I'll show the relevant parts of the `appveyor.yml` file and describe them in detail.

### Basic settings

```yaml
version: 1.0.0.{build}

platform: x64

branches:
  only:
    - master
```

The version number can be customized to fit our needs, and it can be manually bumped when we are releasing a new version. The `{build}` argument is an internal environment variable of AppVeyor, which will be automatically bumped on every build.

I configured my pipeline to be triggered only by pushes to the master branch, this can be modified in the `branches` section.

### Cloning and prerequisites

```yaml
clone_folder: c:\gopath\src\github.com\account\myproject

environment:
  GOPATH: c:\gopath

install:
  - echo %PATH%
  - echo %GOPATH%
  - set PATH=%GOPATH%\bin;c:\go\bin;%PATH%
  - go version
  - go env
```

The `clone_folder` property specifies the location our repo gets cloned to. This is important in the Golang ecosystem, since we usually want our projects to reside under the folders specified by either the `GOROOT` or the `GOPATH` environment variables. Hence we are setting that root folder as the value of the `GOPATH` variable in the `environment` section.

It turns out that the default AppVeyor agent image — among [many other technologies](https://www.appveyor.com/docs/installed-software) — comes with Go preinstalled, so in the `install` section we don't have to do any real installation.  
However, it's still a good idea to print out some dianostic information about our Go environment, which can help troubleshooting if the build goes south. We also add `%GOPATH%\bin` and `C:\go\bin` to the PATH, so we can use the go toolchain in our build scripts without specifying full paths.

### Building

Depending on how complicated our build is, we can either use a `go build` command directly in our `appveyor.yml`.

```yaml
build_script:
  - go build -o buildOutput\myapp -i .
```

Or, if we have a more complicated build (for example in my case we are cross-compiling the application for three different platforms), it's a better idea to put a script doing the build in our repository (I used PowerShell), and execute that in the pipeline.

```yaml
build_script:
  - ps: .\build.ps1
```

The next thing to specify is the list of files to use during the deployment. These have to be added to the `artifacts` section.

```yaml
artifacts:
  - path: buildOutput/myapp
    name: binary
```

We can list multiple files if we are generating more than one build output.

### Deployment

The last part is doing the actual deployment of our artifacts.  
Now this part will completely depend on the way we want to release are application. I only investigated using GitHub Releases, since that was perfect for my purposes, but AppVeyor has built-in support for numerous other systems (Amazon S3, different Azure services, NuGet, etc.). And I'm sure we can roll our own deployment script as well.

Here is an example for setting up the `deploy` section for GitHub Releases.

```yaml
deploy:
  release: myapp-$(appveyor_build_version)
  description: 'This is a release of my awesome application.'
  provider: GitHub
  auth_token:
    secure: ZkOJAiZBmapKpbiqovaofs+W0foBWaV9Jom4yBYzcRKlAk4Bee+5b7t+5LrQRVn8
  artifact: binary # This is the name we specified in the artifacts section.
  draft: false
  prerelease: false
  on:
    branch: master
```

Where the value of the `secure` property is a **Personal access token** we have to set up on the [settings page](https://github.com/settings/tokens) of GitHub.

One gotcha is that we shouldn't add the raw value of our token to the `appveyor.yml`, since then anyone would be able to read it from our repository (and GitHub is actually smart enough to notice that we erroneously added the plain value of a token to our repo and disables it automatically).

We should rather encrypt it with the **Encrypt data** option on the AppVeyor management site, and use that value instead. AppVeyor will recognize that its an encrypted token and decrypt it automatically.

So this is the complete `appveyor.yml` file we have to put at the root of our repository to get a basic build working. (More details about all the settings can be found in [official documentation](https://www.appveyor.com/docs).)

```yaml
version: 1.0.0.{build}

platform: x64

branches:
  only:
    - master

clone_folder: c:\gopath\src\github.com\account\myproject

environment:
  GOPATH: c:\gopath

install:
  - echo %PATH%
  - echo %GOPATH%
  - set PATH=%GOPATH%\bin;c:\go\bin;%PATH%
  - go version
  - go env

build_script:
  - go build -o buildOutput\myapp -i .

build_script:
  - ps: .\build.ps1

artifacts:
  - path: buildOutput/myapp
    name: binary

deploy:
  release: myapp-$(appveyor_build_version)
  description: 'This is a release of my awesome application.'
  provider: GitHub
  auth_token:
    secure: FW3tJ3fMncxvs58/ifSP7w+kBl9BlxvRMr9liHmnBs14ALRG8Vfyol+sNhj9u2JA
  artifact: binary # This is the name we specified in the artifacts section.
  draft: false
  prerelease: false
  on:
    branch: master
```

I think this example shows that setting up a build pipeline for a Golang project in AppVeyor is really simple, and I hope this post will save some time for people getting started with continuous delivery in Golang.
