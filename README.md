# botnix
A highly modular perl bot for IRC and discord.

[![Discord Bots](https://top.gg/api/widget/630730262765895680.svg)](https://top.gg/bot/630730262765895680)

Botnix is a highly modular, highly portable IRC and Discord bot designed to be connected to multiple networks at any one time. It is lightweight, fast and expandable, written in Perl. Botnix supports SSL, IPv6 and proxies, and is currently in beta stages of development. Many modules are already tested and working, such as modules to imitate an InfoBot, or to track when users were last seen. You can download it from our subversion repository or visit our forums below. There is a sizeable amount of documentation on our wiki, and more documentation will follow as it is needed. 

**What is required to run Botnix?**

Perl (5.8.0 or above) with the Socket6 module and Digest::SHA1 module (bundled with perl or available from CPAN). For SSL support you also require the Net::SSLeay module.
I can't get ActiveState perl to install Socket6 through PPM!

A lot of the time you will find that PPM fails to install Socket6 (simply because ActiveState broke the package!). If you have problems you should install it with one of the following commands:

    ppm install http://www.botnix.org/ppm/Socket6.ppd
    ppm install http://www.open.com.au/radiator/free-downloads/Socket6.ppd

These are precompiled binary packages which will work in ActiveState perl 5.8 and will run correctly. If one command fails, this is because the required tarballs are not on the server, please try the next command in this list. If you wish to mirror this directory structure, you may find a zip of the /ppm directory here.

**What is required for Gentoo users to run Botnix?**

For the very lazy:

    emerge Socket6 Digest-SHA1 Net-SSLeay.

**Can botnix connect to discord?**

There have recently been developments allowing connection of specific modules to discord, namely the infobot module. You can connect this to discord via a special briding module found under the discord folder. This is a git submodule and can be accessed on github via: https://github.com/braindigitalis/botnix-discord - You'll need PHP 7.0 or greater on your server to run the discord connector.

**Do i need the Socket6 module even if my machine does not have ipv6 enabled?**

Yes. This is essentially a wrapper over Socket, so it is still required. It should still compile, so long as your operating system has the neccessary headers (e.g. if it's newer than around five years old... which it should be unless you like to run insecure software!)


**Can i have more than one logging module at a time?**

Yes, why not? :-) Remember to configure all the modules you use.


**Does the DCC module depend on the CTCP module, with DCC technically being a CTCP?**

No, we decided that this would be a somewhat pointless and annoying dependency.


**Why Perl?**

Because we felt like it. No, really... Perl is a text processing language, and IRC is essentially just text. Compared to high level languages like C and object languages like Python, Perl is able to process IRC text in a much more efficient manner, plus its support for regexps and its portability are second to none.


**Can i link my botnix bots together?**

Not yet.


**Why isn't my bot responding to any commands?**

You probably haven't loaded the modules/irc/cli.pm module. This module is essential if you want to issue any commands on channel or in private message. Please see the Annotated Example Config for more information.


**Are passwords case sensitive?**

Yes, also for the time being, network names are also case sensitive.


**I have the global owner flag, why won't the bot op me?**

In botnix, no flag should ever indirectly give the privilages of another flag. Therefore even if you are the bot owner you must add the 'operator' flag for yourself (addflags handle * * operator) for the bot to be able to op you.


**Where does botnix store its data?**

Botnix stores its data in two files which are specified in your configuration file. These two files are the userfile (usually with the extension .uf) and the store file (usually with the extension .store). All modules store their data in the store file, centralizing the information. Both are plaintext, however it is not recommended you edit these by hand unless you absolutely must, otherwise you may corrupt your settings.


**Can the bot join completely different channels on different networks?**

Yes, you could for example connect your bot to both ircnet and efnet, and have the bot on #one on ircnet and #two on efnet, or even on #three on both, at the same time. There are no real limitations on what can be joined and where.


**Do i have to use the same nick for my bot on all networks?**

No, you can configure a different nick, ident and GECOS (fullname field) for every network you connect your bot to.


**What does botnix support?**

Because botnix is beta software it does not yet have a full feature set. However it does support a large number of features already based upon what was learned from previous projects such as WinBot and IRC Defender, as shown below:


    Support for both IPv4 and IPv6 connections
    Support for HTTP Proxies
    SSL-encrypted IRC connections (over both IPv4 and IPv6)
    SQL Support
    Channel Mirroring (relay channel text between multiple networks)
    Support for multiple network connections in one bot process
    Modular support for CTCP
    Modular support for DCC CHAT
    Modular bot channel commands such as .OP and .BAN
    Sticky-ban support
    Powerful API with nonblocking sockets, timers and events
    Simplified bind-style configuration file format
    Mode queueing (merge several +b or +o into one line)
    Support for unrealircd founder/protect/halfop plus many InspIRCd modes and features
    Userfile and user manipulation with login/logout
    Local and global user flags (global to a network or to all networks)
    Mode enforcement (modelock)
    Channel key management
    'Floating' channel limits
    Modular command interpreter (load/unload the ability to issue commands in message or on channel etc)
    Flood protection
    Clone protection
    Support for telnet control of the bot (via a module)

**Why is botnix spamming my console?**

You didn't load a logging module. You must load and configure at least one logging module. If you do not want to log you should probably load the 'null' logging module, modules/log/null.pm.


**Why did you name this project 'botnix'? What does it mean?**

The name just sounded kind of cool. No, really.

Actually the name has two origins... Firstly, it comes from a character from the video game "Sonic The Hedgehog", called Dr Robotnik. This project being an IRC robot, it seemed perfectly apt. Not just that, but, if you take the two words bot and unix.... well, you get the idea...


**When i load botnix on windows, it says its going into the background, but then it hangs!**

It hasn't actually hung. If you have text like this in your command prompt:

    Botnix 0.4.5
    Initializing: STORE MODULES CONFIG USERS
    Done, switching to background using SW_HIDE...

Then all you need to do is press enter, and you will return to the command prompt again. The bot will continue to run in the background.


**On windows, when i close the window that started botnix, it takes botnix with it!**

There is nothing we can do about this. You should probably bug the perl win32 maintainers and get them to fix the severely broken fork emulation on windows which stops perl programs forking normally.

If this bugs you, find another use for the console after you spawn botnix. Fire up lynx or something.


**Will botnix let me connect the same bot multiple times to the same network with different nicks?**

Yes, but why would you want to do this legitimately? To do this, simply give each connection a different network name. 
