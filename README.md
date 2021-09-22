# Purple Haze

A DNS tunnel client for iOS based on [Iodine][1]. A paid Apple Developer account is required to build because of the entitlements needed for [Network Extensions][2].

## Build

1. Make sure you cloned the submodules: `git submodule init && git submodule update`
2. Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and fill in `DEVELOPMENT_TEAM` with your Team ID [(found here)][3] and choose a unique `PRODUCT_BUNDLE_PREFIX`.
3. Open `PurpleHaze.xcodeproj` and build it.

## About

### What's with the name?

* "Purple Haze" is a great Jimi Hendrix song.
* [Iodine][1], the DNS tunnel this project is based off (itself named after the atomic number 53 which is also the port number for DNS), is a purple gas at room temperature.
* Purple was the [codename for the original iPhone](https://en.wikipedia.org/wiki/List_of_Apple_codenames#iPhone).

[1]: https://github.com/yarrick/iodine
[2]: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
[3]: https://developer.apple.com/account/#!/membership
