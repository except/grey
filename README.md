# grey

a project by @afraidlabs

# Design Choices

Preface, I suck at Swift so it might not be the best solution, and some of the stuff I quote might be wrong.
- Variti 
- - Swift provides the correct TLS fingerprint for Safari on iOS & macOS as long as you set a proper User-Agent
- Task Handling
- - WS API (Incomplete) makes managing tasks simple however there is a limit of 64 tasks due to how DispatchQueue's work.
- Speed
- - The use of the Spree API (also referred to as :zap: **Lightning mode** on [TheMobileBot](https://twitter.com/TheMobileBot/)) gave us great speed advantage theoretically bringing our request count down after completely some initiating steps to just  `ATC -> Advance Order -> Start PayPal Checkout || Start Card Checkout (Not Implemented)`

# Status

The bot is incomplete and no longer works on Off---White, however it will support stores hosted by NET2B like OAMC and Antonioli. Will probably get patched in the future.

Currently supports accounts with addresses added, and will generate PayPal checkout links to a supplied slack webhook.

# Support

Unfortunately, it is unlikely I will be offering any support or any updates to this project.

# License

[MIT](https://github.com/except/grey/blob/master/LICENSE)



