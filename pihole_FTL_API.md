# Query Pi-hole FTLv6's API from shell

Small tool to query the new API introduced with FTLv6.
For available endpoints see your local API documentation at
[pi.hole:8080/api/docs/](pi.hole:8080/api/docs/)

This script can also connect **remotely** to your Pi-hole by using the provides options.

```shell
Usage: ./query_FTL_API.sh [-u <URL>] [-p <port>] [-a <path>] [-s <secret password>]
```

See `-h` for help.

___

Sample output

```shell
./query_FTL_API.sh -u 10.0.1.24
Authentication failed.
No password supplied. Please enter your password:

Authentication successful.

Request data from API endpoint:
/dns/cache
{
        "size": 10000,
        "inserted":     0,
        "evicted":      0,
        "valid":        {
                "ipv4": 0,
                "ipv6": 0,
                "cname":        0,
                "srv":  0,
                "ds":   0,
                "dnskey":       0,
                "other":        0
        },
        "expired":      0,
        "immortal":     34
}

Request data from API endpoint:
/version
{
        "web":  {
                "branch":       "new/FTL_is_my_new_home",
                "tag":  "v5.5-64-g0aace934"
        },
        "core": {
                "branch":       "master",
                "tag":  "v5.10-0-g853f6b7d"
        },
        "ftl":  {
                "branch":       "new/http",
                "tag":  "vDev-8a5d06b",
                "date": "2022-01-15 15:58:36 +0100"
        }
}
```

To interact with the `json` output I recommend `jq`. See [https://stedolan.github.io/jq/](https://stedolan.github.io/jq/)
