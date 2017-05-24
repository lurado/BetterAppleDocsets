# BetterAppleDocsets
## Fine-tuned Apple API Docsets for Dash

[Dash](https://kapeli.com/dash) supports Apple’s new, unified API reference for macOS, iOS, tvOS and watchOS. However:

* you cannot filter by platform.
* types are not clickable.
* information density suffers from huge headlines and generous whitespace.

<img src="screenshots/before.png" width="600">

BetterAppleDocsets is a [Ruby script](./bad.rb) that extracts a configurable subset of the API reference and tweaks the CSS at the same time.

<img src="screenshots/after.png" width="600">

## Quick start

Make sure you've got the latest "Apple API Reference" installed in Dash. Then run the 
following commands in your Terminal:

```bash
gem install sqlite3 # or "sudo gem install sqlite3" if you use Apple’s Ruby
curl -O https://raw.githubusercontent.com/lurado/BetterAppleDocsets/master/bad.rb
ruby bad.rb --language=objc --platform=ios --output=~/Desktop
# this takes a while, let it run in the background...
# double-click the generated ~/Desktop/iOS_API_Reference.docset
```

Run `ruby bad.rb --help` for the full command-line reference.

(You should repeat this after each major Xcode update to refresh your docset.)

If you see this warning while adding your docset to Dash, simply ignore it and click _Install_:

<img src="screenshots/warning.png" width="410">

## Some details

BetterAppleDocsets requires the “Apple API Reference” docset to be installed in Dash (latest version).

It will not touch the existing docset, but instead create a new docset by running the following steps:

1. Extract every HTML file from Xcode’s embedded docset.
2. Remove each language from the search index that has not been whitelisted with `--language=objc` or `--language=swift`.
3. Remove each platform that has not been whitelisted with `--platform=...os`, and add hyperlinks to type names at the same time.
4. Append custom CSS to the styles of the extracted docset.
5. Change the name and keyword of the generated docset in the docset’s Info.plist file.

The best place to start reading and hacking the source code is the method `BetterAppleDocsets#run(args)`.

## License

BetterAppleDocsets is released under the [MIT license](LICENSE).
