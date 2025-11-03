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

A more recently introduced Linux windowing system is called [Wayland](https://en.wikipedia.org/wiki/Wayland_(protocol)), which is intended to be a successor of X, and [it is now the default](https://en.wikipedia.org/wiki/Wayland_(protocol)#Desktop_Linux_distributions) for multiple popular Linux distributions, like Ubuntu, Fedora and Debian.

There are other display server implementations out there, but their usage is less common, or they are mostly targeting scenarios other than desktop PCs, for example [Mir](https://en.wikipedia.org/wiki/Mir_(software)), which is mostly used for Internet of Things applications.

# Desktop Environment

In order to be able to use our desktop computer for everyday tasks involving GUI applications, we need a system running on top of the OS utilizing the display server to provide us a way to start applications and switch between them, and potentially provide other convenience features, like displaying a list of the running apps, providing a status bar, being able to resize application windows, etc.

One such type of software, arguably the one which is most widely used, especially by non-technical users, is a [desktop environment](https://en.wikipedia.org/wiki/Desktop_environment). A desktop environment is a software and potentially a bundle of additional loosely connected programs, implementing features we are used to see on the GUI of a desktop PC, such as icons, windows, toolbars, wallpapers, and various additional desktop widgets, wnd it often also supports drag and drop interaction. As Wikipedia states:

>A desktop environment aims to be an intuitive way for the user to interact with the computer using concepts which are similar to those used when interacting with the physical world, such as buttons and windows.

![Screenshot showing the Maxx desktop environment.](/images/2025/10/maxx-desktop-environment.png "The MaXX desktop environment, showing various windows and icons.")

Popular Linux desktop environments include [GNOME](https://en.wikipedia.org/wiki/GNOME), [KDE](https://en.wikipedia.org/wiki/KDE_Plasma) and [Xfce](https://en.wikipedia.org/wiki/Xfce), each being the defalt for some distributions, like GNOME for Ubuntu, KDE for openSUSE, and Xfce for Manjaro.

# Window Manager

Desktop environments provide a fully fledged GUI suitable to be used by everyday non-technical users. A [Window manager](https://en.wikipedia.org/wiki/Window_manager) is a software controlling the placement of windows on the screen. A desktop environment typically includes a default window manager, for example GNOME uses [Mutter](https://mutter.gnome.org), and KDE uses [KWin](https://en.wikipedia.org/wiki/KWin) by default.

However, a window manager can also be used by itself in lieu of a desktop environment to be the main way to interact with the system. This approach is typically chosen by power users, as setting up a window manager is less streamlined, their feature set is more low level and lightweight, and controlling them often includes several hotkeys which need to be memorized.

Window managers are typically categorized based on how they support positioning windows on the screen. For example stacking window managers typically support freely moving and resizing windows, which can cover each other.  
Compositing window managers (or compositors) typically implement fancy effects such as 3D transformation, blending, fading, drop shadows, etc. A prominent example for this is the Desktop Window Manager in Windows introduced in Vista, which added 3D effects, or Compiz for Linux, which is known for its 3D transformations, for example rendering windows on the surface of a cube.

![Screenshot showing the 3D Aero Flip capability introduced in Windows Vista.](/images/2025/10/vista-aero-flip.png "The compositing Desktop Window Manager introduced the capability to render windows in 3D.")

![Screenshot showing the the 3D rendering capabilities of Compiz.](/images/2025/10/compiz-cube.png "A typical example to showcase the 3D capabilities in Compiz was to render windows on faces of a cube.")

## Tiling window managers

The type of window manager most often used by power users and developers is the [tiling window manager](https://en.wikipedia.org/wiki/Tiling_window_manager). Instead of opening windows stacked on top of each other, and allowing for the windows to be freely movable and resizable with a mouse, a tiling window manager automatically positions and sizes windows so that they are evenly distributed on the available screen real estate. When your screen is empty, and you open a new window, that opens full screen. If you open a second window, then typically the screen will be split in half for the two windows, and so on—hence the name tiling.  
Usually windows can be moved or resized with keyboard shortcuts, and their distribution can be switched between horizontal or vertical.

![Screenshot showing a typical tiling window setup with i3.](/images/2025/10/tiling-wm-i3.png "i3 is a typical tiling window manager for the X window system.")

This setup can be very efficient for folks used to mainly using the keyboard and memorizing shortcuts, especially for development when working with terminals, where we often want to open multiple shells and/or code editors open at the same time, which fits the tiling layout really well.

There are several such window managers, some still actively maintained ones for X are [i3](https://i3wm.org), [awesomewm](https://awesomewm.org) and [dwm](https://dwm.suckless.org). As the basics of the tiling system can be implemented with relatively little amount of code, several other projects exist created in all sorts of programming languages. My favorite example is [xmonad](https://xmonad.org), which is a tiling window manager implemented in Haskell, as indicated by one of the photos on its website 🙂.

![Photo showing the xmonad window manager running on 3 monitors.](/images/2025/10/xmonad.jpg "As top tier nerdy things go, implementing a window manager in Haskell is certainly up there. ")

As Wayland is a modern alternative to X, new and more modern window managers appeared targeting it. One example is [Sway](https://swaywm.org), which is a drop-in replacement for i3. And the one which seems to have the most buzz is [Hyprland](https://hypr.land). While some other window managers like [ratpoison](https://www.nongnu.org/ratpoison/) intentionally don't want to support any fancy effects such as animations, custom border designs, etc. Hyprland has extensive support for eye candy to be able to create a really aestheticly pleasing yet functional UI.


