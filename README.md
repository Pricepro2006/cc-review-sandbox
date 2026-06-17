# cc-review-sandbox

CommandCenter review pipeline sandbox. Public throwaway repo for proving the
CMDC-0004 out-of-run review subsystem (4A read-only review, later 4B/4C).
No sensitive content, ever.

- 2026-06-13: CMDC-0007b ntfy notification acceptance run completed.
- 2026-06-17: CMDC-0007b ntfy notification acceptance run completed.

## parsePort

Converts a PORT configuration string to an integer.

```js
const { parsePort } = require('./src/parsePort');
const port = parsePort(process.env.PORT || '3000'); // 3000
```
