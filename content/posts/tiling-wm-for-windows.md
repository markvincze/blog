+++
title = "Tiling WMs, aka ricing the Windows"
slug = "tiling-wms-aka-ricing-the-windows"
description = "Using the GlazeWM tiling window manager on Windows."
date = "2025-10-12T20:00:00.0000000"
tags = ["windows", "ricing", "windowmanager", "glazem"]
+++

Throughout most of my career I worked with Microsoft technologies, mainly with .NET and C#. This meant that my daily driver operatin system has mostly been Windows, as even after the advent of .NET Core (which can be run on Linux), I had to maintain some classic .NET applications, which only ran on Windows, and could only be easily developed with Visual Studio.

But I had a short period of time during which I mainly worked on some TypeScript and NodeJS applications, and did not need Windows for my day to day work. Thus I decided to try to use Linux on my development machine. Due to my lack of experience, setting everything up and took some effort, and I remember having some struggles with certain device drivers.

One thing that made all of that worth it was to be able to use a [tiling window manager](https://en.wikipedia.org/wiki/Tiling_window_manager).
If you—like me—are mostly a Windows user, might ask what a tiling window manager is in the first place. Let's start at the beginning.

# The Windowing System

The windowing system is the part of the operating system responsible for drawing windows with their various UI components like icons, buttons, borders, etc.

A central part of the windowing system is what's called the **"display server"** or "window server", which provides an API for the various programs to render themselves on the screen, and it connects to the OS kernel to receive input from the different attached input devices, such as the keyboard and the mouse.  

And another thing is the "display server communication protocol", which is the API contract provided by the display server to the various applications.

*(The terminology around this is not perfectly clear. Even the [Wikipedia page](https://en.wikipedia.org/wiki/Windowing_system) at some point says that the display server is "the main component of the windowing system", but later it says "The display server implements the windowing system". And based on my experience the distinction between the communication protocol and the windowing system as a whole is not strictly defined. So I think these terms are used somewhat interchangably.)

## Examples

To find [concrete examples for windowing systems](https://en.wikipedia.org/wiki/List_of_display_servers), we mainlay have to look at Linux.  
On Windows, there is a dedicated windowing system since Windows Vista called [Desktop Window Manager](https://en.wikipedia.org/wiki/Desktop_Window_Manager), but to be honest I haven't heard anyone using this name before reading up on it for this post. And I could not find out if there was a specific windowing system in Windows before Vista, or this functionality was just considered an integral part of Windows.

On the other hand, on Linux the display server is another modular component of the system that we can choose an install, so the distinction between it and the rest of the OS is much more often defined and discussed.

Arguably the two most well-known windowing systems for Linux are X and Wayland.
The [X Window System](https://en.wikipedia.org/wiki/X_Window_System) (or simply X) is a long existing project, initially released in 1984, which served as the most common choice to implement GUI applications on Linux for a long time. It is also referred to as X11, because the X protocol has been at version 11 since 1987.
If you have used any GUI application on a Linux desktop machine not very recently, it was almost certainly using X.

A more recently introduced Linux windowing system is 

![Screenshot showing the 3D Aero Flip capability introduced in Windows Vista.](/images/2025/10/vista-aero-flip.png "The compositing Desktop Window Manager introduced the capability to render windows in 3D.")

