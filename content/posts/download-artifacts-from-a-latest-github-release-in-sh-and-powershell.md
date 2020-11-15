+++
title = "Download artifacts from a latest GitHub release with bash and PowerShell"
slug = "download-artifacts-from-a-latest-github-release-in-sh-and-powershell"
description = "Downloading artifacts for a particular GitHub release is easy, but to download artifacts from the latest release we need some extra steps in our scripts."
date = "2016-07-09T22:45:38.0000000"
tags = ["github", "bash", "powershell"]
ghostCommentId = "ghost-23"
+++

[Releases](https://help.github.com/articles/about-releases/) is an important feature of GitHub, with which we can publish packaged versions of our project.

The source code of our repository is packaged with every release, and we also have the possibility to upload some artifacts alongside, for example the binaries or executables that we've built.

Lately I've been working on an [application](https://github.com/Travix-International/Travix.Core.Adk) for which the releases are published on GitHub, and I wanted to create an install script which always downloads the latest release.

It turned out that downloading the artifacts for a specific version is easy, we can simply build an URL with the version number to access the artifact. However, there is no direct URL to download artifacts from the *latest* release, so we need a bit of logic in our scripts to do that.

## Link structure

We can access a particular release with a URL like `https://github.com/account/project/releases/tag/project-1.0.5`. (The part after `tag/` is the what we specified when we created the release.)

Artifacts from this particular release can be downloaded with the URL `https://github.com/account/project/releases/download/project-1.0.5/myArtifact.zip`.

And there is this URL, which which always takes us to the latest release of a project: `https://github.com/account/project/releases/latest`.  
It seemed logical that there should also be a way to also download artifacts from the latest release, so I [asked around](http://stackoverflow.com/questions/38283074/is-there-a-way-to-download-an-artifact-from-the-latest-release-on-github), but it turns out, there is no URL available to do that directly.

## Getting the latest tag

As it's pointed out in the above SO answer, we can send a GET request to the URL `https://github.com/account/project/releases/latest` and set the `Accept` header to `application/json` (without this we get back the HTML page), we get information about the latest release in the following format.

```json
{"id":3622206,"tag_name":"project-1.0.5"}
```

This is the information we want, now we can use this in our scripts to determine the latest version and build our download links.

## Use the version in scripts

### Shell script

We can get the information about the latest release with `curl`.

```bash
LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' https://github.com/account/project/releases/latest)
```

Then we have to extract the value of the `tag_name` property, I used a regex for this with `sed`.

```bash
# The releases are returned in the format {"id":3622206,"tag_name":"hello-1.0.0.11",...}, we have to extract the tag_name.
LATEST_VERSION=$(echo $LATEST_RELEASE | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')
```

Then we can build our download URL for a certain artifact.

```bash
ARTIFACT_URL="https://github.com/account/project/releases/download/$LATEST_VERSION/myArtifact.zip"
```

### PowerShell

The latest release can be retrieved with `Invoke-WebRequest`.

```powershell
$latestRelease = Invoke-WebRequest https://github.com/account/project/releases/latest -Headers @{"Accept"="application/json"}
```

Then we have to extract the value of the `tag_name` property. Since PowerShell has built-in support for parsing Json, we don't have to use a regex.

```powershell
# The releases are returned in the format {"id":3622206,"tag_name":"hello-1.0.0.11",...}, we have to extract the tag_name.
$json = $latestRelease.Content | ConvertFrom-Json
$latestVersion = $json.tag_name
```

Then we can build our download URL for a certain artifact.

```powershell
$url = "https://github.com/account/project/releases/download/$latestVersion/myArtifact.zip"
```
