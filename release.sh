#!/bin/sh
set -e

echo "Run the hugo build"
hugo

SOURCE_DIR=$PWD
TEMP_REPO_DIR=$PWD/../my-project-gh-pages

echo "Removing temporary doc directory $TEMP_REPO_DIR"
rm -rf $TEMP_REPO_DIR
mkdir $TEMP_REPO_DIR

echo "Cloning the repo with the gh-pages branch"
git clone https://github.com/markvincze/blog.git --branch gh-pages $TEMP_REPO_DIR

echo "Clear repo directory"
cd $TEMP_REPO_DIR
git rm -r *

echo "Copy documentation into the repo"
cp -r $SOURCE_DIR/public* .

echo "Push the new blog to the remote branch"
git add . -A
git commit -m "Update blog content"
git push origin gh-pages
