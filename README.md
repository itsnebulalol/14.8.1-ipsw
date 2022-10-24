# 14.8.1 IPSW Creator

Funny little script to make a 14.8.1 IPSW, used for pwned restores. May or may not work. Use at your own risk.

Created by Nebula and [Nick Chan](https://github.com/asdfugil), with help from galaxy#0007.

# Requirements

- macOS
- From [Procursus](https://github.com/ProcursusTeam/Procursus): aria2, ldid, 7z
    - Easiest way is to Procursus strap your Mac, then `sudo apt install aria2 ldid p7zip`
- [asr64_patcher](https://github.com/iSuns9/asr64_patcher)
- [restored_external64_patcher](https://github.com/iSuns9/restored_external64patcher)
- [trustcache](https://github.com/CRKatri/trustcache)
- [img4lib](https://github.com/pinauten/img4lib)

Binaries should be in path, easiest place is `/usr/local/bin`.

# Usage

`./makeipsw.sh <link to 14.8.1 ota> <deviceid, eg. iPhone10,6>`

It's pretty easy. Output IPSW will be in the `ipsws` folder.

# Restoring

## Requirements

- Latest futurerestore action build
- 14.8.1 OTA blob
- Generated IPSW

Restore with `--skip-blob` and `--use-pwndfu`.

Example command: `futurerestore -t 14.8.1.shsh2 --use-pwndfu --skip-blob --custom-latest-beta --custom-latest-buildid 19H12 --no-rsep --latest-sep --latest-baseband 14.8.1.ipsw`
# Licensing

14.8.1 IPSW Creator is licensed under BSD-3-Clause. The license can be found [here](https://github.com/itsnebulalol/14.8.1-ipsw/blob/main/LICENSE).
