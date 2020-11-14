+++
title = "Introducing Code Fragments extension in Visual Studio Code for managing snippets during presentations"
slug = "introducing-code-fragments-extension-for-visual-studio-code"
description = "Introducing a simple Visual Studio Code extension for saving pieces of code, and later easily insert them into source files, intended for coding demos."
date = "2017-11-26T22:34:50.0000000"
tags = ["visual studio", "visual studio code", "presenting"]
+++

Recently I started working on a simple Visual Studio Code extension I'd like to introduce in this post.

Occasionally I do tech presentations, in which I usually like to do some live code demos. To make this smoother, Visual Studio has always had a really useful—although somewhat undocumented—feature, which makes it possible to save snippets of code, and easily insert them during the presentation, to save some typing.  
We can create such a "snippet" (not to be confused with actuala code snippets) by selecting a piece of code, and dropping it onto the *Toolbox* window.

Since I started to focus more on .NET Core, I wanted to use Visual Studio **Code** instead of Visual Studio during my presentations, but it was a significant drawback for me that it didn't have this feature—there is no Toolbox window where pieces of code could be easily saved.  
I could've used actual code snippets, but then I'd have to remember the alias of the snippet during the demo, and also, creating a VSCode snippet is a bit too involved for this purpose. (The other alternative would be to just prepare all the demo code in a separate file, and copy paste the necessary chunks during the presentation. But I think we can all agree that this approach is way too clunky 🙂).

I decided to implement a VSCode extension for this specific purpose, which I called [**Code Fragments**](https://marketplace.visualstudio.com/items?itemName=markvincze.code-fragments). (I used the term fragment in order not to confuse these with actual code snippets.)

I wanted to base the design on the experience the VS Toolbox provided, but I had to diverge due to the limitations of VSCode. Namely, I wasn't able to handle dragging and dropping a piece of code to the Explorer window, and also the other way around, items in the explorer tree views are not draggable.

A piece of code can be saved as a fragment by selecting it in the editor, and then executing the "Save selection as Code Fragment" from the Command Palette (brought up with Ctrl+Shift+P) or in the context menu.
Clicking on an existing fragment in the list inserts its content into the editor at the current cursor position.

This is what it looks like to save code fragments.

![Saving a Code Fragment.](/images/2017/11/codefragments-save.gif)

And inserting a Code Fragment to the current cursor position.

![Inserting a Code Fragment](/images/2017/11/codefragments-insert.gif)

This really simple extension provides a very small set of functionality, but I think it's already useful for this specific purpose.  
I'd be happy if you gave it a try, and any feedback is welcome!

You can download the extension from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=markvincze.code-fragments), and find the source code on [GitHub](https://github.com/markvincze/vscode-codeFragments).
