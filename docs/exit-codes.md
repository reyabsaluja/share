# Exit codes

| Code | JSON `error.code` | Meaning | Typical cause |
|------|-------------------|---------|---------------|
| 0 | – | Success (including dry runs) | |
| 1 | `error` | Unexpected failure | Bug or unhandled OS error |
| 2 | `usage`, `invalid_url` | Bad arguments | Unknown option, no recipient, malformed URL |
| 3 | `input_not_found` | A path does not exist | Typo in a file name |
| 4 | `packaging_failed` | Zip creation failed | `ditto` error, disk full |
| 5 | `backend_unavailable` | Required app/tool missing or unreachable | AirDrop off, port taken, no LAN address |
| 6 | `cancelled` | The user (or non-interactive policy) cancelled | AirDrop picker closed, secrets prompt declined |
| 7 | `automation_denied` | macOS refused automation | Automation permission not granted for the terminal |
| 8 | `unsupported` | The operation makes no sense for the input | `share serve https://…` |
| 9 | `sharing_failed` | The backend reported an error | AppleScript error, recipient not reachable |
| 10 | `timeout` | Waited too long | AirDrop panel left open beyond `airdropTimeout` |
| 11 | `config_error` | Invalid config key or value | `share config set smart maybe` |
| 12 | `refused` | A safety guard stopped the command | Packaging `/`, overwriting without `--force`, too large for non-interactive mode |
| 64 | `error` | Argument parsing error from the CLI framework | Missing required argument |

`share doctor` exits 1 when a required component is missing.
