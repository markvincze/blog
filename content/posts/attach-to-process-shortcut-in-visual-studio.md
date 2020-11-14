+++
title = "Attach to specific Process shortcut in Visual Studio"
slug = "attach-to-process-shortcut-in-visual-studio"
description = "How to create a shortcut in Visual Studio to attach the debugger to a specific process."
date = "2015-04-26T12:21:19.0000000"
tags = ["visual studio", "debug", "tooling", "visual commander"]
+++

It's a very useful feature of Visual Studio that besides starting an application for debugging, we can attach the debugger to already running processes as well.
This can be done with the **Debug->Attach to Process...** option, where we have to select the desired one from a list of all running processes.
![Attach to Process window in Visual Studio](/images/2015/04/attach_window.png)
This method of attaching to a process is OK if you have to do it only once in a while, but if you have to debug applications this way regularly, it becomes time-consuming to search for the process in the list every time.

The principle of automation has been written in many forms, this is one of the renditions:
>Anything that you do more than twice has to be automated.

This applies not just to integration, deployment, testing, etc., but  to tooling as well.
So I started looking for a more convenient way to attach to a specific process quickly.
#Visual Studio Macros
The first approach I found is to write a Visual Studio macro that looks for a specific process and attaches VS to it. This approach is described in this [Stack Overflow answer](http://stackoverflow.com/a/6696813/974733), it seemed very straightforward and promising.  
However, the first comment on the answer destroys our happiness:
>"Macros are no longer available in Visual Studio 2012."

Ok, so this is a dead end. Or is it?
#Visual Commander to the rescue!
I really like it when a popular feature of a product is removed, but the community brings it back. The same thing happened to VS macros with [Visual Commander](https://vlasovstudio.com/visual-commander/), a freemium VS extension that lets us reuse existing VS macros, and create commands and extensions using C# or VB.NET.  
After installing the extension, you can open the Commands windows with the VCMD->Commands option.
![Commands option in the VCMD menu](/images/2015/04/VCMD_menu.png)
In the Commands window we can manage our existing commands, and create a new one with the Add button.
![Commands window for managing all our existing commands](/images/2015/04/vc_commands.png)
In the command editor window can pick a name, select the language we'd like to use (C# or VB), and implement the code which will run when we execute the command.
![Command editor window of VCMD](/images/2015/04/new_command.png)
**One gotcha**: pick the desired language before starting to type the code, because if you switch to another language, all your edits are erased.  
The editor window is a bit plain, it does not support IntelliSense or automatic code formatting, so you'll might be better off writing the code in a normal Visual Studio window and insert it into the VCMD command afterwards.

The code for attaching to a process with a specific name is quite simple, as described in the above SO-answer. This is the same code translated to C#.

```csharp
using EnvDTE;
using EnvDTE80;
using System.Management;
using System;

public class C : VisualCommanderExt.ICommand
{
    public void Run(EnvDTE80.DTE2 DTE, Microsoft.VisualStudio.Shell.Package package) 
    {
        foreach(Process proc in DTE.Debugger.LocalProcesses)
        {
            if(proc.Name.ToString().EndsWith("MyApp.exe"))
            {
                proc.Attach();
                return;
            }
        }

        System.Windows.MessageBox.Show("Process running the MyApp was not found.");
    }
}
```

The above code tries to attach to a process that has a name ending with "MyApp.exe". The command in this form is already ready to use. Existing commands can be found with their specified name in the VCMD menu.
![Run existing VCMD command](/images/2015/04/attachToMyApp.png)

#Attach to a process with a specific owner user

Sometimes we can't identify the process we are looking for by it's name, but we have to use the name of the user running it.  
A typical scenario for this is when we have several web applications running in IIS. In this case all the processes have the same name, **w3wp.exe**, they only differ in the name of the user running them. (That is, if we use different application pools for each of the applications.)
![IIS processes with the same name, but different user](/images/2015/04/attach_iis.png)
##Finding out the process owner's user name
Unfortunately, the `EnvDTE.Process` [interface](https://msdn.microsoft.com/en-us/library/envdte.process.aspx) does not contain the user name, so we have to do a little additional coding to find it.  
One solution is to use WMI, which can be used in .NET with the System.Management namespace, and implement a little helper method.

```csharp
private string GetProcessOwner(int processId)
{
    string query = "Select * From Win32_Process Where ProcessID = " + processId;
    ManagementObjectSearcher searcher = new ManagementObjectSearcher(query);
    ManagementObjectCollection processList = searcher.Get();

    foreach (ManagementObject obj in processList)
    {
        string[] argList = new string[] { string.Empty, string.Empty };
        int returnVal = Convert.ToInt32(obj.InvokeMethod("GetOwner", argList));
        if (returnVal == 0)
        {
            // Return DOMAIN\user.
            return argList[1] + "\\" + argList[0];
        }
    }

    return "NO OWNER";
}
```

With this, we can implement the complete VS command attaching for a specific IIS application.

```csharp
using EnvDTE;
using EnvDTE80;
using System.Management;
using System;

public class C : VisualCommanderExt.ICommand
{
    public void Run(EnvDTE80.DTE2 DTE, Microsoft.VisualStudio.Shell.Package package) 
    {
        foreach(Process proc in DTE.Debugger.LocalProcesses)
        {
            if(proc.Name.ToString().EndsWith("w3wp.exe") && GetProcessOwner(proc.ProcessID) == "IIS APPPOOL\\MySite")
            {
                proc.Attach();
                return;
            }
        }

        System.Windows.MessageBox.Show("Process runing MySite was not found.");
    }

    private string GetProcessOwner(int processId)
    {
        string query = "Select * From Win32_Process Where ProcessID = " + processId;
        ManagementObjectSearcher searcher = new ManagementObjectSearcher(query);
        ManagementObjectCollection processList = searcher.Get();

        foreach (ManagementObject obj in processList)
        {
            string[] argList = new string[] { string.Empty, string.Empty };
            int returnVal = Convert.ToInt32(obj.InvokeMethod("GetOwner", argList));
            if (returnVal == 0)
            {
                // Return DOMAIN\user.
                return argList[1] + "\\" + argList[0];
            }
        }

        return "NO OWNER";
    }
}
```

The last thing to take care of is making sure the command has a reference to the System.Management assembly. We simply have to add the line `System.Management` in the References window.

One last thing to note is a cool feature of Visual Commander: you can create an **export** of the commands in the VCMD menu, and distribute them in your team, to make everybody debug processes as conveniently as possible!
