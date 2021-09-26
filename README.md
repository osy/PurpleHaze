# Purple Haze

A DNS tunnel client for iOS based on [Iodine][1]. A paid Apple Developer account is required to build because of the entitlements needed for [Network Extensions][2].

## Build

1. Make sure you cloned the submodules: `git submodule init && git submodule update`
2. Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and fill in `DEVELOPMENT_TEAM` with your Team ID [(found here)][3] and choose a unique `PRODUCT_BUNDLE_PREFIX`.
3. Open `PurpleHaze.xcodeproj` and build it.

## Usage

[Read iodine's documentations for instructions on setting up a server.][1] Once you have `iodined` running on your computer and the nameserver pointed to your IP, you can tunnel into the private subnet created by `iodined` from Purple Haze. Note that without additional configuration, you cannot use the tunnel to browse the web (or connect to WAN). You can then setup a SSH tunnel (by connecting to `10.0.0.1` or whatever your iodine server IP is set to) or a HTTP(S) proxy and configuring Purple Haze to use that proxy in the advanced settings.

If you are running `iodined` on a Linux machine/VM, then you can do the following to forward the TAP traffic to the internet.

```
# sysctl -e net.ipv4.ip_forward=1
# iptables -t nat -A POSTROUTING -s 10.0.0.0/255.255.224.0 -o eth0 -j MASQUERADE
```

(Where `10.0.0.0/255.255.224.0` is the IP/subnet of your `iodined` TAP interface and `eth0` is the Ethernet interface.) Note this could pose a security issue as Iodine's authentication is pretty weak.

## Troubleshooting Tips

* Make sure you built and are running the same release of [iodine][1] server from GitHub as the client in Purple Haze.
* Iodine server seems more stable on Linux than macOS. If you are having trouble connecting to iodined, try running it from a Linux VM.
* Try running iodine client on your computer on the same network to debug connection issues.
* DNS tunneling to bypass paid WiFi is a well known trick and likely won't work on any modern network.

## About

### What's with the name?

* "Purple Haze" is a great Jimi Hendrix song.
* [Iodine][1], the DNS tunnel this project is based off (itself named after the atomic number 53 which is also the port number for DNS), is a purple gas at room temperature.
* Purple was the [codename for the original iPhone](https://en.wikipedia.org/wiki/List_of_Apple_codenames#iPhone).

[1]: https://github.com/yarrick/iodine
[2]: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
[3]: https://developer.apple.com/account/#!/membership
