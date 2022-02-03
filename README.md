# Covid Pass Decoder

A sample Swift project to demonstrate how to decode and check the validity of an NHS Domestic Covid pass.

Step 1: Fetch the current NHS keys from https://covid-status.service.nhsx.nhs.uk/pubkeys/keys.json and store them locally (I have included a keys.json file within the bundle with the keys at time of writing)

Step 2: Scan a QR code. You'll end up with something like this:

`HC1:6BFOXN%TSMAHN-H%RCHJOHEE/7I2SL3J40:5NR68LE6H9OGI/LA%-VM7D7/ISSF4LD43MVJJ7PO7UODFHT-HNTI4L6N$Q%UG/YL WO*Z7ON13:L:-J$R1LU9:V5O P.T1..PZS5KWOQZPV*BKO8IO8:PIBZQX+JV*B$*R7LAXE5I$HPYH9UESCG.77-HQ/SPZHQ% O6ZRYGO:CO-B5SO2ORD%PD9F1QW6UCGY+CO6DKDFWN5QWCD4D-T4CP4W%SXSAOY2707978M1NL+9AKPCPP0%M 76JZ68Q008KI7JSTNB95.16U0PDZ4U9SR95W169NP5CQYNQIVQCA7T5MIH5:ZJ$2B322UM97H98$QJEQ8BHW89PB7Y:5/MMR8N9EV4:PCDCJUL7%8*57GHE6-V4UH:EF+$IT0362LQFLUEKDISA1F /LA2DUX4H1NLHP :J6%V6TEB7R9IBXB372U000D892+E`

Step 3: Initiate the `CovidPassDetector` with the fetched keys and then decode using the HC1 string from the QR code:

```
let decoder = try CovidPassDecoder(keys: keys)
let cwt = try decoder.decodeHC1(barcode: qrCode)
let isValid = cwt.isValid(using: DefaultDateService())
```

The `CWT` contains all the information within the pass (i.e. issuing country, issued at date, expiration date, passholders name and date of birth) and there are convenience methods to determine if the pass is currently valid.

**NOTE**: This project includes [SwiftCBOR](https://github.com/unrelentingtech/SwiftCBOR) as a dependency via Swift Package Manager.