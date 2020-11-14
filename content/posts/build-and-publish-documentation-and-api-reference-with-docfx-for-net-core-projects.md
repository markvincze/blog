+++
title = "Build and publish documentation and API reference with DocFx for .NET Core projects"
slug = "build-and-publish-documentation-and-api-reference-with-docfx-for-net-core-projects"
description = "This guide shows how to generate and publish API documentation for a .NET Core library, using DocFx, GitHub Pages and AppVeyor."
date = "2017-11-17T00:00:34.0000000"
tags = [".net-core", "appveyor", "docfx"]
+++

[DocFx](http://dotnet.github.io/docfx/) is an open source tool for generating documentation and API reference, and it has great support for .NET Core projects.

DocFx can be slightly intimidating first, because it has a really wide set of features, and the default scaffolded configuration contains quite a lot of files, which at first sight can look a bit complex.

With this post I'd like to give a guide about what is a minimal configuration you need if you want to set up documentation for a .NET Core project with DocFx.  
We'll also take a look at how you can automatically publish the documentation. In that part I'll assume that the project is hosted on GitHub, so we can make the site site available using [GitHub Pages](https://pages.github.com/).

For the sake of this guide I created a dummy project called `DotnetCoreDocfxDemo`, you can find the complete source on [GitHub](https://github.com/markvincze/dotnetcore-docfx-demo).

# Install DocFX

In order to scaffold a new documentation project, serve it for testing on our machine, or to build the final version of the docs, we'll need to have the `docfx` CLI installed.

The simplest way to do this is with Chocolatey, by executing the following command.

```bash
cinst docfx -y
```

(Alternatively, we can also download and extract a release from the [Releases](https://github.com/dotnet/docfx/releases) page.)

# Set up the DocFx project

In the examples I'll assume that our repository has the following.

```
|- src/
   |- MyProject/
      |- MyProject.csproj
|- test/
   |- MyProject.UnitTests/
      |- MyProject.UnitTests.csproj
|- MySolution.sln
```

Where the `src` folder contains our main project, and the unit test projects are in the `test` folder.

If we want to use DocFx, we need to set up a *project*, which consists of a bunch of configuration and content files describing our documentation site. A typical place to put this project in is a `docs` folder at the root of our repository.

To scaffold a default DocFx project in a `docs` directory, issue the following command at the root of the repository.

```
docfx init -q -o docs
```

(`-o` specifies the output folder, while `-q` enables the "quiet" mode, so the command generates the default setup without asking any questions. If you'd like to revise the scaffolding options, omit the `-q` flag.)  
Let's review what this generated.

```md
|- api/: Configuration for the generation of the API reference.
|- articles/: Manually written pages, this is what we can use to write actual documentation.
|- images/: Image assets.
|- src/: Folder is for storing our source code projects. (I don't use this.)
|- docfx.json: The main configuration file of our documentation.
|- index.md: The content of the index page.
|- toc.yml: The main segments of our site which will be displayed in the navigation bar.
```

The root of the project contains the `index.md` and `toc.yml` files, which define the content of the main page, and the list of top-level pages.  
Other subfolders, like `articles` and `api` also contain the same pair of files, which define the same content for those areas of the site.

# Configure the API reference

In order to get the API reference generation working, we have to change our working directory to point to the folder where our source projects reside. In our example this is the `src` folder at the root of our repository (on the same level with the `docs` folder).  
We can do this by adding the `cwd` property to the object in the `src` array. Since we only need to go one level up, we can simply set it to `..`.  

```json
"src": [
  {
    "files": [
      "src/**.csproj"
    ],
    "exclude": [
      "**/obj/**",
      "**/bin/**",
      "_site/**"
    ],
    "cwd": ".."
  }
],
```

This way we are generating the API reference for every project in the `src` folder. If we want to (for example if we only want to have the reference for a subset of our projects), we can also explicitly specify the csproj files we'd like to process.

```
    "files": [
      "Project1/Project1.csproj",
      "Project2/Project2.csproj"
    ]
```

**Important**: If we are multi-targeting different .NET Framework versions in our project, we must explicitly specify one of the frameworks here, otherwise `docfx` won't be able to build the project.  
We can do this by adding `properties` to our metadata object:

```
"metadata": [
   {
     ...
     "properties": {
         "TargetFramework": "netstandard1.3"
     }
   } 
 ],
```

In the `api` folder we shouldn't manually edit the `toc.yml`, since the list of table of contents will be generated during the build based on the types we have in our assemblies.

On the other hand, we should change the content of the `index.md` file. This is the main page displayed when we navigate to the API reference, so we can change it to a welcome message, or a high-level overview about our types.  
If we want to add a link to a certain type, we can do it by specifying the full name of the type with html extension. Example:

```
[MyClass](MyProject.MyClass.html)
```

*Note: `docfx` will display a warning for "Invalid file link" when generating the documentation, but the link will work properly.*

# Set up our documentation pages

By default, an `articles` folder is generated in the DocFx project where we can add some extra documentation pages. We can do this by adding additional Markdown files to that folder, and adding them to the `toc.yml`.

If we want to, we can rename the sections of the site (or add additional sections). For example, I tend to rename the "Articles" section to "Documentation", and change "Api Documentation" to "Api Reference". If you'd like to change these, you should rename the folders (optional), adjust `docfx.json` to include these folders in the `build`, and change the `toc.yml` accordingly.

# Set up our index page

We can customize the main index page of our site in by editing the `index.md` file at the root of the DocFx project.

It's a good idea to add an introduction about our project, include a link pointing to the GitHub repo, and display the usual CI and NuGet badges.

# Testing the documentation

We can start locally serving the documentation site by entering the `docs` folder and issuing the following command. We can access the site by opening `http://localhost:8080` in the browser.

```
docfx --serve
```

**Important**: If we are working with .NET Core, we might have to set the `VSINSTALLDIR` and `VisualStudioVersion` environment variables, otherwise DocFx won't be able to build our projects. This is something I only found in various GitHub issues, and different people reported different solutions for these problems. So it might happen that this exact configuration won't work on your machine, in that case you have to adjust these values (for example if you have a different edition of Visual Studio installed, you'll have to change the path).

To make this convenient, I recommend creating a script called `serveDocs` at the root of the repository, which sets these variables and then calls `docfx --serve`.

If you use PowerShell, then `serveDocs.ps1` should look like this.

```powershell
$env:VSINSTALLDIR="C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional"
$env:VisualStudioVersion="15.0"

docfx docs/docfx.json --serve
```

If you use bash, then create this `serveDocs.sh`.

```bash
#!/bin/sh
export VSINSTALLDIR="C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional"
export VisualStudioVersion="15.0"

docfx docs/docfx.json --serve
```

# Publish the documentation

In this guide I'll show how to use [GitHub Pages](https://pages.github.com/) to host the documentation, but you can easily adjust the release script if you use a different hosting method.
In order to host a static page on GitHub Pages, we just have to push the content in our repository to a branch called `gh-pages`, and the site will be available at the address `https://accountname.github.io/RepositoryName`.

*Note: As flagged by Ben Brandt in the comments, it's important to keep in mind that the site published with GitHub Pages [is always going to be public](https://help.github.com/articles/what-is-github-pages/#guidelines-for-using-github-pages), even if it's hosted in a private repository.*

## Create the `gh-pages` branch

Since the `gh-pages` will only have to contain our static HTML content and nothing else, it's a good idea to create an empty orphan branch. We can do this in our repository with the following commands.  
**Important**: Make sure to commit everything to your work branch before you execute these commands!

```bash
git checkout --orphan gh-pages
git reset .
rm -r *
rm .gitignore
echo 'The documentation will be here.' > index.html
git add index.html
git commit -m 'Initialize the gh-pages orphan branch'
git push -u origin gh-pages
```

## Release the documentation

We can create a script to build the documentation and publish it to GitHub Pages. The following steps will be needed:

1. Create a temporary folder and clone our repository into it at the `gh-pages` branch.
2. Remove all the files from the folder.
3. Build the documentation site with `docfx` into the folder.
4. Commit and push all the changes to `gh-pages`.

We can do this by creating the following `releaseDocs.sh` script at the root of our repository.

```bash
#!/bin/sh
set -e

export VSINSTALLDIR="C:\Program Files (x86)\Microsoft Visual Studio\2017\Community"
export VisualStudioVersion="15.0"

docfx ./docs/docfx.json

SOURCE_DIR=$PWD
TEMP_REPO_DIR=$PWD/../my-project-gh-pages

echo "Removing temporary doc directory $TEMP_REPO_DIR"
rm -rf $TEMP_REPO_DIR
mkdir $TEMP_REPO_DIR

echo "Cloning the repo with the gh-pages branch"
git clone https://github.com/myaccount/my-project.git --branch gh-pages $TEMP_REPO_DIR

echo "Clear repo directory"
cd $TEMP_REPO_DIR
git rm -r *

echo "Copy documentation into the repo"
cp -r $SOURCE_DIR/docs/_site/* .

echo "Push the new docs to the remote branch"
git add . -A
git commit -m "Update generated documentation"
git push origin gh-pages
```

(Note that when setting up the necessary environment variables, I'm using the path to the Community version of Visual Studio, because that's what is installed on the AppVeyor build agents. You might have to adjust this based on your environment.)

By calling `releaseDocs.sh` we can update and publish our documentation in a single step.

# Automatically publish the docs with AppVeyor

We can include the release script in our CI-pipeline, so that the documentation gets automatically updated on every build.  
In this example I'll show how to do this with AppVeyor, but you can use the same approach with other CI-systems too.

In order to set up an AppVeyor build, we have to add an `appveyor.yml` file to the root of our repository, in which we'll describe the steps needed to build our project (and in our case publish the documentation).

The only slightly tricky part is giving AppVeyor permission to push changes to our repository.  
The recommended way to do this is to create a Personal Access Token on GitHub. We can follow [this guide](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/), and the only permission we'll need is `public_repo`. (Make sure to copy the access token to the clipboard after creating it.)

We should handle the access token as a password, so we should encrypt it before adding it to the AppVeyor config. We can do this on the AppVeyor site by clicking on our profile image, and in the menu selecting the "Encrypt data" option. Now we should add this to our yaml file as an environment variable:

```yaml
environment:
  github_access_token:
    secure: ceFfu552HHIV
```

We'll also need the email address we use as our GitHub account, and since it's better not to have it in plain text in our repository, encrypt this too and add it as an environment variable called `github_email`.

Then we need to execute a couple of commands to actually use the access token with `git`, and set up our email and user name for pushing (following [this guide](https://www.appveyor.com/docs/how-to/git-push/)).

```yaml
- git config --global credential.helper store
- ps: Add-Content "$env:USERPROFILE\.git-credentials" "https://$($env:github_access_token):x-oauth-basic@github.com`n"
- git config --global user.email %github_email%
- git config --global user.name "markvincze"
```

The last thing to do in our deploy setup is to execute our `releaseDocs.sh` script.

```yaml
- bash releaseDocs.sh
```

The full `appveyor.yml` (also building the solution and running the unit tests) should look like this:

```yaml
skip_tags: true

image: Visual Studio 2017

clone_depth: 1

branches:
  only:
    - master

environment:
  github_access_token:
    secure: ceFfu552HHkV
  github_email:
    secure: salKyeDwuc37

install:
  - cinst docfx

build_script:
- dotnet restore
- dotnet build --configuration Release

test_script:
- dotnet test test/MyProject.UnitTests/MyProject.UnitTests.csproj --configuration Release

deploy_script:
- git config --global credential.helper store
- ps: Add-Content "$env:USERPROFILE\.git-credentials" "https://$($env:github_access_token):x-oauth-basic@github.com`n"
- git config --global user.email %github_email%
- git config --global user.name "myusername"
- bash releaseDocs.sh
```

With this configuration in place, if we add our repository in AppVeyor, it will build our solution and publish the documentation on every new commit in the `master` branch.

# Summary

Following this guide we can easily set up automatically generated documentation and API reference for our open-source .NET Core libraries. (However, this post only shows the basic capabilities of DocFx, it has plenty more features that are not in the scope of this guide.)

You can find the source code of the full sample repository on [GitHub](https://github.com/markvincze/dotnetcore-docfx-demo/), and take a look at the published documentation [here](https://markvincze.github.io/dotnetcore-docfx-demo/).
