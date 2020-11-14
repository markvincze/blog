+++
title = "Setting up a Travis-CI pipeline for Golang"
slug = "setting-up-a-travis-ci-pipeline-for-golang"
description = "This post gives and Introduction to setting up a continuous delivery pipeline for a Golang-based project in Travis-CI."
date = "2016-10-15T15:36:14.0000000"
tags = ["golang", "travis"]
+++

In the [previous post](/setting-up-an-appveyor-pipeline-for-golang) we looked at how we can set up a pipeline in AppVeyor for building and releasing a Golang application. Recently I made some changes to the project I'm working on, which [prevents the it to be cross-compiled on a Windows build agent](https://github.com/rjeczalik/notify/issues/108). After the change I was able to properly do the build only on an OSX machine.

This caused a problem for me, since AppVeyor only supports using a Windows machine as the build agent, so I wasn't able to properly cross compile the application any more.

Another really popular CI system for open source projects is Travis-CI. It works very similarly to AppVeyor, and its basic concepts are the same, but it's more tailored for building applications on a Linux-based environments. Luckily, it also supports using an OSX build agent, which is appropriate for my purposes.

Since I've written a summary about setting up a Golang pipeline for AppVeyor, it just seemed logical to do the same for Travis.

## Setting up the build

Similarly to AppVeyor, the normal way to use Travis to build a project is to include a yaml file at the root of the repository with the name `.travis.yml`, in which we can specify how we would like to compile our project, and we can also set up a configuration for releasing it.

### Environment

By default Travis is using an Ubuntu virtual machine to run the build. If Linux is an appropriate environment for your build, you can probably use the default settings. (I would only recommend using an OSX agent if there is a real need for it, since the Linux environment is faster and boots up much quicker.) You can find all the detailed information about the different environments you can use in [the documentation](https://docs.travis-ci.com/user/ci-environment/).

Since I wanted to use an OSX agent, I had to add the following line to the top of my `.travis.yml`.

```yaml
os: osx
```

The next thing to set up is the programming language which is needed to build our application. In the case of Go, the following settings are needed. 

```yaml
language: go

go:
- tip # The latest version of Go.
```

We can either set the version of the tools to a fix version, like `1.3`, or we can use `tip` to always get the latest version. We can find more options in [the docs](https://docs.travis-ci.com/user/languages/go).

### Build

The next step is to configure the actual build. Similarly to my example for AppVeyor, I'm not setting up the actual `go build` commands here, but I have a separate build script file in my repository, and I'm just calling that script from Travis.

```yaml
script:
- "./build.sh"
```

The script builds the source code and puts the output binary in the `bin` folder, it looks something like this (This is a simplified example.)

```bash
#!/bin/bash

go build -o bin/myawesomeapp -i .
``` 

### Deployment

The last thing to do is to configure how to deploy the application. This depends on what kind of project we're working on. The application I'm developing is a client side CLI tool. Of course the deployment would be very different for a — let's say — web application.

Similarly to AppVeyor, Travis has built-in deployment support for a [wide range](https://docs.travis-ci.com/user/deployment) of different systems. It includes support for GitHub Releases too, which I was already using.

To set up a GitHub release, we have to add the following section to our yaml.

```yaml
deploy:
  provider: releases
  skip_cleanup: true # Important, otherwise the build output would be purged.
  api_key:
    secure: lFGBaF...SJ1lDPDICY=
  file: bin/myawesomeapp
  on:
    repo: account/myawesomeproject
    tags: true # The deployment happens only if the commit has a tag.
``` 

#### GitHub authentication

There are [multiple ways](https://docs.travis-ci.com/user/deployment/releases/) to configure the `api_key` that will be used to authenticate AppVeyor to do the release, and we can also use a username/password combination (which is of course not a good idea if our yaml file will be public).

The simplest option (which is also recommended by the docs) is to [install the Travis CLI](https://github.com/travis-ci/travis.rb#installation), then step into the directory of our repository, and issue the `setup releases` command.

```bash
travis setup releases
```

This will prompt us to log into GitHub, then it generates an ApiKey, encrypts it and automatically adds it to our `.travis.yml` file.

The `file` property specifies the binary we want to upload to the GitHub release. We can also upload multiple files.

```yaml
  file:
    - file1
    - file2
    - file3
```

In the `repo` field we have to enter our GitHub account name, and the name of our project (basically the route in the URL if we open our repository on GitHub).

And if we set `tags` to true, then the deployment only happens for commits which have tags, and the name of the release will be the name of the tag. This is nice if we would like to explicitly control when we're releasing and what version number we want to use, which is a good opportunity to enforce conscious semantic versioning.

## Full example

This is the full `.travis.yml` file we have to put into our repo to get a build and release working.

```yaml
os: osx # Only use OSX if it's really needed!

language: go

go:
- tip # The latest version of Go.

script:
- "./build.sh"

deploy:
  provider: releases
  skip_cleanup: true # Important, otherwise the build output would be purged.
  api_key:
    secure: lFGBaF...SJ1lDPDICY=
  file: bin/myawesomeapp
  on:
    repo: account/myawesomeproject
    tags: true # The deployment happens only if the commit has a tag.
```

With this configuration the build itself runs for every commit and PR (which is nice, because we see if everything compiles fine), but the deployment only happens when we actually push a tag as well containing the version number of the new release.

Setting up Travis turned out to be a very similar experience to using AppVeyor, so the decision whether to use one or the other boils down to whether a Windows or a Linux (or OSX) build environment is more appropriate for our scenario.
