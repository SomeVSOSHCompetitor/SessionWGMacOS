Example implementation of SessionWG specification.
Won't work on unedited devices setup. You need to enable sudo nopasswd access for a `/usr/local/sbin/wg-quick-brewbash` with the following content
```
#!/bin/sh
exec /opt/homebrew/bin/bash /opt/homebrew/bin/wg-quick "$@"
```

This is made because Apple won't give me ADP so i could use NetworkExtension like i should
